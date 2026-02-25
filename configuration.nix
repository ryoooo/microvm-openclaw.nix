{ config, pkgs, pkgs-unstable, wezterm, microvm, home-manager, nix-openclaw, nix-openclaw-defender, nix-steipete-gogcli, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ── System services ───────────────────────────────────────
  services.tailscale.enable = true;
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      ListenAddress = "127.0.0.1";
    };
  };

  # ... (省略: シェル, 日本語入力, AI/ML サービス, Home Manager デスクトップ設定,
  #  Hyprland, WezTerm, Waybar, Dunst, Rofi, パッケージ等)

  # ── Bootloader ────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.kernelModules = [
    "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"
  ];

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # ── Locale / Timezone ─────────────────────────────────────
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "ja_JP.UTF-8";

  # ... (省略: GPU ドライバ, GDM/GNOME, Hyprland system-level, XDG Portal,
  #  セッション環境変数, Bluetooth, PipeWire, ユーザー定義)

  # ── User ──────────────────────────────────────────────────
  users.users.ryoki = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "kvm" ];
  };

  nixpkgs.config.allowUnfree = true;

  # バイナリキャッシュ（microvm.nix + llm-agents.nix）
  nix.settings = {
    extra-substituters = [ "https://microvm.cachix.org" "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "microvm.cachix.org-1:oXnBc6hRE3eX5rSYdRyMYXnfzcCxC7yKPTbZXALsqyn="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  # virtiofs で /nix/store を共有する場合、optimise は stale file handle を起こす
  nix.optimise.automatic = false;

  # ── System packages (dev tools) ───────────────────────────
  environment.systemPackages = with pkgs; [
    neovim
    jq fd ripgrep
    # ... (省略: デスクトップアプリ, 開発ツール)
  ];

  # ════════════════════════════════════════════
  #  microVM ネットワーク — NetworkManager 共存
  # ════════════════════════════════════════════

  # NetworkManager が microVM インターフェースを無視するよう設定
  networking.networkmanager.unmanaged = [
    "interface-name:microbr"
    "interface-name:microvm*"
    "interface-name:veth*"
  ];

  # systemd-networkd でブリッジ + TAP を管理
  # (networking.useNetworkd は設定しない → NM と共存)
  systemd.network.enable = true;

  systemd.network.netdevs."20-microbr".netdevConfig = {
    Kind = "bridge";
    Name = "microbr";
  };

  systemd.network.networks."20-microbr" = {
    matchConfig.Name = "microbr";
    addresses = [{ Address = "192.168.83.1/24"; }];
    networkConfig.ConfigureWithoutCarrier = true;
  };

  systemd.network.networks."21-microvm-tap" = {
    matchConfig.Name = "microvm*";
    networkConfig.Bridge = "microbr";
  };

  # NAT (VM → インターネット)
  networking.nat = {
    enable = true;
    internalInterfaces = [ "microbr" ];
    externalInterface = "eno1";
  };

  # ════════════════════════════════════════════
  #  ファイアウォール + nftables egress ログ
  # ════════════════════════════════════════════

  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    interfaces.microbr = {
      allowedUDPPorts = [ 53 ];  # VM → Unbound DNS のみ許可
    };
  };

  networking.nftables.enable = true;
  networking.nftables.tables.microvm-egress = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority 10; policy accept;
        iifname "microbr" oifname "microbr" ip saddr 192.168.83.2 ip daddr 192.168.83.3 tcp dport 22 accept
        iifname "microbr" oifname "microbr" ct state established,related accept
        iifname "microbr" oifname "microbr" drop
        iifname "microbr" ct state new log prefix "microvm-egress: " accept
      }
    '';
  };

  # ════════════════════════════════════════════
  #  DNS ログ — Unbound (microVM 専用)
  # ════════════════════════════════════════════

  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "192.168.83.1" ];
        access-control = [ "192.168.83.0/24 allow" ];
        verbosity = 1;
        log-queries = "yes";
      };
      forward-zone = [{
        name = ".";
        forward-addr = [ "1.1.1.1" "8.8.8.8" ];
      }];
    };
  };

  # ════════════════════════════════════════════
  #  セキュリティ監査
  # ════════════════════════════════════════════

  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [
    "-w /var/lib/microvms/openclaw/secrets/ -p rwa -k openclaw-secrets"
    "-w /var/lib/microvms/gogcli/secrets/ -p rwa -k gogcli-secrets"
  ];

  services.chrony.enable = true;

  # ════════════════════════════════════════════
  #  microVM — gogcli (Google Suite 隔離)
  # ════════════════════════════════════════════

  microvm.vms.gogcli = {
    config = {
      imports = [ ./vms/gogcli.nix ];
      nixpkgs.overlays = [
        (final: prev: {
          gogcli = nix-openclaw.inputs.nix-steipete-tools.packages.${final.stdenv.hostPlatform.system}.gogcli;
        })
      ];
    };
    autostart = true;
  };
  systemd.services."microvm@gogcli".serviceConfig.TimeoutStartSec = "120";

  systemd.services.gogcli-prepare-secrets = {
    description = "Stage secrets for gogcli microVM";
    wantedBy = [ "microvm@gogcli.service" ];
    before = [ "microvm@gogcli.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      dir=/var/lib/microvms/gogcli/secrets
      mkdir -p "$dir"
      chmod 0755 "$dir"
      # OpenClaw → gogcli 用 SSH 鍵ペアを生成
      if [ ! -f "$dir/ssh-key" ]; then
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f "$dir/ssh-key" -C "openclaw-to-gogcli"
      fi
      # command= 付き authorized_keys を生成
      printf 'command="/etc/gogcli/wrapper.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding %s\n' \
        "$(cat "$dir/ssh-key.pub")" > "$dir/authorized-keys"
      chmod 0444 "$dir"/*
    '';
  };

  # ════════════════════════════════════════════
  #  microVM — OpenClaw
  # ════════════════════════════════════════════

  microvm.vms.openclaw = {
    specialArgs = {
      defenderPluginPath = nix-openclaw-defender.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-defender-plugin.pluginPath;
      openclawHmModule = nix-openclaw.homeManagerModules.openclaw;
      inherit nix-steipete-gogcli;
    };
    config = {
      imports = [
        ./vms/openclaw.nix
        home-manager.nixosModules.home-manager
        nix-openclaw-defender.nixosModules.default
      ];
      nixpkgs.overlays = [ nix-openclaw.overlays.default ];
    };
    autostart = true;
  };

  # VM 起動 + ML モデルロード（ExecStartPost ヘルスチェック）に時間がかかるためタイムアウトを延長
  systemd.services."microvm@openclaw".serviceConfig.TimeoutStartSec = "300";

  systemd.services.openclaw-prepare-secrets = {
    description = "Stage secrets for OpenClaw microVM";
    wantedBy = [ "microvm@openclaw.service" ];
    before = [ "microvm@openclaw.service" ];
    after = [ "gogcli-prepare-secrets.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      dir=/var/lib/microvms/openclaw/secrets
      mkdir -p "$dir"
      chmod 0755 "$dir"
      ${pkgs.openssl}/bin/openssl rand -base64 32 > "$dir/gateway-token"
      # Gateway 用統合 EnvironmentFile を生成
      : > "$dir/gateway-env"
      [ -f "$dir/openrouter-api-key" ] && echo "OPENROUTER_API_KEY=$(cat "$dir/openrouter-api-key")" >> "$dir/gateway-env"
      [ -f "$dir/cerebras-api-key" ] && echo "CEREBRAS_API_KEY=$(cat "$dir/cerebras-api-key")" >> "$dir/gateway-env"
      [ -f "$dir/discord-bot-token" ] && echo "DISCORD_BOT_TOKEN=$(cat "$dir/discord-bot-token")" >> "$dir/gateway-env"
      [ -f "$dir/brave-api-key" ] && echo "BRAVE_API_KEY=$(cat "$dir/brave-api-key")" >> "$dir/gateway-env"
      echo "DEFENDER_WATCH_FILES=openclaw.json" >> "$dir/gateway-env"
      echo "DEFENDER_PROTECTED_FILES=openclaw.json" >> "$dir/gateway-env"
      # gogcli SSH 秘密鍵をコピー (OpenClaw VM → gogcli VM 接続用)
      gogcli_key=/var/lib/microvms/gogcli/secrets/ssh-key
      [ -f "$gogcli_key" ] && cp "$gogcli_key" "$dir/gogcli-ssh-key"
      chmod 0444 "$dir"/*
    '';
  };

  system.stateVersion = "25.11";
}

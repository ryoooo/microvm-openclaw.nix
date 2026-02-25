{ config, pkgs, lib, defenderPluginPath, openclawHmModule, nix-steipete-gogcli, ... }:

{
  networking.hostName = "openclaw-vm";
  system.stateVersion = "25.11";

  microvm = {
    hypervisor = "cloud-hypervisor";
    vsock.cid = 3;
    vcpu = 4;
    mem = 4096;

    shares = [
      {
        proto = "virtiofs";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }
      {
        proto = "virtiofs";
        tag = "secrets";
        source = "/var/lib/microvms/openclaw/secrets";
        mountPoint = "/run/secrets";
      }
    ];
    writableStoreOverlay = "/nix/.rw-store";

    volumes = [{
      mountPoint = "/persist";
      image = "persist.img";
      size = 4096;
    }];

    interfaces = [{
      type = "tap";
      id = "microvm-oc";
      mac = "02:00:00:00:00:01";
    }];
  };

  # VM 内ネットワーク (IPv6 無効: ホスト NAT が IPv4 のみ、Node.js undici の Happy Eyeballs 問題回避)
  networking.enableIPv6 = false;
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
  };
  systemd.network.enable = true;
  systemd.network.networks."10-eth" = {
    matchConfig.Name = "e*";
    addresses = [{ Address = "192.168.83.2/24"; }];
    routes = [{ Gateway = "192.168.83.1"; }];
  };
  networking.nameservers = [ "192.168.83.1" ];

  # ユーザー
  users.users.openclaw = {
    isNormalUser = true;
    home = "/persist/openclaw";
    createHome = true;
    group = "openclaw";
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... your-key-here"
    ];
  };
  users.groups.openclaw = {};

  # Prompt Guard 2 classifier (Layer 2, gated model)
  services.openclaw-defender.prompt-guard = {
    enable = true;
    port = 8000;
    modelSize = "86m";
    device = "cpu";
    modelCacheDir = "/persist/openclaw-defender/prompt-guard";
    hfTokenFile = "/run/secrets/hf-token";
  };

  # DeBERTa v3 prompt injection classifier (Layer 2)
  services.openclaw-defender.deberta = {
    enable = true;
    port = 8001;
    device = "cpu";
    modelCacheDir = "/persist/openclaw-defender/deberta";
  };

  # /persist マウント後にホームディレクトリを作成 + Gateway 自動起動用シンボリックリンク
  # Home Manager .bak 残留ファイルを起動時に削除（HM activation 失敗防止）
  systemd.tmpfiles.rules = [
    "r /persist/openclaw/.openclaw/*.bak* - - - - -"
    "r /persist/openclaw/.openclaw/workspace/*.bak* - - - - -"
    "d /persist/openclaw 0755 openclaw openclaw -"
    "d /persist/openclaw/.config/systemd/user/default.target.wants 0755 openclaw openclaw -"
    "L /persist/openclaw/.config/systemd/user/default.target.wants/openclaw-gateway.service - openclaw openclaw - /persist/openclaw/.config/systemd/user/openclaw-gateway.service"
    "d /tmp/openclaw 0755 openclaw openclaw -"
    "d /persist/openclaw/.openclaw/skills 0755 openclaw openclaw -"
    "d /persist/openclaw-defender 0755 root root -"
    "d /persist/openclaw-defender/prompt-guard 0755 root root -"
    "d /persist/openclaw-defender/deberta 0755 root root -"
  ];

  # Gateway の PDF→画像変換 (opencv/numpy) に必要な共有ライブラリ
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    libgcc.lib
    zlib
    glib.out
    libGL
    mesa
    libx11
    libxcb
    libxext
    libxrender
    libxi
    libxfixes
    libxcursor
    libxrandr
    libsm
    libice
    fontconfig
    freetype
    libpng
    libjpeg
    libtiff
    libwebp
    harfbuzz
    cairo
    pango
    gdk-pixbuf
    expat
    dbus
  ];

  environment.systemPackages = with pkgs; [
    curl jq
    poppler-utils  # pdftoppm: Gateway の PDF→画像変換 (Vision フォールバック) に必要
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # ── Home Manager ──────────────────────────────────────────
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "bak";
  # .bak が残留していても HM activation が上書きできるようにする
  systemd.services.home-manager-openclaw.environment.HOME_MANAGER_BACKUP_OVERWRITE = "1";
  # Gateway がシンボリンクを通常ファイルに上書きするため、HM activation 前に除去
  systemd.services.openclaw-pre-hm-cleanup = {
    description = "Remove regular files that HM manages as symlinks";
    wantedBy = [ "home-manager-openclaw.service" ];
    before = [ "home-manager-openclaw.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for f in /persist/openclaw/.openclaw/openclaw.json \
               /persist/openclaw/.openclaw/workspace/AGENTS.md \
               /persist/openclaw/.openclaw/workspace/SOUL.md \
               /persist/openclaw/.openclaw/workspace/TOOLS.md \
               /persist/openclaw/.openclaw/workspace/nix-mcp-plan.md; do
        [ -f "$f" ] && [ ! -L "$f" ] && rm -f "$f"
      done
      # .bak 残留も除去
      rm -f /persist/openclaw/.openclaw/*.bak* /persist/openclaw/.openclaw/workspace/*.bak*
    '';
  };
  home-manager.users.openclaw = {
    imports = [ openclawHmModule ];
    home.username = "openclaw";
    home.homeDirectory = "/persist/openclaw";
    home.stateVersion = "25.11";
    # gogcli: 透過的に gogcli VM で gog を実行する SSH ラッパー (OpenClaw バンドルの gog を上書き)
    home.packages = [
      (lib.hiPrio (pkgs.writeShellScriptBin "gog" ''
        exec ${pkgs.openssh}/bin/ssh \
          -o StrictHostKeyChecking=accept-new \
          -o BatchMode=yes \
          -i /run/secrets/gogcli-ssh-key \
          gogcli@192.168.83.3 \
          gog "$@"
      ''))
    ];
    # Gateway user service に環境変数を注入
    systemd.user.services.openclaw-gateway.Service = {
      EnvironmentFile = "-/run/secrets/gateway-env";
      Environment = [
        "PATH=/run/current-system/sw/bin:/run/wrappers/bin:/persist/openclaw/.nix-profile/bin"
        "QT_QPA_PLATFORM=offscreen"  # opencv-python バンドルの Qt xcb プラグイン (ELFCLASS32) を回避
      ];
    };
    programs.openclaw.documents = ../docs;
    # gogcli ファーストパーティスキル (nix-steipete-tools)
    home.file.".openclaw/workspace/skills/gog" = {
      source = "${nix-steipete-gogcli}/skills/gog";
      recursive = true;
    };
    programs.openclaw.instances.default = {
      enable = true;
      systemd.enable = true;
      config = {
        plugins.load.paths = [ defenderPluginPath ];
        plugins.allow = [ "openclaw-defender" ];
        gateway = {
          mode = "local";
          bind = "loopback";
          auth = {
            mode = "token";
            token = "/run/secrets/gateway-token";
          };
          reload.mode = "hybrid";
          http.endpoints.responses.files.pdf = {
            maxPages = 20;
            maxPixels = 5000000;
            minTextChars = 50;
          };
        };
        channels.discord = {
          enabled = true;
          dmPolicy = "pairing";
          groupPolicy = "open";
          guilds."*" = {
            requireMention = true;
            tools.deny = [];
          };
        };
        agents.defaults = {
          model.primary = "openai-codex/gpt-5.3-codex";
          model.fallbacks = [ "openrouter/z-ai/glm-5" ];
          sandbox.mode = "off";
        };
        tools.deny = [ "gateway" "cron" "elevated" ];
        discovery.mdns.mode = "minimal";
      };
    };
  };
}

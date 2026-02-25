{ config, pkgs, lib, ... }:

{
  networking.hostName = "gogcli-vm";
  system.stateVersion = "25.11";

  microvm = {
    hypervisor = "cloud-hypervisor";
    vsock.cid = 4;
    vcpu = 1;
    mem = 512;

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
        source = "/var/lib/microvms/gogcli/secrets";
        mountPoint = "/run/secrets";
      }
    ];
    writableStoreOverlay = "/nix/.rw-store";

    volumes = [{
      mountPoint = "/persist";
      image = "persist.img";
      size = 1024;
    }];

    interfaces = [{
      type = "tap";
      id = "microvm-gog";
      mac = "02:00:00:00:00:02";
    }];
  };

  # VM 内ネットワーク (IPv6 無効: ホスト NAT が IPv4 のみ)
  networking.enableIPv6 = false;
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
  };
  systemd.network.enable = true;
  systemd.network.networks."10-eth" = {
    matchConfig.Name = "e*";
    addresses = [{ Address = "192.168.83.3/24"; }];
    routes = [{ Gateway = "192.168.83.1"; }];
  };
  networking.nameservers = [ "192.168.83.1" ];

  # ユーザー
  users.users.gogcli = {
    isNormalUser = true;
    home = "/persist/gogcli";
    createHome = true;
    group = "gogcli";
    # authorized_keys は /run/secrets/authorized-keys (command= 付き) のみ使用
    # 個人鍵を置くと command= 制限をバイパスしてフルシェルが取れてしまう
  };
  users.groups.gogcli = {};

  # /persist マウント後にディレクトリを作成
  systemd.tmpfiles.rules = [
    "d /persist/gogcli 0755 gogcli gogcli -"
    "d /persist/gogcli/.config/gogcli 0700 gogcli gogcli -"
    "d /persist/gogcli/.config/gogcli/keyring 0700 gogcli gogcli -"
    "Z /persist/gogcli/.config/gogcli 0700 gogcli gogcli -"
  ];

  environment.systemPackages = [ pkgs.gogcli ];

  # ラッパースクリプト: SSH command= から呼ばれ、gog サブコマンドのみ安全に実行
  environment.etc."gogcli/wrapper.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      export GOG_KEYRING_BACKEND=file
      export GOG_KEYRING_PASSWORD="$(cat /run/secrets/keyring-password)"
      export GOG_JSON=1
      export GOG_ENABLE_COMMANDS=calendar,gmail,drive,contacts,sheets,tasks
      export HOME=/persist/gogcli

      set -f
      cmd="$SSH_ORIGINAL_COMMAND"
      cmd="''${cmd#gog }"
      subcmd="''${cmd%% *}"
      case "$subcmd" in
        calendar|gmail|drive|contacts|sheets|tasks) ;;
        *) logger -t gogcli-audit -p auth.warning "DENIED subcmd=$subcmd from=$SSH_CLIENT"
           echo "Error: command '$subcmd' not allowed" >&2; exit 1 ;;
      esac
      logger -t gogcli-audit -p auth.info "EXEC subcmd=$subcmd args=''${cmd#* } from=$SSH_CLIENT"
      exec ${pkgs.gogcli}/bin/gog $cmd
    '';
  };

  # SSH サーバー (OpenClaw VM からのアクセスのみ)
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AuthorizedKeysFile = ".ssh/authorized_keys /etc/ssh/authorized_keys.d/%u /run/secrets/authorized-keys";
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [];
    extraCommands = ''
      iptables -A nixos-fw -s 192.168.83.1 -p tcp --dport 22 -j nixos-fw-accept
      iptables -A nixos-fw -s 192.168.83.2 -p tcp --dport 22 -j nixos-fw-accept
    '';
  };
}

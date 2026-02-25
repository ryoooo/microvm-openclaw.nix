{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # cloud-hypervisor v50.1 がセクタ0書き込みをブロック (microvm.nix#476)
    # v50.1 以前の nixpkgs から cloud-hypervisor をピン留め
    nixpkgs-ch.url = "github:NixOS/nixpkgs/c217913993d6c6f6805c3b1a3bda5e639adfde6d";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wezterm = {
      url = "github:wez/wezterm?dir=nix";
    };
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
    };
    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-openclaw-defender = {
      url = "github:ryoooo/nix-openclaw-defender";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-steipete-gogcli = {
      url = "github:openclaw/nix-steipete-tools?dir=tools/gogcli";
      flake = true;
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, nixpkgs-ch, home-manager, wezterm, microvm, llm-agents, nix-openclaw, nix-openclaw-defender, nix-steipete-gogcli, ... }: let
    system = "x86_64-linux";
    pkgs-unstable = import nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
    pkgs-ch = import nixpkgs-ch { inherit system; };
  in {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit wezterm pkgs-unstable microvm home-manager nix-openclaw nix-openclaw-defender nix-steipete-gogcli; };
      modules = [
        {
          nixpkgs.overlays = [
            llm-agents.overlays.default
            # cloud-hypervisor v50.1 セクタ0書き込みブロック回避 (microvm.nix#476)
            (final: prev: { cloud-hypervisor = pkgs-ch.cloud-hypervisor; })
          ];
        }
        microvm.nixosModules.host
        ./configuration.nix
        home-manager.nixosModules.home-manager
      ];
    };
  };
}

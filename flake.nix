{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, wezterm, microvm, llm-agents, nix-openclaw, nix-openclaw-defender, nix-steipete-gogcli, ... }: let
    system = "x86_64-linux";
    pkgs-unstable = import nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit wezterm pkgs-unstable microvm home-manager nix-openclaw nix-openclaw-defender nix-steipete-gogcli; };
      modules = [
        { nixpkgs.overlays = [ llm-agents.overlays.default ]; }
        microvm.nixosModules.host
        ./configuration.nix
        home-manager.nixosModules.home-manager
      ];
    };
  };
}

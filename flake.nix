{
  description = "Nix packaging for the forked Gemini CLI";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    gemini-cli-src = {
      url = "github:RogerNavelsaker/gemini-cli";
      flake = false;
    };
  };

  outputs = { gemini-cli-src, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = import nixpkgs {
          inherit system;
        };
      });
    in {
      packages = forAllSystems ({ pkgs }: {
        default = pkgs.callPackage ./nix/package.nix {
          inherit gemini-cli-src;
        };
      });

      devShells = forAllSystems ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            jq
            nodejs_20
            prefetch-npm-deps
            nixfmt-rfc-style
          ];
        };
      });
    };
}

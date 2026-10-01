{
  description = "Nix packaging for the prepared Gemini CLI package";

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://rogernavelsaker.cachix.org"
      "https://nacosolutions.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "rogernavelsaker.cachix.org-1:n1DtzMNhA9Rz4Kg3xlXOi/KceULu8VrMbs9WXyMFQNQ="
      "nacosolutions.cachix.org-1:JzCiW2CLcuLXtwOVAg3SlSK/kpqWbfSFEVenyKVUlug="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bun2nix.url = "github:nix-community/bun2nix";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    gemini-cli-main-src = {
      url = "github:google-gemini/gemini-cli/main";
      flake = false;
    };
    gemini-cli-nightly-src = {
      url = "github:google-gemini/gemini-cli/v0.64.0-nightly.20260930.g38700b4b3";
      flake = false;
    };
    gemini-cli-stable-src = {
      url = "github:google-gemini/gemini-cli/3df99d8bcbef76d677f54662a25904a8d1168ba9";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, bun2nix, gemini-cli-main-src, gemini-cli-nightly-src, gemini-cli-stable-src, ... }:
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
          overlays = [ bun2nix.overlays.default ];
        };
      });

    in {
      packages = forAllSystems ({ pkgs }: {
        default = pkgs.callPackage ./nix/package.nix {
          gemini-cli-src = gemini-cli-stable-src;
        };
        main = pkgs.callPackage ./nix/package.nix {
          gemini-cli-src = gemini-cli-main-src;
        };
        nightly = pkgs.callPackage ./nix/package.nix {
          gemini-cli-src = gemini-cli-nightly-src;
        };
        stable = pkgs.callPackage ./nix/package.nix {
          gemini-cli-src = gemini-cli-stable-src;
        };
      });

      devShells = forAllSystems ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs
            jq
            nixfmt-rfc-style
          ];
        };
      });
    };
}

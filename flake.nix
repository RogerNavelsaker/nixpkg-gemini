{
  description = "Nix packaging for the prepared Gemini CLI package";

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
    gemini-cli-main-src = {
      url = "github:google-gemini/gemini-cli/main";
      flake = false;
    };
    gemini-cli-nightly-src = {
      url = "github:google-gemini/gemini-cli/v0.40.0-nightly.20260415.g06e7621b2";
      flake = false;
    };
    gemini-cli-stable-src = {
      url = "github:google-gemini/gemini-cli/v0.38.2";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, gemini-cli-main-src, gemini-cli-nightly-src, gemini-cli-stable-src, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = import nixpkgs { inherit system; };
      });

      npmDepsHashes = {
        stable = "sha256-hd8ozYOmyHTVqn3BEWcqfbrMD4DrjtJWu0VG5pK/hb4=";
        main   = "sha256-1Wp107ozH0CZuDrJLlaozZAotJ41xoIvp4OS6NKGFn0=";
        nightly = "sha256-M1NKu9c1EE7W9S2jObM6r5k81GqjN7IxWAlfGGz2dHI=";
      };
    in {
      packages = forAllSystems ({ pkgs }: {
        default = pkgs.callPackage ./nix/package.nix {
          gemini-cli-src = gemini-cli-stable-src;
          npmDepsHash = npmDepsHashes.stable;
        };
        main = pkgs.callPackage ./nix/package.nix {
          gemini-cli-src = gemini-cli-main-src;
          npmDepsHash = npmDepsHashes.main;
        };
        nightly = pkgs.callPackage ./nix/package.nix {
          gemini-cli-src = gemini-cli-nightly-src;
          npmDepsHash = npmDepsHashes.nightly;
        };
        stable = pkgs.callPackage ./nix/package.nix {
          gemini-cli-src = gemini-cli-stable-src;
          npmDepsHash = npmDepsHashes.stable;
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

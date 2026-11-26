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
    gemini-cli-main-src = {
      url = "github:google-gemini/gemini-cli/main";
      flake = false;
    };
    gemini-cli-nightly-src = {
      url = "github:google-gemini/gemini-cli/v0.71.0-nightly.20261124.gaafdfdfb5";
      flake = false;
    };
    gemini-cli-stable-src = {
      url = "github:google-gemini/gemini-cli/v0.71.1";
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
        stable = "sha256-tzdAkGmh06hYmLgFin/k0btrwvCFZTI6z9qL7Buo3Qk=";
        main = "sha256-9bS8YClM0ioZ3RMbwhi3ctIOXReubnNa/MhZWzMXQ+8=";
        nightly = "sha256-EOerPW6xzFurx9ZOMrkQzkYOcgKjaNrr+BBhRiNZwJE=";
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

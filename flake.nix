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
      url = "github:google-gemini/gemini-cli/v0.42.0-nightly.20260429.g6d9911393";
      flake = false;
    };
    gemini-cli-stable-src = {
      url = "github:google-gemini/gemini-cli/v0.40.1";
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
        stable = "sha256-fOLVrSuXBqq+TzwEHbfxS8qahzZ//c5t51lwpM1KHjM=";
        main   = "sha256-dNQ4+DKazWUlVS4fPEQoDkgM5UZD3pw/Myde6fypq3s=";
        nightly = "sha256-zfBGTZjiIiBinS1LDDWC6R9e9XmNl/QeQPCXVJFXm1A=";
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

{
  description = "Experiments with Nix, Rust, Wasm, and npm.";

  inputs = {
    hacknix.url = "github:hackworthltd/hacknix";
    nixpkgs.follows = "hacknix/nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";

    systems.url = "github:nix-systems/default";

    gitignore.url = "github:hercules-ci/gitignore.nix";
    gitignore.inputs.nixpkgs.follows = "nixpkgs";

    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;

    pre-commit-hooks-nix.url = "github:cachix/pre-commit-hooks.nix";
    pre-commit-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    rust-flake.url = "github:juspay/rust-flake";
    rust-flake.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.pre-commit-hooks-nix.flakeModule
        inputs.rust-flake.flakeModules.default
        inputs.rust-flake.flakeModules.nixpkgs
      ];
      perSystem = { config, self', pkgs, lib, system, ... }: {
        rust-project.crane.args = {
          buildInputs = lib.optionals pkgs.stdenv.isDarwin (
            with pkgs.darwin.apple_sdk.frameworks; [
              IOKit
            ]
          );
        };

        rust-project.toolchain = (pkgs.rust-bin.fromRustupToolchainFile (./rust-toolchain.toml)).override {
          targets = [ "wasm32-unknown-unknown" ];
          extensions = [
            "rust-src"
            "rust-analyzer"
            "clippy"
          ];
        };

        treefmt.config = {
          projectRootFile = "flake.nix";
          programs = {
            nixpkgs-fmt.enable = true;
            rustfmt.enable = true;
          };
        };

        pre-commit = {
          check.enable = true;
          settings = {
            hooks = {
              treefmt.enable = true;
            };
          };
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [
            self'.devShells.nix-rust-wasm-npm
            config.treefmt.build.devShell
            config.pre-commit.devShell
          ];
          packages = with pkgs; [
            cargo-watch
            nodejs_20
            wasm-pack
          ];
        };
        packages.default = self'.packages.nix-rust-wasm-npm;
      };
    };
}

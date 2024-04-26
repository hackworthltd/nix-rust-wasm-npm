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

    crane.url = "github:ipetkov/crane";
    crane.inputs.nixpkgs.follows = "nixpkgs";

    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.pre-commit-hooks-nix.flakeModule
      ];
      perSystem = { config, self', pkgs, lib, system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ inputs.rust-overlay.overlays.default ];
          };

          rustWithWasmTarget =
            (pkgs.rust-bin.fromRustupToolchainFile (./rust-toolchain.toml)).override {
              targets = [ "wasm32-unknown-unknown" ];
              extensions = [
                "rust-src"
                "rust-analyzer"
                "clippy"
              ];
            };

          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rustWithWasmTarget;

          nrwn-crate = craneLib.buildPackage {
            src = craneLib.cleanCargoSource (craneLib.path ./.);
            cargoExtraArgs = "--target wasm32-unknown-unknown";
            doCheck = false;
            buildInputs = [
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.libiconv
            ];
          };
        in
        {
          checks = {
            inherit nrwn-crate;
          };

          packages.default = nrwn-crate;

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

          devShells.default = craneLib.devShell {
            inputsFrom = [
              config.treefmt.build.devShell
              config.pre-commit.devShell
            ];
            packages = with pkgs; [
              cargo-watch
              nil
              nodejs_20
              wasm-pack
            ];
          };
        };
    };
}

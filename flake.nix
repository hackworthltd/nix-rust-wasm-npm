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

    advisory-db.url = "github:rustsec/advisory-db";
    advisory-db.flake = false;
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

          rustToolchain =
            (pkgs.rust-bin.fromRustupToolchainFile (./rust-toolchain.toml)).override {
              extensions = [
                "rust-src"
                "rust-analyzer"
                "clippy"
              ];
            };

          rustWasmToolchain = rustToolchain.override {
            targets = [ "wasm32-unknown-unknown" ];
          };

          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rustToolchain;
          craneLibWasm = (inputs.crane.mkLib pkgs).overrideToolchain rustWasmToolchain;

          src = craneLib.cleanCargoSource (craneLib.path ./.);

          commonArgs = {
            inherit src;
            strictDeps = true;
            buildInputs = [
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.libiconv
            ];
            doCheck = false;
          };

          wasmArgs = commonArgs // {
            cargoExtraArgs = "--target wasm32-unknown-unknown";
          };

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;
          cargoArtifactsWasm = craneLibWasm.buildDepsOnly wasmArgs;

          nrwn-crate = craneLib.buildPackage (commonArgs // {
            inherit cargoArtifacts;
          });

          nrwn-crate-wasm = craneLibWasm.buildPackage (wasmArgs // {
            inherit cargoArtifactsWasm;
          });

          inputsFrom = [
            config.treefmt.build.devShell
            config.pre-commit.devShell
          ];

          devShellPackages = with pkgs; [
            cargo-watch
            nil
          ];
        in
        {
          checks = {
            inherit nrwn-crate;
            inherit nrwn-crate-wasm;

            nwrn-crate-clippy = craneLib.cargoClippy (commonArgs // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });

            nwrn-crate-audit = craneLib.cargoAudit {
              inherit (inputs) advisory-db;
              inherit src;
            };
          };

          packages = {
            default = nrwn-crate;
            inherit nrwn-crate;
            inherit nrwn-crate-wasm;
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

          devShells.default = craneLib.devShell {
            inherit inputsFrom;
            packages = devShellPackages;
          };

          devShells.wasm = craneLibWasm.devShell {
            inherit inputsFrom;
            packages = devShellPackages ++ (with pkgs; [
              nodejs_20
              wasm-pack
            ]);
          };
        };
    };
}

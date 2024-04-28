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

          pname = "nrwn-workspace";

          cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
          cargoLock = builtins.fromTOML (builtins.readFile ./Cargo.lock);

          wasm-bindgen-cli =
            let
              wasmBindgenCargoVersions = builtins.map ({ version, ... }: version) (builtins.filter ({ name, ... }: name == "wasm-bindgen") cargoLock.package);
              wasmBindgenVersion = assert builtins.length wasmBindgenCargoVersions == 1; builtins.elemAt wasmBindgenCargoVersions 0;
            in
            pkgs.wasm-bindgen-cli.override {
              version = wasmBindgenVersion;
              hash = "sha256-1VwY8vQy7soKEgbki4LD+v259751kKxSxmo/gqE6yV0=";
              cargoHash = "sha256-aACJ+lYNEU8FFBs158G1/JG8sc6Rq080PeKCMnwdpH0=";
            };

          inherit (cargoToml.workspace.package) version;

          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rustToolchain;
          craneLibWasm = (inputs.crane.mkLib pkgs).overrideToolchain rustWasmToolchain;

          src = craneLib.cleanCargoSource (craneLib.path ./.);

          commonArgs = {
            inherit pname version src;
            strictDeps = true;

            buildInputs = [
            ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.libiconv
            ];
          };

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          individualCrateArgs = commonArgs // {
            inherit cargoArtifacts;
            doCheck = false;
          };

          wasmArgs = commonArgs // {
            CARGO_BUILD_TARGET = "wasm32-unknown-unknown";
          };

          cargoArtifactsWasm = craneLibWasm.buildDepsOnly wasmArgs;

          individualCrateArgsWasm = wasmArgs // {
            inherit cargoArtifactsWasm;
            doCheck = false;
          };

          fileSetForCrate = crate: lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./Cargo.toml
              ./Cargo.lock
              crate
            ];
          };

          greetCrateArgs = baseArgs: pname: baseArgs // {
            inherit pname;
            cargoExtraArgs = "--package greet";
            src = fileSetForCrate ./greet;
            inherit (craneLib.crateNameFromCargoToml { cargoToml = ./greet/Cargo.toml; }) version;
          };

          greet-crate = craneLib.buildPackage (greetCrateArgs individualCrateArgs "${pname}-greet");

          greet-crate-wasm = craneLibWasm.buildPackage (greetCrateArgs individualCrateArgsWasm "${pname}-greet-wasm");

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
            inherit greet-crate;
            inherit greet-crate-wasm;

            nwrn-workspace-clippy = craneLib.cargoClippy (commonArgs // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "--all-targets -- --deny warnings";
            });

            nwrn-workspace-audit = craneLib.cargoAudit {
              inherit (inputs) advisory-db;
              inherit src;
            };
          };

          packages = {
            default = greet-crate-wasm;
            inherit greet-crate;
            inherit greet-crate-wasm;
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
              binaryen
              geckodriver
              nodejs_20
              wasm-pack
            ] ++ [
              wasm-bindgen-cli
            ]);
          };
        };
    };
}

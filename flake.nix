{
  description = "PonziLand Guilds - On-chain guild system";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cairo-nix.url = "github:knownasred/cairo-nix";
    devshell.url = "github:numtide/devshell";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.devshell.flakeModule
      ];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        config,
        self',
        inputs',
        system,
        ...
      }: let
        pkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        snfoundryVersion = "0.51.2";

        snfoundryPlatform = {
          "x86_64-linux" = {
            target = "x86_64-unknown-linux-gnu";
            sha256 = "12h2shs85hjyhfxaklh55iy0cxycvhh2a6293583lbnxd7grp3ws";
          };
          "aarch64-linux" = {
            target = "aarch64-unknown-linux-gnu";
            sha256 = "0000000000000000000000000000000000000000000000000000";
          };
          "x86_64-darwin" = {
            target = "x86_64-apple-darwin";
            sha256 = "0000000000000000000000000000000000000000000000000000";
          };
          "aarch64-darwin" = {
            target = "aarch64-apple-darwin";
            sha256 = "0000000000000000000000000000000000000000000000000000";
          };
        }.${system} or (throw "Unsupported system: ${system}");

        snfoundry = let
          tarball = builtins.fetchurl {
            url = "https://github.com/foundry-rs/starknet-foundry/releases/download/v${snfoundryVersion}/starknet-foundry-v${snfoundryVersion}-${snfoundryPlatform.target}.tar.gz";
            sha256 = snfoundryPlatform.sha256;
          };
          artifacts = pkgs.stdenv.mkDerivation {
            name = "snfoundry-artifacts";
            src = tarball;
            phases = ["unpackPhase"];
            unpackPhase = ''
              mkdir -p $out
              tar -xzf $src -C $out
            '';
          };
        in
          pkgs.stdenv.mkDerivation {
            name = "starknet-foundry-${snfoundryVersion}";
            src = artifacts;
            phases = ["unpackPhase" "installPhase"];
            installPhase = ''
              mkdir -p $out/bin
              mv ./starknet-foundry-*/bin/* $out/bin/
              autoPatchelf $out/bin
            '';
            nativeBuildInputs = with pkgs; [autoPatchelfHook];
            buildInputs = with pkgs; [
              stdenv.cc.cc
              zlib
              openssl
            ];
          };

        uscVersion = "2.7.0";

        uscPlatform = {
          "x86_64-linux" = {
            target = "x86_64-unknown-linux-gnu";
            sha256 = "17p29pz18sh7i2z141wgg2vyzpjizsikdqjh2pn7796mg7y41wc8";
          };
          "aarch64-linux" = {
            target = "aarch64-unknown-linux-gnu";
            sha256 = "0000000000000000000000000000000000000000000000000000";
          };
          "x86_64-darwin" = {
            target = "x86_64-apple-darwin";
            sha256 = "0000000000000000000000000000000000000000000000000000";
          };
          "aarch64-darwin" = {
            target = "aarch64-apple-darwin";
            sha256 = "0000000000000000000000000000000000000000000000000000";
          };
        }.${system} or (throw "Unsupported system: ${system}");

        universal-sierra-compiler = let
          tarball = builtins.fetchurl {
            url = "https://github.com/software-mansion/universal-sierra-compiler/releases/download/v${uscVersion}/universal-sierra-compiler-v${uscVersion}-${uscPlatform.target}.tar.gz";
            sha256 = uscPlatform.sha256;
          };
          artifacts = pkgs.stdenv.mkDerivation {
            name = "usc-artifacts";
            src = tarball;
            phases = ["unpackPhase"];
            unpackPhase = ''
              mkdir -p $out
              tar -xzf $src -C $out
            '';
          };
        in
          pkgs.stdenv.mkDerivation {
            name = "universal-sierra-compiler-${uscVersion}";
            src = artifacts;
            phases = ["unpackPhase" "installPhase"];
            installPhase = ''
              mkdir -p $out/bin
              mv ./universal-sierra-compiler-*/bin/* $out/bin/ 2>/dev/null || mv ./universal-sierra-compiler $out/bin/ 2>/dev/null || true
              chmod +x $out/bin/*
              autoPatchelf $out/bin
            '';
            nativeBuildInputs = with pkgs; [autoPatchelfHook];
            buildInputs = with pkgs; [
              stdenv.cc.cc
              zlib
              openssl
            ];
          };
      in {
        devshells.default = {
          packages = [
            inputs'.cairo-nix.packages.scarb
            inputs'.cairo-nix.packages.starkli

            snfoundry
            universal-sierra-compiler

            pkgs.graphite-cli
            pkgs.git
            pkgs.rustc
            pkgs.cargo
          ];
        };
      };
      flake = {};
    };
}

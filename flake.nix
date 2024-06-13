{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f rec {
        pkgs = import nixpkgs { inherit system; };
        rustToolchain = pkgs.rustPlatform;
      });
    in
    {
      devShells = forEachSupportedSystem ({ pkgs, rustToolchain }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            (with rustToolchain; [
              cargo
              rustc
              rustLibSrc
              rust-analyzer
            ])

            clippy
            rustfmt
            pkg-config
          ];

          RUST_SRC_PATH = "${rustToolchain.rustLibSrc}";
        };
      });

      packages = forEachSupportedSystem ({ pkgs, rustToolchain }: {
        default = rustToolchain.buildRustPackage {
          pname = "waybar-spotify";
          version = "1.0.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
        };
      });
    };
}

{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; };
      });
    in
    {
      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [ zig zls ];
        };
      });
      packages = forEachSupportedSystem ({ pkgs }: rec {
        default = pkgs.stdenvNoCC.mkDerivation
          {
            pname = "waybar-spotify";
            version = "0.1.0";
            src = ./.;

            nativeBuildInputs = with pkgs; [ zig.hook ];
          };
        waybar-spotify = default;
      });
    };
}

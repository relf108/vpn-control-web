{
  description = "Private Flutter web dashboard for the vpn-control API";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      eachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      nixosModules.default = import ./module.nix;
      packages = eachSystem (system: {
        default = import ./default.nix { pkgs = nixpkgs.legacyPackages.${system}; };
      });
      checks = eachSystem (system: {
        web = self.packages.${system}.default;
      });
      devShells = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.flutter
              pkgs.nixfmt
              pkgs.yq-go
            ];
          };
        }
      );
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}

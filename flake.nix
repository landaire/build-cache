{
  description = "Remote action cache for Buck2 CI and workstations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Locked to the revision junction runs in ~/dev/config, so both tiers of the
    # cache speak the same protocol version. It pins its own Rust toolchain.
    nativelink.url = "github:TraceMachina/nativelink";
  };

  outputs =
    {
      nixpkgs,
      disko,
      nativelink,
      ...
    }:
    let
      forSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ];
    in
    {
      nixosConfigurations.buck-cache = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit nativelink; };
        modules = [
          disko.nixosModules.disko
          ./host
        ];
      };

      devShells = forSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.hcloud
              pkgs.nixos-anywhere
              pkgs.nixos-rebuild-ng
            ];
          };
        }
      );
    };
}

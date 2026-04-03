{
  description = "pi-dns-stack - Ad-blocking DNS on Raspberry Pi Zero 2 W with NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "aarch64-linux";
      cfg = import ./config.nix;
    in {
      nixosConfigurations.dns1 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit cfg; };
        modules = [
          ./hosts/dns1.nix
          ./modules/dns-node.nix
        ];
      };

      nixosConfigurations.dns2 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit cfg; };
        modules = [
          ./hosts/dns2.nix
          ./modules/dns-node.nix
        ];
      };
    };
}

if builtins.pathExists ./config.local.nix
then import ./config.local.nix
else import ./config.example.nix

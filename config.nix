let
  cfg = if builtins.pathExists ./config.local.nix
        then import ./config.local.nix
        else import ./config.example.nix;
in
  if cfg.sshKey == "ssh-ed25519 AAAA... your-key-here"
  then throw ''

    Refusing to build with placeholder SSH key from config.example.nix.

    config.local.nix is either missing or not visible to the Nix flake.
    Gitignored files must be registered with `git add -N` so the flake
    evaluator can see them.

    Setup:
      cp config.example.nix config.local.nix
      git add -N config.local.nix
      $EDITOR config.local.nix      # set domain, localIP, sshKey, timeZone

    See README.md for details.
  ''
  else cfg

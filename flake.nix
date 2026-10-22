{
  description = "Development shells for nvim-scrollbar";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    multiverse.url = "github:fzakaria/nixpkgs-multiverse";
    # No `follows` on its inputs, so the builds match nix-community.cachix.org
    neovim-nightly-overlay.url = "github:nix-community/neovim-nightly-overlay";
  };

  outputs =
    {
      nixpkgs,
      multiverse,
      neovim-nightly-overlay,
      ...
    }:
    let
      # The systems that the multiverse fast path publishes store paths for
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        system: pkgs:
        let
          mv = multiverse.multiverse.${system};
          shell =
            {
              neovim,
              extraPackages ? [ ],
              env ? { },
            }:
            pkgs.mkShell {
              packages = [
                neovim
                pkgs.stylua
                pkgs.selene
                pkgs.lua-language-server
                pkgs.gnumake
                pkgs.git
              ]
              ++ extraPackages;
              inherit env;
              # scripts/nightly-cache.sh reads the store path of Neovim from here
              passthru = { inherit neovim; };
            };
        in
        {
          default = shell { neovim = pkgs.neovim-unwrapped; };
          # The minimum supported version
          nvim-0_11_0 = shell { neovim = mv.fast.version "neovim-unwrapped" "0.11.0"; };
          # The overlay CI pushes only this output to nix-community.cachix.org. It uses the nixpkgs of the
          # overlay's dev partition, so `packages.${system}.default` is a different build that is not in the cache.
          nightly = shell { neovim = neovim-nightly-overlay.checks.${system}.neovim; };
          # `make demo`, `make demo-manifest`, and `make demo-issues`. CI does not use this shell. It is tested on
          # Linux only, where the nixpkgs VHS includes Chromium.
          demo = shell {
            neovim = pkgs.neovim-unwrapped;
            extraPackages = [
              pkgs.vhs
              pkgs.gh
              pkgs.curl
              pkgs.coreutils
            ];
            # The tapes set the font family `JetBrainsMono Nerd Font Mono`
            env.FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.nerd-fonts.jetbrains-mono ]; };
          };
        }
      );
    };
}

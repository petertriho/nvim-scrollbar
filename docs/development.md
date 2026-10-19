# Development

The tests need Neovim 0.11 or newer, Git, and Make. The quality checks also
need [StyLua](https://github.com/JohnnyMorganz/StyLua),
[Selene](https://github.com/Kampfkarren/selene), and the
[Lua language server](https://github.com/LuaLS/lua-language-server).

## Commands

```sh
make test-deps
make test
make test-file FILE=tests/test_core.lua
make format
make format-check
make lint
make typecheck
make benchmark
make benchmark-render
make benchmark-search
make benchmark-marks
make benchmark-minimap
make benchmark-typing
make benchmark-worker
make benchmark-providers
make demo
make demo-manifest ISSUE=119
make demo-issues SHOWCASE=120
make ci
```

- `make test-deps` prepares the test-only `mini.nvim v0.18.0` in the ignored
  `deps/` directory. It runs automatically before `make test` and
  `make test-file`.
- `make test-file` runs one MiniTest file.
- `make format` formats the code with StyLua. `make format-check` only checks
  the formatting.
- `make lint` runs Selene. `make typecheck` runs the Lua language server.
- `make benchmark` is an alias for `make benchmark-render`. The other
  `benchmark-*` targets run the scripts in `benchmarks/` for search, marks, the
  minimap, typing, the minimap worker, and providers.
- `make ci` runs the formatting check, Selene, LuaLS type checking, and the
  full test suite.
- `make demo`, `make demo-manifest`, and `make demo-issues` generate the
  images of the README and the docs. See [Demo Images](#demo-images).

## Demo Images

The README, the docs, and the
[showcase](https://github.com/petertriho/nvim-scrollbar/issues/120) embed
images that `make demo` generates. The images are attachments of
[#119](https://github.com/petertriho/nvim-scrollbar/issues/119). They are not
files in the repository.

`make demo` needs [VHS](https://github.com/charmbracelet/vhs) and the
`JetBrainsMono Nerd Font Mono` font. If `vhs` is not on your `PATH`, set
`VHS`, for example `make demo VHS="nix shell nixpkgs#vhs -c vhs"`. `make demo`
first runs `make demo-deps`, which prepares tokyonight.nvim at a fixed commit
in the ignored `deps/` directory.

`scripts/demo/entries.lua` lists the images. Each entry has the Lua source of
its `setup()` call. `scripts/demo/init.lua` runs that source, and the showcase
prints the same source. `tests/test_demo_entries.lua` checks that every source
is a valid configuration.

To replace the images:

1. Run `make demo`. To build only some images, set `ONLY`, for example
   `make demo ONLY="hero search"`.
2. Drag the new files from `scripts/demo/out/` into a new comment on #119.
3. Run `make demo-manifest ISSUE=119`. It downloads each attachment, matches it
   to a file by SHA-256, and writes `scripts/demo/manifest.json`.
4. Run `make demo-issues SHOWCASE=120`. It writes the bodies of both issues to
   `scripts/demo/out/.work/`.
5. Update the issues with
   `gh issue edit 119 --body-file scripts/demo/out/.work/assets.md` and
   `gh issue edit 120 --body-file scripts/demo/out/.work/showcase.md`.
6. Replace the old URLs in the README and the docs with the new URLs from
   `scripts/demo/manifest.json`.

Do not run `make demo` between step 1 and step 3. A new build changes the
bytes of the GIFs, so the attachments no longer match the files.

When v2 is released, change `BRANCH` in `scripts/demo/cli.lua`, update the
note at the top of the showcase, and update the issues again.

## Continuous Integration

CI blocks on the quality checks and on the tests with Neovim `v0.11.4` and the
current stable release. The same tests also run against Neovim nightly. The
nightly run is informational and does not block.

## Related

- [README](../README.md)
- [Configuration](configuration.md)
- [Custom providers](providers/custom.md)
- [Makefile](../Makefile)
- [CI workflow](../.github/workflows/ci.yml)

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

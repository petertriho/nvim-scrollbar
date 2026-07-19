# Development

Tests require Neovim 0.11 or newer, Git, and Make. Quality checks additionally
require [StyLua](https://github.com/JohnnyMorganz/StyLua),
[Selene](https://github.com/Kampfkarren/selene), and
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
make ci
```

`make test-deps` prepares test-only `mini.nvim v0.18.0` under the ignored
`deps/` directory. It runs automatically before `make test` and `make test-file`.
`make test-file` runs one MiniTest file. `make benchmark` is an alias for
`make benchmark-render`; `make benchmark-search` runs the search benchmark;
`make benchmark-marks` measures the per-call cost of the marks-provider
`SafeState` reconcile path across a range of unique-buffer counts.

`make ci` runs formatting checks, Selene, LuaLS type checking, and the full test
suite.

## Continuous Integration

CI blocks on quality checks and tests with Neovim `v0.11.4` and the current
stable release. The same tests run against Neovim nightly as informational,
nonblocking coverage.

## Related

- [README](../README.md)
- [Configuration](configuration.md)
- [Custom providers](providers/custom.md)
- [Makefile](../Makefile)
- [CI workflow](../.github/workflows/ci.yml)

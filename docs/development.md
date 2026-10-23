# Development

## Requirements

Use one of these setups:

- Nix with flakes, and direnv. The flake gives the same tool versions that CI
  uses.
- These tools on your `PATH`: Neovim 0.11 or newer, Git, Make,
  [StyLua](https://github.com/JohnnyMorganz/StyLua),
  [Selene](https://github.com/Kampfkarren/selene), and the
  [Lua language server](https://github.com/LuaLS/lua-language-server).

Other versions of these tools can give results that are different from CI.

The first `make test` or `make typecheck` clones mini.nvim, so this first run
needs network access.

## Development Shells

To load the default shell when you enter the repository:

1. Install Nix and enable flakes.
2. Install direnv and hook it into your shell.
3. In the repository, run `direnv allow`.

With direnv, `nvim` still opens the Neovim of your machine, because `.envrc`
removes the Neovim of the shell from `PATH`. `make` runs the Neovim of the
shell from `$SCROLLBAR_NVIM`, which each shell sets. `nix develop` keeps the
Neovim of the shell on `PATH`.

The flake has four shells. Each shell has StyLua, Selene, lua-language-server,
make, and git.

| Shell         | Neovim                                                   | Command                     |
| ------------- | -------------------------------------------------------- | --------------------------- |
| `default`     | The stable release in the locked nixpkgs                 | `nix develop`               |
| `nvim-0_11_0` | 0.11.0, the minimum supported version                    | `nix develop .#nvim-0_11_0` |
| `nightly`     | The nightly build in the locked `neovim-nightly-overlay` | `nix develop .#nightly`     |
| `demo`        | The stable release in the locked nixpkgs                 | `nix develop .#demo`        |

The `demo` shell also has VHS, gh, curl, and the
`JetBrainsMono Nerd Font Mono` font for the [demo images](#demo-images). It is
tested on Linux only. CI does not use it.

The nightly builds are in the nix-community binary cache. Without this cache,
Nix builds Neovim from source. To use the cache, add these lines to your Nix
config:

```
extra-substituters = https://nix-community.cachix.org
extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
```

## Commands

| Target                          | Action                                                                                              |
| ------------------------------- | --------------------------------------------------------------------------------------------------- |
| `make test`                     | Runs all tests.                                                                                     |
| `make test-file FILE=<path>`    | Runs one test file.                                                                                 |
| `make format`                   | Formats `lua/`, `tests/`, `scripts/`, and `benchmarks/` with StyLua.                                |
| `make format-check`             | Checks the formatting.                                                                              |
| `make lint`                     | Lints `lua/`, `tests/`, `scripts/`, and `benchmarks/` with Selene. Warnings fail the target.        |
| `make typecheck`                | Checks the types with lua-language-server. Warnings fail the target.                                |
| `make ci`                       | Runs `format-check`, `lint`, `typecheck`, and `test`.                                               |
| `make test-deps`                | Clones mini.nvim at `MINI_VERSION` into `deps/`. `test`, `test-file`, and `typecheck` run it first. |
| `make bench`                    | Runs the benchmark cases. Options go in `BENCH_ARGS`.                                               |
| `make bench-compare REF=<rev>`  | Compares the benchmark cases of `<rev>` (default `main`) with the working tree.                     |
| `make benchmark-<area>`         | Runs one benchmark report. `make benchmark` runs `benchmark-render`.                                |
| `make demo`                     | Builds the demo images. See [Demo Images](#demo-images).                                            |
| `make demo-manifest ISSUE=<n>`  | Writes `scripts/demo/manifest.json` from the attachments of an issue.                               |
| `make demo-issues SHOWCASE=<n>` | Writes the bodies of the asset issue and the showcase issue.                                        |

To use a different tool, set its variable: `NVIM`, `STYLUA`, `SELENE`,
`LUA_LANGUAGE_SERVER`, or `VHS`. For example:

```sh
make test NVIM=~/.local/bin/nvim
```

`make` reads `NVIM` only from the command line. It ignores the environment
variable `$NVIM`, because Neovim sets it to its server address in `:terminal`
and in jobs. To set the Neovim in the environment, set `$SCROLLBAR_NVIM`.

`make typecheck` gets `$VIMRUNTIME` from `$(NVIM)`, so lua-language-server
checks the code against the Neovim API of that version.

To run the tests on Neovim 0.11.0 and on nightly:

```sh
nix develop .#nvim-0_11_0 -c make test
nix develop .#nightly -c make test
```

The `Neovim nightly` job tests the newest nightly that is in the cache, not the
locked nightly. To do the same test on your computer, run these commands.
`scripts/nightly-cache.sh latest` needs an authenticated `gh`, and it checks
the last 10 overlay commits. To check more commits, give a count, for example
`latest 20`.

```sh
rev=$(scripts/nightly-cache.sh latest)
nix develop .#nightly --no-write-lock-file \
  --override-input neovim-nightly-overlay "github:nix-community/neovim-nightly-overlay/$rev" -c make test
```

## Benchmarks

The benchmarks have two parts:

- The cases in `benchmarks/cases/` print one line for each case. CI compares
  them between two revisions to find regressions.
- The reports in `benchmarks/reports/` print Markdown tables with the phases of
  the renderer, p95 and maximum times, process memory, and event-loop delay.
  They use larger buffers, up to 500000 lines. They do not run in CI.

### Cases

The cases use 10000-line buffers. Only `minimap/squash/fit_1k` uses 1000 lines.

| Group        | File                             | Measures                                                                                                                        |
| ------------ | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `render/`    | `benchmarks/cases/render.lua`    | One render of the scrollbar in the `line` and `screenline` units: steady, after a change, in 3 windows, and with wrapped lines. |
| `typing/`    | `benchmarks/cases/typing.lua`    | The TextChangedI and CursorMoved dispatch of a full setup, with and without the minimap.                                        |
| `providers/` | `benchmarks/cases/providers.lua` | One refresh of a custom provider through the manager API.                                                                       |
| `marks/`     | `benchmarks/cases/marks.lua`     | The reconcile of the marks provider over 1, 4, and 16 buffers.                                                                  |
| `search/`    | `benchmarks/cases/search.lua`    | One accepted search with the sync backend, from BufEnter to the publication.                                                    |
| `minimap/`   | `benchmarks/cases/minimap.lua`   | The squash, a sync request, and the render of the minimap float.                                                                |
| `worker/`    | `benchmarks/cases/worker.lua`    | The round trips to the search and minimap children, and the startup of each child.                                              |

Each line of the output has these values:

| Value      | Meaning                                                                                                                                                                     |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `median`   | The median time of one operation.                                                                                                                                           |
| `min`      | The shortest time of one operation.                                                                                                                                         |
| `alloc`    | Sync cases only. The Lua memory that one operation allocates. It does not change between runs.                                                                              |
| `main`     | Async cases only. The main-thread time of one operation. Neovim cannot handle a keystroke during it.                                                                        |
| `block`    | Async cases only. The longest uninterrupted main-thread slice of one operation.                                                                                             |
| `spawns`   | The processes that one operation starts.                                                                                                                                    |
| `blocking` | The calls to `vim.fn.system` and `vim.fn.systemlist` in one operation. These stop Neovim until the process finishes. The line shows this value only when it is more than 0. |

To run the cases:

```sh
make bench
make bench BENCH_ARGS="--filter render"
```

To compare your changes with `main`:

```sh
make bench-compare
```

`scripts/bench-compare.sh` runs the cases of the working tree on the `lua/`
code of both revisions. It runs each side two times, and keeps the best run of
each side. To change the number of runs, set `BENCH_RUNS`.

The script reports a regression in a case, and exits with 1, when one of these
conditions is true:

- The median time or the main-thread time grows by more than 25%.
- The allocation grows by more than 10%.
- The count of spawns or blocking calls grows.
- The case fails only on the working tree.

A change of 0.5 us, 2 ms, or 0.5 KB or less does not count. The options of
`benchmarks/compare.lua` change the limits, for example
`scripts/bench-compare.sh main --time-threshold 0.5`. A case that the older
revision cannot run shows `base error`. It does not count as a regression.

To add a case:

1. Add the case to the file of its group.
2. Call the module functions, not internal upvalues, so that the case also
   runs on the code of an older revision.
3. If the operation ends in a scheduled callback or in a worker child, write
   an async case that calls `done`.
4. If a worker child answers the operation, list the global callback of the
   worker in `hooks`. The harness then counts its time as main-thread time.
5. Use the helpers in `benchmarks/fixtures.lua`, and call `fixtures.reset()`
   in `teardown`.

Keep one run of `make bench` under 2 minutes on a GitHub runner. The
`Benchmarks` job runs it 6 times.

Do not set `'lines'` in a case. With 48 lines and three windows that show the
buffer, the redraw that places a float crashes Neovim 0.12.6 in `nvim -l`.

### Reports

| Target                     | Report                                                                                    |
| -------------------------- | ----------------------------------------------------------------------------------------- |
| `make benchmark-render`    | The end-to-end time and the phases of the renderer for the `line` and `screenline` units. |
| `make benchmark-search`    | The sync search and the search worker, with up to 500000 lines.                           |
| `make benchmark-marks`     | The marks reconcile, and the overhead of the SafeState fallback.                          |
| `make benchmark-minimap`   | The squash, the parity of the sync and worker backends, and the render.                   |
| `make benchmark-typing`    | The TextChangedI and CursorMoved dispatch.                                                |
| `make benchmark-worker`    | The main-loop blocking and the round trip of the minimap worker.                          |
| `make benchmark-providers` | The cost of a provider publication.                                                       |

`benchmarks/reports/render_compact.lua` has no target. To run it, use
`nvim --headless --noplugin -u NONE -l benchmarks/reports/render_compact.lua`.

## Demo Images

The README, the docs, and the
[showcase](https://github.com/petertriho/nvim-scrollbar/issues/120) embed
images that `make demo` generates. The images are attachments of
[#119](https://github.com/petertriho/nvim-scrollbar/issues/119). They are not
files in the repository.

`make demo` needs [VHS](https://github.com/charmbracelet/vhs) and the
`JetBrainsMono Nerd Font Mono` font. The `demo` shell has both:

```sh
nix develop .#demo -c make demo
```

Without Nix, put `vhs` on your `PATH`, or set `VHS`. `make demo` first runs
`make demo-deps`, which prepares tokyonight.nvim at a fixed commit in the
ignored `deps/` directory.

`scripts/demo/entries.lua` lists the images. Each entry has the Lua source of
its `setup()` call. `scripts/demo/init.lua` runs that source, and the showcase
prints the same source. `tests/test_demo_entries.lua` checks that every source
is a valid configuration.

The demo buffer is `lua/scrollbar/mouse.lua`, so its length changes with the
code. `scripts/demo/entries.lua` gives the place of each diagnostic, hunk,
mark, and cursor as a fraction of the line count, not as a line number. Each
`Ctrl+D` in a tape scrolls 4% of the buffer. `tests/test_demo_entries.lua`
fails when two marks resolve to the same line, when two hunks touch, or when the
search pattern matches fewer than 5 lines.

Do not run `make demo` between step 1 and step 3 of the procedure that
follows. A new build changes the bytes of the GIFs, so the attachments no
longer match the files.

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

## Continuous Integration

The workflow in `.github/workflows/ci.yml` runs on pushes to `main`, on pull
requests, and on manual dispatch. It has these jobs:

| Job              | Steps                                                                                                      | Blocks |
| ---------------- | ---------------------------------------------------------------------------------------------------------- | ------ |
| `Quality`        | `make format-check`, `make lint`, and `make typecheck` in the default shell                                | Yes    |
| `Neovim stable`  | `make test` in the default shell                                                                           | Yes    |
| `Neovim 0.11.0`  | `make test` in the `nvim-0_11_0` shell                                                                     | Yes    |
| `Nightly cache`  | `scripts/nightly-cache.sh check` (the locked nightly Neovim is in the cache for each system)               | Yes    |
| `Neovim nightly` | `make test` with the newest `neovim-nightly-overlay` commit that is in the cache, not the locked revision  | No     |
| `Benchmarks`     | Pull requests only. `scripts/bench-compare.sh` against the base branch, with the report in the job summary | No     |

Shared runners are noisy, so a regression in the `Benchmarks` job is a warning
to read in the job summary. It does not fail the check.

A weekly schedule (Monday 06:00 UTC) runs only the nightly job. GitHub disables
scheduled workflows after 60 days without repository activity. To enable the
schedule again, use the Actions tab of the repository.

A push to a branch without a pull request does not run CI. To run CI on such a
branch, start the workflow from the Actions tab.

## Dependency Updates

Each month, Dependabot opens up to two grouped pull requests:

- `github-actions` updates the action SHAs in the workflow.
- `nix` updates the inputs in `flake.lock`.

A nixpkgs update can change the versions of StyLua, Selene,
lua-language-server, and stable Neovim. If the `Quality` job then fails, do
these steps on the Dependabot branch:

1. Run `make format`.
2. Fix the lint and type warnings, if there are any.
3. Push the changes to the branch.

A `nix` update can lock a `neovim-nightly-overlay` commit whose Neovim is not
in the cache yet. Then `nix develop .#nightly` builds Neovim from source, and
the `Nightly cache` job fails. The overlay updates each day at 00:00 UTC, and
its CI pushes the build to the cache later. If the job fails, do these steps.
Step 2 removes the changes that you pushed to the branch.

1. Later the same day, run the job again.
2. If the job still fails, comment `@dependabot recreate` on the pull request.
   Dependabot then locks the newest overlay commit.
3. If you pushed changes to the branch before step 2, push them again.

To check the locked nightly Neovim on your computer, run
`scripts/nightly-cache.sh check`.

Dependabot does not change the Neovim 0.11.0 pin in `flake.nix`.

### Update mini.nvim

Dependabot does not update mini.nvim. To update it:

1. Find the latest release tag of
   [mini.nvim](https://github.com/nvim-mini/mini.nvim/releases).
2. Set `MINI_VERSION` in the `Makefile` to the tag.
3. Run `make test`. `make test-deps` checks out the new tag in
   `deps/mini.nvim`.
4. Commit the `Makefile`.

Dependabot also does not update tokyonight.nvim. `TOKYONIGHT_COMMIT` in the
`Makefile` pins it for the demo images.

## Related

- [README](../README.md)
- [Configuration](configuration.md)
- [Custom providers](providers/custom.md)
- [Makefile](../Makefile)
- [CI workflow](../.github/workflows/ci.yml)
- [Flake](../flake.nix)

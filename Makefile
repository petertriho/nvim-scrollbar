# Not `?=`: Neovim sets $NVIM to its server address in :terminal and in jobs. The flake sets $SCROLLBAR_NVIM.
NVIM := $(or $(SCROLLBAR_NVIM),nvim)
STYLUA ?= stylua
SELENE ?= selene
LUA_LANGUAGE_SERVER ?= lua-language-server
MINI_VERSION := v0.18.0
MINI_DIR := deps/mini.nvim
TOKYONIGHT_COMMIT := cdc07ac78467a233fd62c493de29a17e0cf2b2b6
TOKYONIGHT_DIR := deps/tokyonight.nvim
VHS ?= vhs
LUA_PATHS := lua tests scripts benchmarks
REF ?= main

.PHONY: test-deps test test-file bench bench-compare benchmark benchmark-render benchmark-search benchmark-marks benchmark-minimap benchmark-typing benchmark-worker benchmark-providers demo-deps demo demo-manifest demo-issues format format-check lint typecheck ci

test-deps:
	@if [ ! -d "$(MINI_DIR)/.git" ]; then \
		mkdir -p deps; \
		git clone --filter=blob:none --branch "$(MINI_VERSION)" --depth 1 \
			https://github.com/nvim-mini/mini.nvim.git "$(MINI_DIR)"; \
	fi
	@if [ "$$(git -C "$(MINI_DIR)" describe --tags --exact-match 2>/dev/null)" != "$(MINI_VERSION)" ]; then \
		git -C "$(MINI_DIR)" fetch --depth 1 origin tag "$(MINI_VERSION)"; \
		git -C "$(MINI_DIR)" checkout --detach "$(MINI_VERSION)"; \
	fi

test: test-deps
	$(NVIM) --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

test-file: test-deps
	@test -n "$(FILE)" || (printf '%s\n' 'Usage: make test-file FILE=tests/**/test_*.lua' >&2; exit 2)
	TEST_FILE="$(FILE)" $(NVIM) --headless --noplugin -u scripts/minimal_init.lua \
		-c "lua MiniTest.run_file(vim.env.TEST_FILE)"

# Prints one line for each case. Options go in BENCH_ARGS, for example BENCH_ARGS="--filter render".
bench:
	$(NVIM) --headless --clean -l benchmarks/run.lua $(BENCH_ARGS)

# Compares the benchmarks of REF with the working tree
bench-compare:
	SCROLLBAR_NVIM="$(NVIM)" scripts/bench-compare.sh "$(REF)"

benchmark: benchmark-render

benchmark-render:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/reports/render.lua

benchmark-search:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/reports/search.lua

benchmark-marks:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/reports/marks_reconcile.lua

benchmark-minimap:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/reports/minimap.lua

benchmark-typing:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/reports/typing.lua

benchmark-worker:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/reports/worker.lua

benchmark-providers:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/reports/providers.lua

demo-deps: test-deps
	@if [ ! -d "$(TOKYONIGHT_DIR)/.git" ]; then \
		mkdir -p deps; \
		git init --quiet "$(TOKYONIGHT_DIR)"; \
		git -C "$(TOKYONIGHT_DIR)" remote add origin https://github.com/folke/tokyonight.nvim.git; \
	fi
	@if [ "$$(git -C "$(TOKYONIGHT_DIR)" rev-parse HEAD 2>/dev/null)" != "$(TOKYONIGHT_COMMIT)" ]; then \
		git -C "$(TOKYONIGHT_DIR)" fetch --quiet --depth 1 origin "$(TOKYONIGHT_COMMIT)"; \
		git -C "$(TOKYONIGHT_DIR)" checkout --quiet --detach FETCH_HEAD; \
	fi

demo: demo-deps
	VHS="$(VHS)" $(NVIM) --headless --noplugin -u NONE -l scripts/demo/cli.lua build $(ONLY)

demo-manifest:
	@test -n "$(ISSUE)" || (printf '%s\n' 'Usage: make demo-manifest ISSUE=<asset issue number>' >&2; exit 2)
	$(NVIM) --headless --noplugin -u NONE -l scripts/demo/cli.lua manifest "$(ISSUE)"

demo-issues:
	$(NVIM) --headless --noplugin -u NONE -l scripts/demo/cli.lua issues $(SHOWCASE)

format:
	$(STYLUA) $(LUA_PATHS)

format-check:
	$(STYLUA) --check $(LUA_PATHS)

lint:
	$(SELENE) $(LUA_PATHS)

# LuaLS reads the Neovim API types from $VIMRUNTIME/lua, see .luarc.json
typecheck: test-deps
	VIMRUNTIME="$$($(NVIM) --clean --headless -c 'lua io.write(vim.env.VIMRUNTIME)' -c q 2>&1)" \
		$(LUA_LANGUAGE_SERVER) --check=. --checklevel=Warning --check_format=pretty

ci: format-check lint typecheck test

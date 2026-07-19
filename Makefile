NVIM ?= nvim
STYLUA ?= stylua
SELENE ?= selene
LUA_LANGUAGE_SERVER ?= lua-language-server
MINI_VERSION := v0.18.0
MINI_DIR := deps/mini.nvim
LUA_PATHS := lua tests scripts benchmarks

.PHONY: test-deps test test-file benchmark benchmark-render benchmark-search benchmark-marks format format-check lint typecheck ci

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
	@test -n "$(FILE)" || (printf '%s\n' 'Usage: make test-file FILE=tests/test_*.lua' >&2; exit 2)
	TEST_FILE="$(FILE)" $(NVIM) --headless --noplugin -u scripts/minimal_init.lua \
		-c "lua MiniTest.run_file(vim.env.TEST_FILE)"

benchmark: benchmark-render

benchmark-render:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/render.lua

benchmark-search:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/search.lua

benchmark-marks:
	$(NVIM) --headless --noplugin -u NONE -l benchmarks/marks_reconcile.lua

format:
	$(STYLUA) $(LUA_PATHS)

format-check:
	$(STYLUA) --check $(LUA_PATHS)

lint:
	$(SELENE) $(LUA_PATHS)

typecheck:
	$(LUA_LANGUAGE_SERVER) --check=.

ci: format-check lint typecheck test

.PHONY: test help deps-install clean

DEPS_DIR := .deps
MINI_PATH := $(DEPS_DIR)/mini.nvim

help:
	@echo "Available targets:"
	@echo "  make deps   - Download dependencies to .deps/"
	@echo "  make test   - Run all tests in headless mode"
	@echo "  make clean  - Remove .deps/"

# Download dependencies
deps: $(MINI_PATH)

$(MINI_PATH):
	@echo "Installing mini.nvim to $(DEPS_DIR)..."
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d $(MINI_PATH) ]; then \
		git clone --depth 1 https://github.com/echasnovski/mini.nvim $(MINI_PATH); \
	else \
		echo "mini.nvim already installed"; \
	fi

# Run all tests in headless mode
test: deps
	@echo "Running tests (headless)..."
	nvim --headless -u scripts/minimal_init.lua \
		-c "lua require('mini.test').run({ \
		  execute = { \
		    reporter = require('mini.test').gen_reporter.stdout() \
		  } \
		})" \
		-c 'qa!'

# Clean dependencies
clean:
	@echo "Removing .deps/..."
	@rm -rf $(DEPS_DIR)

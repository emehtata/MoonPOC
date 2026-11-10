# Pinned Godot version (official release, SHA-512 from the release's SHA512-SUMS.txt)
GODOT_VERSION := 4.7.2-stable
GODOT_ZIP     := Godot_v$(GODOT_VERSION)_linux.x86_64.zip
GODOT_URL     := https://github.com/godotengine/godot/releases/download/$(GODOT_VERSION)/$(GODOT_ZIP)
GODOT_SHA512  := 9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
GODOT_DIR     := tools/godot

SHELL := /bin/bash
GODOT ?= $(GODOT_DIR)/godot

# Rust ephemeris (toolchain pinned in ephemeris/rust-toolchain.toml)
RUST_TOOLCHAIN := $(shell sed -n 's/^channel *= *"\(.*\)"/\1/p' ephemeris/rust-toolchain.toml)
CARGO_HOME     ?= $(HOME)/.cargo
RUSTUP         := $(CARGO_HOME)/bin/rustup
CARGO          := $(CARGO_HOME)/bin/cargo
RUST_TARGET    := x86_64-unknown-linux-musl
EPHEMERIS_UTC  ?= 2026-11-10T00:00:00Z
EPHEMERIS_JSON := assets/ephemeris/sun_moon_fixed.json

# Texture preparation (Rust crate tools/texture-prep, same pinned toolchain and target as the ephemeris crate)
TEXTURE_RAW_DIR ?= data/raw/lroc_wac_gmm_100m
TEXTURE_PNG     ?= assets/textures/lunar_albedo_4096x2048.png
TEXTURE_PREP    := tools/texture-prep/target/$(RUST_TARGET)/release/texture-prep

.DEFAULT_GOAL := help
.PHONY: help setup editor run import check test clean require-godot require-project rust-setup ephemeris-test ephemeris require-rust texture

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | grep -v '^require' | awk -F':.*## ' '{printf "  %-15s %s\n", $$1, $$2}'

setup: ## Download pinned Godot into tools/godot/ and verify its SHA-512
	@if [ -x "$(GODOT_DIR)/godot" ]; then echo "Godot already installed: $$($(GODOT_DIR)/godot --version)"; exit 0; fi; \
	set -e; tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	echo "Downloading $(GODOT_URL)"; \
	curl -fsSL -o "$$tmp/$(GODOT_ZIP)" "$(GODOT_URL)"; \
	echo "$(GODOT_SHA512)  $$tmp/$(GODOT_ZIP)" | sha512sum -c -; \
	mkdir -p "$(GODOT_DIR)"; \
	unzip -o -q "$$tmp/$(GODOT_ZIP)" -d "$$tmp/x"; \
	mv "$$tmp/x/Godot_v$(GODOT_VERSION)_linux.x86_64" "$(GODOT_DIR)/godot"; \
	chmod +x "$(GODOT_DIR)/godot"; \
	echo "Installed: $$($(GODOT_DIR)/godot --version)"

require-godot:
	@command -v "$(GODOT)" >/dev/null 2>&1 || [ -x "$(GODOT)" ] || { echo "ERROR: Godot not found at '$(GODOT)'. Run 'make setup' or set GODOT=/path/to/godot." >&2; exit 1; }

require-project:
	@[ -f project.godot ] || { echo "ERROR: project.godot not found in $$(pwd). The Godot project has not been created yet." >&2; exit 1; }

editor: require-godot require-project ## Open the project in the Godot editor
	"$(GODOT)" --editor --path .

run: require-godot require-project ## Run the main scene (renderer from project.godot, else Forward+/Vulkan)
	@if grep -q '^renderer/rendering_method' project.godot; then \
		echo "Using renderer settings from project.godot"; "$(GODOT)" --path .; \
	else \
		"$(GODOT)" --rendering-method forward_plus --rendering-driver vulkan --path .; \
	fi

import: require-godot require-project ## Headless import to generate resources
	"$(GODOT)" --headless --import --path .

check: require-godot require-project ## Headless load check; fails on script errors
	@fail=0; \
	while IFS= read -r f; do \
		out=$$("$(GODOT)" --headless --path . --check-only --script "res://$${f#./}" 2>&1) || { echo "$$out" >&2; echo "parse error: $$f" >&2; fail=1; }; \
	done < <(find . -name '*.gd' -not -path './.godot/*' -not -path './tools/*' -not -path './addons/*'); \
	out=$$("$(GODOT)" --headless --quit --path . 2>&1); rc=$$?; echo "$$out"; \
	if [ $$rc -ne 0 ] || grep -qE '^(SCRIPT ERROR|ERROR|Parse Error)' <<<"$$out"; then fail=1; fi; \
	if [ $$fail -ne 0 ]; then echo "check: FAILED" >&2; exit 1; fi; echo "check: OK"

test: ## Run tests/run_tests.gd headless if present
	@if [ -f tests/run_tests.gd ]; then \
		$(MAKE) --no-print-directory require-godot require-project && "$(GODOT)" --headless --path . --script tests/run_tests.gd; \
	else echo "no tests yet"; fi

clean: ## Remove Godot's generated .godot/ cache only
	rm -rf .godot

rust-setup: ## Install rustup (if missing) and the Rust toolchain pinned in ephemeris/rust-toolchain.toml
	@set -e; \
	if [ ! -x "$(RUSTUP)" ]; then \
		echo "Installing rustup (no default toolchain)"; \
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain none --profile minimal; \
	fi; \
	if "$(RUSTUP)" toolchain list | grep -q "^$(RUST_TOOLCHAIN)-"; then \
		echo "Rust $(RUST_TOOLCHAIN) already installed"; \
	else \
		"$(RUSTUP)" toolchain install "$(RUST_TOOLCHAIN)" --profile minimal; \
	fi; \
	"$(RUSTUP)" target add --toolchain "$(RUST_TOOLCHAIN)" $(RUST_TARGET); \
	cd ephemeris && "$(CARGO_HOME)/bin/rustc" --version

require-rust:
	@[ -x "$(CARGO)" ] || { echo "ERROR: cargo not found at '$(CARGO)'. Run 'make rust-setup'." >&2; exit 1; }

ephemeris-test: require-rust ## Run the ephemeris crate tests with the pinned toolchain
	cd ephemeris && "$(CARGO)" test

ephemeris: require-rust ## Generate assets/ephemeris/sun_moon_fixed.json for EPHEMERIS_UTC
	cd ephemeris && "$(CARGO)" build --release --locked
	@mkdir -p assets/ephemeris
	ephemeris/target/$(RUST_TARGET)/release/moon-ephemeris "$(EPHEMERIS_UTC)" > $(EPHEMERIS_JSON).tmp && mv $(EPHEMERIS_JSON).tmp $(EPHEMERIS_JSON)
	@cat $(EPHEMERIS_JSON)

texture: require-rust ## Rebuild the lunar albedo texture (TEXTURE_PNG) from the raw tiles in TEXTURE_RAW_DIR
	cd tools/texture-prep && RUSTUP_TOOLCHAIN=$(RUST_TOOLCHAIN) "$(CARGO)" build --release --locked
	$(TEXTURE_PREP) "$(TEXTURE_RAW_DIR)" "$(TEXTURE_PNG).tmp" && mv "$(TEXTURE_PNG).tmp" "$(TEXTURE_PNG)"

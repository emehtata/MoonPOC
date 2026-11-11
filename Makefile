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
# Default: current UTC time when make runs; override with EPHEMERIS_UTC=YYYY-MM-DDTHH:MM:SSZ
EPHEMERIS_UTC  ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
EPHEMERIS_JSON := assets/ephemeris/sun_moon_fixed.json

# Texture preparation (Rust crate tools/texture-prep, same pinned toolchain and target as the ephemeris crate)
TEXTURE_RAW_DIR ?= data/raw/lroc_wac_gmm_100m
TEXTURE_PNG     ?= assets/textures/lunar_albedo_4096x2048.png
TEXTURE_PREP    := tools/texture-prep/target/$(RUST_TARGET)/release/texture-prep

# Moon data pipeline (Rust crate tools/moon-data, toolchain pinned in tools/moon-data/rust-toolchain.toml)
MOON_DATA_TOOLCHAIN := $(shell sed -n 's/^channel *= *"\(.*\)"/\1/p' tools/moon-data/rust-toolchain.toml)
MOON_RAW_DIR        ?= data/raw
MOON_ELEVATION_DIR  ?= assets/elevation
MOON_TEXTURES_DIR   ?= assets/textures
MOON_DATA           := tools/moon-data/target/$(RUST_TARGET)/release/moon-data

# Earth Milestone 1: monthly NASA Blue Marble Next Generation images (not committed; see docs/DATA_SOURCES.md)
EARTH_TEXTURE_DIR  := assets/earth/bmng
EARTH_TEXTURE_BASE := https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-base
# Rows of "<month> <file> <bytes> <sha256>"
EARTH_TEXTURES := \
	january world.200401.3x5400x2700.jpg 1884678 99f5faad74efe985fbf1714c8be7296ca9999759a1215b65f99b7f1df278dde5 \
	february world.200402.3x5400x2700.jpg 1865311 252444b224c7dc10289616fb5e3cd85c3738fca9ddbdc267775cd22a748bbfbe \
	march world.200403.3x5400x2700.jpg 1830489 0d9967be048b5e2ba62195dd610042c9e0926b4eb9d1e9ae53dbf20eaadd9228 \
	april world.200404.3x5400x2700.jpg 1774173 8db8d5e545b31cde0e4e5dfa46cb116bf485243a0200c2d6e4b04b4e6937f669 \
	may world.200405.3x5400x2700.jpg 1735263 d9a8dfc0a3e54775c3a4aeb547c729f710bb588d82d4602252d7cd7bf43a38ef \
	june world.200406.3x5400x2700.jpg 1692239 dc059529b8ed1cfcdd59747a7c3f259c93c1322bf88ca1ec8bab1dd71fcc57f5 \
	july world.200407.3x5400x2700.jpg 1617810 f55226d46d27e05511f2118dc6aa24f5dbf9b6b2cddc87cc6e0e7dd067c00b11 \
	august world.200408.3x5400x2700.jpg 1616254 2048023ccc62250c677c0f4b03d4362f997b130eb0154a6cad00aa1b27c390b9 \
	september world.200409.3x5400x2700.jpg 1709729 ed72e87674861f72e2a6e5df52f0cc6bf3df1edd9b862664cf18ac423e2e9e0e \
	october world.200410.3x5400x2700.jpg 1766694 ccfd9b7a5e5ee601e1466556716bba50ea418f3a8e068ab0194ae0425815b1b0 \
	november world.200411.3x5400x2700.jpg 1851209 d63de0bb4274a7d9df08d2f69eeffc849d0f7aca157c4401f9bd2e41af63b178 \
	december world.200412.3x5400x2700.jpg 1878742 3d38a8ecaceb1cdb51ced7f831e9ac18d261950049616feff6892efcae0dcc26

.DEFAULT_GOAL := help
.PHONY: help setup editor run import check test sun-helper-test clean require-godot require-project rust-setup ephemeris-test ephemeris require-rust texture moon-data moon-data-test normal-map visual-check perf earth-texture

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

run: require-godot require-project require-rust ## Build the Sun helper (moon-ephemeris --stream), then run the main scene (renderer from project.godot, else Forward+/Vulkan)
	cd ephemeris && "$(CARGO)" build --release --locked
	@[ "$$(ls $(EARTH_TEXTURE_DIR)/*.jpg 2>/dev/null | wc -l)" -ge 12 ] || echo "Earth textures missing: run 'make earth-texture'"
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

sun-helper-test: require-godot require-project ## Live REQ-24/REQ-25 check with a fake helper via MOON_SUN_HELPER (about 6 s)
	bash tests/sun_helper_live.sh "$(GODOT)"

visual-check: require-godot require-project ## User-run GPU checks (tests/visual_check.gd); windowed by default, HEADLESS=1 prints not-available lines
	"$(GODOT)" $(if $(HEADLESS),--headless) --path . --script tests/visual_check.gd

perf: require-godot require-project ## Measure performance (tests/perf.gd); windowed by default, HEADLESS=1 for headless values only
	"$(GODOT)" $(if $(HEADLESS),--headless) --path . --script tests/perf.gd

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

earth-texture: ## Download and verify the 12 monthly Blue Marble images into assets/earth/bmng/ (skips valid files)
	@set -e; mkdir -p "$(EARTH_TEXTURE_DIR)"; \
	printf '%s\n' $(EARTH_TEXTURES) | paste -d' ' - - - - | while read -r month file bytes sha; do \
		dst="$(EARTH_TEXTURE_DIR)/$$file"; \
		if [ -f "$$dst" ] && [ "$$(stat -c %s "$$dst")" = "$$bytes" ] && echo "$$sha  $$dst" | sha256sum -c --quiet - 2>/dev/null; then echo "ok $$file"; continue; fi; \
		tmp="$$dst.part"; \
		echo "Downloading $$file"; \
		if ! curl -fsSL -o "$$tmp" "$(EARTH_TEXTURE_BASE)/$$month/$$file" || [ "$$(stat -c %s "$$tmp")" != "$$bytes" ] || ! echo "$$sha  $$tmp" | sha256sum -c --quiet -; then \
			echo "ERROR: download or checksum failed for $$file" >&2; unlink "$$tmp" 2>/dev/null || true; unlink "$$dst" 2>/dev/null || true; exit 1; \
		fi; \
		mv -f "$$tmp" "$$dst"; \
	done

moon-data-test: require-rust ## Run the moon-data crate tests with the pinned toolchain
	cd tools/moon-data && RUSTUP_TOOLCHAIN=$(MOON_DATA_TOOLCHAIN) "$(CARGO)" test --locked

moon-data: require-rust ## Build elevation levels, albedo, normal map and moon_data.json from data/raw/ (LOLA LDEM_64 + LROC WAC)
	cd tools/moon-data && RUSTUP_TOOLCHAIN=$(MOON_DATA_TOOLCHAIN) "$(CARGO)" build --release --locked
	$(MOON_DATA) "$(MOON_RAW_DIR)" "$(MOON_ELEVATION_DIR)" "$(MOON_TEXTURES_DIR)"

normal-map: require-rust ## Build the ENU normal map PNG from the 4096 x 2048 height level and add it to moon_data.json
	cd tools/moon-data && RUSTUP_TOOLCHAIN=$(MOON_DATA_TOOLCHAIN) "$(CARGO)" build --release --locked
	$(MOON_DATA) normal-map "$(MOON_ELEVATION_DIR)" "$(MOON_TEXTURES_DIR)"

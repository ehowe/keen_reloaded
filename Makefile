# keen_reloaded — build & test automation
#
# Tested with GNU Make 3.81 (macOS default `make`) and homebrew `gmake`.
#
# Common targets:
#   make build      Export a standalone macOS .app (auto-installs export templates)
#   make run-app    Build, then launch the .app (clears macOS quarantine)
#   make templates  Download + install Godot export templates (idempotent, ~1.3GB once)
#   make run        Run the project from source
#   make test       Run the GUT unit/integration suite (headless)
#   make import     Headless import / refresh the .godot cache
#   make edit       Open the Godot editor
#   make clean      Remove build/ and the generated export preset
#
# Override the engine binary if needed:  make GODOT=/path/to/godot build

# --- Engine -----------------------------------------------------------------
GODOT ?= /Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot

# --- Build output -----------------------------------------------------------
BUILD_DIR := build
MAC_APP   := $(BUILD_DIR)/keen_reloaded.app

# --- Export templates (machine-global; shared across projects) --------------
# NOTE: this path contains a space, so it is only ever referenced inside quoted
# shell recipes — never used as a Make target/prerequisite.
GODOT_VERDIR := 4.7.stable
TMPL_DIR     := $(HOME)/Library/Application Support/Godot/export_templates/$(GODOT_VERDIR)
# existence of macos.zip == "macOS export template installed"
TMPL_MARKER  := $(TMPL_DIR)/macos.zip
TPZ          := Godot_v4.7-stable_export_templates.tpz
TPZ_URL      := https://github.com/godotengine/godot/releases/download/4.7-stable/$(TPZ)

.PHONY: all build templates test import run run-app edit clean check-godot help

all: build

help:
	@echo "keen_reloaded targets:"
	@echo "  make build      - export macOS .app (installs templates if missing)"
	@echo "  make run-app    - build then launch the .app"
	@echo "  make templates  - install export templates (~1.3GB, one-time)"
	@echo "  make run        - run project from source"
	@echo "  make test       - run GUT tests"
	@echo "  make import     - headless import"
	@echo "  make edit       - open Godot editor"
	@echo "  make clean      - remove build/ + export_presets.cfg"

# ---------------------------------------------------------------------------
# Export templates: downloaded automatically if the macOS marker is absent.
# (~1.3 GB, one-time; shared by all Godot 4.7 projects on this machine.)
# ---------------------------------------------------------------------------
templates:
	@if [ -f "$(TMPL_MARKER)" ]; then \
		echo ">> Export templates already installed."; \
	else \
		echo ">> Export templates missing. Downloading $(TPZ) (~1.3 GB, one-time)..." && \
		mkdir -p "$(TMPL_DIR)" && \
		tmp=$$(mktemp -d) && \
		curl -fL --progress-bar -o "$$tmp/$(TPZ)" "$(TPZ_URL)" && \
		unzip -q "$$tmp/$(TPZ)" -d "$$tmp" && \
		cp -R "$$tmp/templates/." "$(TMPL_DIR)/" && \
		rm -rf "$$tmp" && \
		echo ">> Installed -> $(TMPL_MARKER)"; \
	fi

# ---------------------------------------------------------------------------
# Generated export preset (gitignored; auto-created if absent).
# ---------------------------------------------------------------------------
export_presets.cfg:
	@echo ">> Generating $@"
	@printf '%s\n' \
		'[preset.0]' '' \
		'name="macOS"' 'platform="macOS"' 'runnable=true' 'dedicated_server=false' \
		'export_filter="all_resources"' 'include_filter=""' 'exclude_filter=""' \
		'export_path="$(MAC_APP)"' '' \
		'[preset.0.options]' \
		'custom_template/debug=""' 'custom_template/release=""' \
		'application/bundle_identifier="com.keenreloaded.game"' \
		'application/short_version="1.0"' 'application/version="1.0"' \
		'application/min_macos_version="10.12"' 'display/high_res=true' \
		'codesign/codesign=0' 'notarization/notarization=0' > $@

# ---------------------------------------------------------------------------
# Build: standalone macOS .app. Re-exports every run so source edits ship.
# Depends on: engine check, templates (auto-install), preset (auto-gen), import.
# ---------------------------------------------------------------------------
build: check-godot templates export_presets.cfg import
	@echo ">> Exporting macOS release -> $(MAC_APP)"
	@mkdir -p $(BUILD_DIR)
	@$(GODOT) --headless --export-release "macOS" "$(MAC_APP)"
	@echo ">> Built: $(MAC_APP)"
	@echo ">> Launch with: make run-app"

check-godot:
	@test -x "$(GODOT)" || { echo "ERROR: Godot not found at $(GODOT)"; echo "Override with: make GODOT=/path/to/godot build"; exit 1; }

import:
	@$(GODOT) --headless --import --quit

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
run: check-godot
	@$(GODOT) --path .

run-app: build
	@xattr -dr com.apple.quarantine "$(MAC_APP)" 2>/dev/null || true
	@open "$(MAC_APP)"

# ---------------------------------------------------------------------------
# Test / editor / clean
# ---------------------------------------------------------------------------
test: check-godot
	@./tests/run_all.sh

edit: check-godot
	@$(GODOT) -e

clean:
	@rm -rf $(BUILD_DIR) export_presets.cfg
	@echo ">> Removed build/ and export_presets.cfg"

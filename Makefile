# keen_reloaded — build & test automation
#
# Tested with GNU Make 3.81 (macOS default `make`) and homebrew `gmake`.
#
# Common targets:
#   make build      Export a standalone app for the CURRENT OS/arch
#                   (macOS -> .app, Windows -> .exe, Linux -> binary)
#   make build-all  Cross-build all three desktop targets into build/
#   make run-app    Build for current host, then launch it
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
APP_NAME  := keen_reloaded
MAC_APP   := $(BUILD_DIR)/$(APP_NAME).app
WIN_EXE   := $(BUILD_DIR)/$(APP_NAME)_windows.exe
LINUX_BIN := $(BUILD_DIR)/$(APP_NAME)_linux.x86_64

# --- Host OS/arch detection -------------------------------------------------
# `make build` targets the host; `make build-all` cross-builds all platforms.
HOST_OS   := $(shell uname -s)
HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_OS),Darwin)
  HOST_PRESET := macOS
  HOST_OUTPUT := $(MAC_APP)
else ifeq ($(HOST_OS),Linux)
  HOST_PRESET := Linux
  HOST_OUTPUT := $(LINUX_BIN)
else ifneq (,$(filter MINGW% MSYS% CYGWIN%,$(HOST_OS)))
  HOST_PRESET := Windows Desktop
  HOST_OUTPUT := $(WIN_EXE)
else
  $(error Unsupported host OS: $(HOST_OS))
endif

# --- Export templates (machine-global; shared across projects) --------------
# NOTE: this path contains a space, so it is only ever referenced inside quoted
# shell recipes — never used as a Make target/prerequisite.
GODOT_VERDIR := 4.7.stable
TMPL_DIR     := $(HOME)/Library/Application Support/Godot/export_templates/$(GODOT_VERDIR)
# existence of macos.zip == "export-templates package extracted"
# (the official .tpz bundles macOS + Windows + Linux templates together, so one
# marker proves all three are present).
TMPL_MARKER  := $(TMPL_DIR)/macos.zip
TPZ          := Godot_v4.7-stable_export_templates.tpz
TPZ_URL      := https://github.com/godotengine/godot/releases/download/4.7-stable/$(TPZ)

.PHONY: all build build-all templates test import run run-app edit clean check-godot help

all: build

help:
	@echo "keen_reloaded targets:"
	@echo "  make build      - export app for current OS/arch ($(HOST_OS)/$(HOST_ARCH))"
	@echo "  make build-all  - cross-build macOS + Windows + Linux into build/"
	@echo "  make run-app    - build (current host) then launch"
	@echo "  make templates  - install export templates (~1.3GB, one-time)"
	@echo "  make run        - run project from source"
	@echo "  make test       - run GUT tests"
	@echo "  make import     - headless import"
	@echo "  make edit       - open Godot editor"
	@echo "  make clean      - remove build/ + export_presets.cfg"

# ---------------------------------------------------------------------------
# Export templates: downloaded automatically if the marker is absent.
# (~1.3 GB, one-time; the .tpz contains macOS + Windows + Linux templates, so a
# single install powers both `build` and `build-all`.)
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
# Defines presets for all three desktop platforms: macOS / Windows Desktop / Linux.
# Windows + Linux embed the .pck for self-contained single-file executables.
# ---------------------------------------------------------------------------
export_presets.cfg:
	@echo ">> Generating $@"
	@{ \
		printf '%s\n' '[preset.0]' '' \
			'name="macOS"' 'platform="macOS"' 'runnable=true' 'dedicated_server=false' \
			'export_filter="all_resources"' 'include_filter=""' 'exclude_filter=""' \
			'export_path="$(MAC_APP)"' '' \
			'[preset.0.options]' \
			'custom_template/debug=""' 'custom_template/release=""' \
			'application/bundle_identifier="com.keenreloaded.game"' \
			'application/short_version="1.0"' 'application/version="1.0"' \
			'application/min_macos_version="10.12"' 'display/high_res=true' \
			'codesign/codesign=0' 'notarization/notarization=0' '' ; \
		printf '%s\n' '[preset.1]' '' \
			'name="Windows Desktop"' 'platform="Windows Desktop"' 'runnable=true' 'dedicated_server=false' \
			'export_filter="all_resources"' 'include_filter=""' 'exclude_filter=""' \
			'export_path="$(WIN_EXE)"' '' \
			'[preset.1.options]' \
			'custom_template/debug=""' 'custom_template/release=""' \
			'binary_format/embed_pck=true' '' ; \
		printf '%s\n' '[preset.2]' '' \
			'name="Linux"' 'platform="Linux"' 'runnable=true' 'dedicated_server=false' \
			'export_filter="all_resources"' 'include_filter=""' 'exclude_filter=""' \
			'export_path="$(LINUX_BIN)"' '' \
			'[preset.2.options]' \
			'custom_template/debug=""' 'custom_template/release=""' \
			'binary_format/embed_pck=true' ; \
	} > $@

# ---------------------------------------------------------------------------
# Build: standalone app for the CURRENT host OS/arch. Re-exports every run.
# Depends on: engine check, templates (auto-install), preset (auto-gen), import.
# ---------------------------------------------------------------------------
build: check-godot templates export_presets.cfg import
	@echo ">> Exporting $(HOST_PRESET) ($(HOST_OS)/$(HOST_ARCH)) -> $(HOST_OUTPUT)"
	@mkdir -p $(BUILD_DIR)
	@$(GODOT) --headless --export-release "$(HOST_PRESET)" "$(HOST_OUTPUT)"
	@echo ">> Built: $(HOST_OUTPUT)"
	@echo ">> Launch with: make run-app"

# ---------------------------------------------------------------------------
# Build-all: cross-build every desktop platform into build/.
# (Templates for all three ship in the single .tpz installed by `templates`.)
# ---------------------------------------------------------------------------
build-all: check-godot templates export_presets.cfg import
	@mkdir -p $(BUILD_DIR)
	@echo ">> Exporting macOS..."
	@$(GODOT) --headless --export-release "macOS" "$(MAC_APP)"
	@echo ">> Exporting Windows Desktop..."
	@$(GODOT) --headless --export-release "Windows Desktop" "$(WIN_EXE)"
	@echo ">> Exporting Linux..."
	@$(GODOT) --headless --export-release "Linux" "$(LINUX_BIN)"
	@echo ">> Built all platforms:"
	@echo "   $(MAC_APP)"
	@echo "   $(WIN_EXE)"
	@echo "   $(LINUX_BIN)"

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
ifeq ($(HOST_OS),Darwin)
	@xattr -dr com.apple.quarantine "$(HOST_OUTPUT)" 2>/dev/null || true
	@open "$(HOST_OUTPUT)"
else ifeq ($(HOST_OS),Linux)
	@"$(HOST_OUTPUT)"
else
	@"$(HOST_OUTPUT)"
endif

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

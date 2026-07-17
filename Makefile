# keen_reloaded — build & test automation
#
# Tested with GNU Make 3.81 (macOS default `make`) and homebrew `gmake`.
#
# Common targets:
#   make build      Export a standalone app for the CURRENT OS/arch
#                   (macOS -> .app, Windows -> .exe, Linux -> binary)
#   make build-all  Cross-build all three desktop targets into build/
#                   (macOS export also produces a .dmg via create-dmg)
#   make run-app    Build for current host, then launch it
#   make templates  Download + install Godot export templates (idempotent, ~1.3GB once)
#   make run        Run the project from source
#   make test       Run the GUT unit/integration suite (headless)
#   make import     Headless import / refresh the .godot cache
#   make edit       Open the Godot editor
#   make clean      Remove build/ and the generated export preset
#   make version    Show current version + last tag + commits since tag
#   make release-dry Preview the version a release would cut (no side effects)
#   make release    Bump VERSION, patch project.godot, generate changelog, commit + tag
#
# Override the engine binary if needed:  make GODOT=/path/to/godot build

# --- Engine -----------------------------------------------------------------
GODOT ?= /Users/eugene/.local/share/mise/installs/godot/4.7-stable/Godot.app/Contents/MacOS/Godot

# --- Build output -----------------------------------------------------------
BUILD_DIR := build
APP_NAME  := keen_reloaded
MAC_APP   := $(BUILD_DIR)/macos/$(APP_NAME).app
WIN_EXE   := $(BUILD_DIR)/windows/$(APP_NAME)_windows.exe
LINUX_BIN := $(BUILD_DIR)/linux/$(APP_NAME)_linux.x86_64

# --- Versioning (CalVer YYYY.MM.DD) -----------------------------------------
VERSION_FILE := VERSION
VERSION      := $(shell cat $(VERSION_FILE) 2>/dev/null || echo "0.0.0")
LAST_TAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "")

MAC_DMG      := $(BUILD_DIR)/dist/$(APP_NAME).$(VERSION).dmg
# Clean staging folder holding ONLY the .app, so stray build artifacts (prior
# DMGs, create-dmg's own rw.*.dmg staging files) can never leak into the image.
MAC_DMG_STAGE := $(BUILD_DIR)/dmg-staging

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

.PHONY: all build build-all macos-dmg templates test import convert-levels run run-app edit clean check-godot version release release-dry help

all: build

help:
	@echo "keen_reloaded targets:"
	@echo "  make build      - export app for current OS/arch ($(HOST_OS)/$(HOST_ARCH))"
	@echo "  make build-all  - cross-build macOS (+DMG) + Windows + Linux into build/"
	@echo "  make run-app    - build (current host) then launch"
	@echo "  make templates  - install export templates (~1.3GB, one-time)"
	@echo "  make run        - run project from source"
	@echo "  make test       - run GUT tests"
	@echo "  make import     - headless import"
	@echo "  make convert-levels - regenerate binary .res from .tres LevelData"
	@echo "  make edit       - open Godot editor"
	@echo "  make clean      - remove build/ + export_presets.cfg"
	@echo "  make version    - show current version + last tag + commits since tag"
	@echo "  make release-dry - preview the version a release would cut"
	@echo "  make release    - bump VERSION, changelog, commit + tag"

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
			'application/short_version="$(VERSION)"' 'application/version="$(VERSION)"' \
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
build: check-godot templates export_presets.cfg import convert-levels
	@mkdir -p $(dir $(HOST_OUTPUT))
	@echo ">> Exporting $(HOST_PRESET) ($(HOST_OS)/$(HOST_ARCH)) -> $(HOST_OUTPUT)"
	@$(GODOT) --headless --export-release "$(HOST_PRESET)" "$(HOST_OUTPUT)"
	@echo ">> Built: $(HOST_OUTPUT)"
ifeq ($(HOST_OS),Darwin)
	@$(MAKE) --no-print-directory macos-dmg
endif
	@echo ">> Launch with: make run-app"

# ---------------------------------------------------------------------------
# macOS DMG: stages ONLY the .app into a clean folder, then builds the image.
# create-dmg copies *everything* in its source folder into the DMG, so pointing
# it at build/macos/ would bundle stale .dmg files lying there. We also detach
# any leftover create-dmg staging volumes (/Volumes/dmg.*) and drop orphaned
# rw.*.dmg files that interrupted runs leave in the output dir.
# ---------------------------------------------------------------------------
macos-dmg:
	@echo ">> Staging .app -> $(MAC_DMG_STAGE)"
	@for v in $$(mount | sed -n 's|^.*on \(/Volumes/dmg\.[^ ]*\) .*$$|\1|p'); do \
		echo ">> Detaching stale staging volume: $$v"; \
		hdiutil detach "$$v" -force >/dev/null 2>&1 || true; \
	done
	@rm -f $(dir $(MAC_DMG))rw.*.dmg
	@rm -rf "$(MAC_DMG_STAGE)" && mkdir -p "$(MAC_DMG_STAGE)"
	@cp -R "$(MAC_APP)" "$(MAC_DMG_STAGE)/"
	@mkdir -p "$(dir $(MAC_DMG))"
	@echo ">> Creating DMG: $(MAC_DMG)"
	@create-dmg --overwrite --volname "$(APP_NAME)" "$(MAC_DMG)" "$(MAC_DMG_STAGE)"
	@rm -rf "$(MAC_DMG_STAGE)"
	@echo ">> DMG: $(MAC_DMG)"

# ---------------------------------------------------------------------------
# Build-all: cross-build every desktop platform into build/.
# (Templates for all three ship in the single .tpz installed by `templates`.)
# ---------------------------------------------------------------------------
build-all: check-godot templates export_presets.cfg import convert-levels
	@mkdir -p $(dir $(MAC_APP)) $(dir $(WIN_EXE)) $(dir $(LINUX_BIN))
	@echo ">> Exporting macOS..."
	@$(GODOT) --headless --export-release "macOS" "$(MAC_APP)"
	@$(MAKE) --no-print-directory macos-dmg
	@echo ">> Exporting Windows Desktop..."
	@$(GODOT) --headless --export-release "Windows Desktop" "$(WIN_EXE)"
	@echo ">> Exporting Linux..."
	@$(GODOT) --headless --export-release "Linux" "$(LINUX_BIN)"
	@echo ">> Built all platforms:"
	@echo "   $(MAC_APP)"
	@echo "   $(MAC_DMG)"
	@echo "   $(WIN_EXE)"
	@echo "   $(LINUX_BIN)"

check-godot:
	@test -x "$(GODOT)" || { echo "ERROR: Godot not found at $(GODOT)"; echo "Override with: make GODOT=/path/to/godot build"; exit 1; }

import:
	@$(GODOT) --headless --import --quit

# ---------------------------------------------------------------------------
# ConvertLevels: regenerate .res binaries from authored .tres LevelData.
# Godot 4.7's export converter strips PackedInt32Array tile data during
# text→binary .tres conversion, so we pre-convert via ResourceSaver (which
# preserves the arrays) and ship the .res alongside the .tres source. Runtime
# (Episode.load_overworld / load_levels) prefers the .res sibling. Re-run
# whenever a .tres under assets/levels/ changes.
# ---------------------------------------------------------------------------
convert-levels: check-godot
	@$(GODOT) --headless --path . --script tools/convert_levels_to_res.gd 2>&1 | grep -E "converted=|warning|error" || true

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
# Versioning (CalVer YYYY.MM.DD)
# ---------------------------------------------------------------------------
version:
	@echo "VERSION:  $(VERSION)"
	@if [ -n "$(LAST_TAG)" ]; then \
		since=$$(git rev-list --count $(LAST_TAG)..HEAD 2>/dev/null || echo "?"); \
		echo "Last tag: $(LAST_TAG)"; \
		echo "Commits since tag: $$since"; \
	else \
		echo "Last tag: none"; \
		echo "Commits since tag: (no tags yet)"; \
	fi

release-dry:
	@target=$$(./tools/version.sh); \
	echo ">> Dry run — would release: v$$target"; \
	echo ">> Would update: VERSION, project.godot"; \
	echo ">> Would regenerate: export_presets.cfg (gitignored)"; \
	if [ -n "$(LAST_TAG)" ]; then \
		echo ">> Changelog range: $(LAST_TAG)..HEAD"; \
	else \
		echo ">> Changelog range: full history (no prior tag)"; \
	fi; \
	echo ">> Would prepend section to CHANGELOG.md"; \
	echo ">> Would commit + tag v$$target"; \
	echo ">> (no files modified)"

release:
	@test -z "$$(git status --porcelain)" || { echo "ERROR: working tree dirty. Commit or stash first."; exit 1; }
	@set -e; \
	target=$$(./tools/version.sh); \
	echo ">> Releasing v$$target"; \
	echo "$$target" > VERSION; \
	./tools/set_project_version.sh "$$target"; \
	rm -f export_presets.cfg && $(MAKE) --no-print-directory export_presets.cfg; \
	section=$$(./tools/changelog.sh "$(LAST_TAG)" "$$target"); \
	if [ -f CHANGELOG.md ]; then \
		printf '%s\n\n' "$$section" | cat - CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md; \
	else \
		printf '# Changelog\n\n%s\n' "$$section" > CHANGELOG.md; \
	fi; \
	git add VERSION CHANGELOG.md project.godot; \
	git commit -m "chore(release): v$$target"; \
	git tag "v$$target"; \
	echo ">> Released v$$target"; \
	echo ">> Push with: git push && git push --tags"

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

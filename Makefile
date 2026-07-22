# Connectible - top-level developer Makefile.
#
# Quick start:
#   make setup      # one-time: install frontend deps + check system deps
#   make dev        # run daemon + desktop app together (one command)
#
# Run "make" or "make help" to list every target.

DAEMON_DIR   := daemon
DESKTOP_DIR  := desktop
MOBILE_DIR   := mobile
# Default daemon gRPC port; matches the daemon's and desktop's built-in
# default. Override with: make dev PORT=59000
PORT         ?= 58231

# Run each recipe in a single shell so backgrounding + trap-based
# cleanup in the "dev" target works as written.
.ONESHELL:
SHELL := /bin/bash

# Colors for readable output (fall back to nothing if not a tty).
BLUE := \033[34m
BOLD := \033[1m
DIM  := \033[2m
OFF  := \033[0m

.DEFAULT_GOAL := help

## ---------------------------------------------------------------------
## Help
## ---------------------------------------------------------------------

.PHONY: help
help:
	@echo ""
	@echo -e "$(BOLD)Connectible - make targets$(OFF)"
	@echo ""
	@echo -e "  $(BLUE)make setup$(OFF)          Install frontend deps and check system deps"
	@echo -e "  $(BLUE)make dev$(OFF)            Run daemon + desktop app together (Ctrl-C stops both)"
	@echo ""
	@echo -e "  $(BLUE)make daemon$(OFF)         Run just the daemon (foreground)"
	@echo -e "  $(BLUE)make desktop$(OFF)        Run just the desktop app (needs a daemon running)"
	@echo ""
	@echo -e "  $(BLUE)make test$(OFF)           Run all tests (Rust workspace + frontend + mobile)"
	@echo -e "  $(BLUE)make check$(OFF)          Lint everything (clippy -D warnings + tsc + flutter analyze)"
	@echo -e "  $(BLUE)make fmt$(OFF)            Format Rust code (cargo fmt)"
	@echo -e "  $(BLUE)make proto$(OFF)          Regenerate gRPC stubs for daemon + mobile from proto/connectible.proto"
	@echo ""
	@echo -e "  $(BLUE)make build$(OFF)          Build release artifacts (static daemon + frontend bundle)"
	@echo -e "  $(BLUE)make check-deps$(OFF)     Verify required system libraries are present"
	@echo -e "  $(BLUE)make clean$(OFF)          Remove build artifacts"
	@echo ""
	@echo -e "  $(BLUE)make install-service$(OFF)   Install + enable the daemon as a systemd user service"
	@echo -e "  $(BLUE)make uninstall-service$(OFF) Stop and remove the systemd user service"
	@echo ""
	@echo -e "  $(DIM)Override the daemon port with: make dev PORT=59000$(OFF)"
	@echo ""

## ---------------------------------------------------------------------
## Setup / dependency checks
## ---------------------------------------------------------------------

.PHONY: setup
setup: check-deps
	@echo -e "$(BOLD)Installing frontend dependencies...$(OFF)"
	cd $(DESKTOP_DIR) && npm install
	@echo -e "$(BOLD)Setup complete. Run 'make dev' to start.$(OFF)"

# Verifies the toolchain + the one Tauri system library that is easy to
# forget (webkit2gtk-4.1). Non-fatal for the daemon/core/frontend, which
# do not need it; only the Tauri desktop shell does.
.PHONY: check-deps
check-deps:
	@missing=0
	for tool in cargo node npm; do \
	  if ! command -v $$tool >/dev/null 2>&1; then \
	    echo -e "  MISSING tool: $$tool"; missing=1; \
	  fi; \
	done
	if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists webkit2gtk-4.1; then \
	  echo -e "  ok: webkit2gtk-4.1 (Tauri desktop shell can build)"; \
	else \
	  echo -e "  $(BOLD)note:$(OFF) webkit2gtk-4.1 not found."; \
	  echo -e "        The desktop app ('make desktop' / 'make dev') needs it."; \
	  echo -e "        Arch/CachyOS: $(BLUE)sudo pacman -S --needed webkit2gtk-4.1$(OFF)"; \
	  echo -e "        (The daemon and 'make test' do NOT require it.)"; \
	fi
	if [ $$missing -ne 0 ]; then \
	  echo -e "  Install the missing tools above, then re-run 'make setup'."; \
	  exit 1; \
	fi

## ---------------------------------------------------------------------
## Run
## ---------------------------------------------------------------------

# Runs the daemon in the background and the desktop app in the
# foreground; Ctrl-C (or the app quitting) tears the daemon down too.
.PHONY: dev
dev:
	@echo -e "$(BOLD)Building daemon...$(OFF)"
	cargo build -p connectibled
	@echo -e "$(BOLD)Starting daemon on port $(PORT)...$(OFF)"
	CONNECTIBLE_PORT=$(PORT) ./target/debug/connectibled &
	daemon_pid=$$!
	trap 'echo; echo "Stopping daemon (pid $$daemon_pid)..."; kill $$daemon_pid 2>/dev/null' EXIT INT TERM
	# Give the daemon a moment to generate its cert and bind the port
	# before the desktop app tries to connect.
	sleep 1
	@echo -e "$(BOLD)Starting desktop app...$(OFF)"
	cd $(DESKTOP_DIR) && CONNECTIBLE_PORT=$(PORT) npm run tauri dev

.PHONY: daemon
daemon:
	CONNECTIBLE_PORT=$(PORT) cargo run -p connectibled

.PHONY: desktop
desktop:
	cd $(DESKTOP_DIR) && CONNECTIBLE_PORT=$(PORT) npm run tauri dev

## ---------------------------------------------------------------------
## Test / lint / format
## ---------------------------------------------------------------------

.PHONY: test
test: test-rust test-desktop test-mobile

.PHONY: test-rust
test-rust:
	@echo -e "$(BOLD)Running Rust workspace tests...$(OFF)"
	cargo test --workspace

.PHONY: test-desktop
test-desktop:
	@echo -e "$(BOLD)Running frontend tests...$(OFF)"
	cd $(DESKTOP_DIR) && npm test

.PHONY: test-mobile
test-mobile:
	@echo -e "$(BOLD)Running mobile tests...$(OFF)"
	cd $(MOBILE_DIR) && flutter test

.PHONY: check
check:
	@echo -e "$(BOLD)clippy (Rust)...$(OFF)"
	cargo clippy --workspace --all-targets -- -D warnings
	@echo -e "$(BOLD)tsc (TypeScript strict typecheck)...$(OFF)"
	cd $(DESKTOP_DIR) && npm run typecheck
	@echo -e "$(BOLD)flutter analyze...$(OFF)"
	cd $(MOBILE_DIR) && flutter analyze

.PHONY: fmt
fmt:
	cargo fmt --all

## ---------------------------------------------------------------------
## Protocol buffers
## ---------------------------------------------------------------------

# The daemon regenerates its own stubs automatically on every `cargo
# build` via daemon/build.rs (tonic-build). This target handles the two
# stub sets that require an explicit regeneration step: mobile's Dart
# stubs (checked-in generated code) and a daemon rebuild to catch proto
# errors early. Desktop's Tauri commands consume the daemon's types
# directly over the Rust boundary (desktop/core), so there is no
# separate desktop-side codegen step.
.PHONY: proto
proto:
	@echo -e "$(BOLD)Regenerating daemon stubs (via cargo build)...$(OFF)"
	cargo build -p connectibled
	@echo -e "$(BOLD)Regenerating mobile Dart stubs...$(OFF)"
	cd $(MOBILE_DIR) && ./tool/gen_proto.sh
	@echo -e "Done. Review the diff under $(MOBILE_DIR)/lib/src/generated/ before committing."

## ---------------------------------------------------------------------
## Build / clean
## ---------------------------------------------------------------------

.PHONY: build
build:
	@echo -e "$(BOLD)Building release daemon...$(OFF)"
	cargo build --release -p connectibled
	@echo -e "$(BOLD)Building frontend bundle...$(OFF)"
	cd $(DESKTOP_DIR) && npm run build
	@echo -e "Daemon binary: $(BLUE)target/release/connectibled$(OFF)"

.PHONY: clean
clean:
	cargo clean
	rm -rf $(DESKTOP_DIR)/dist
	@echo -e "Cleaned. (node_modules kept; 'rm -rf $(DESKTOP_DIR)/node_modules' to remove.)"

## ---------------------------------------------------------------------
## Persistent service (T-1201)
## ---------------------------------------------------------------------

# Installs the release daemon binary + systemd user unit and enables it
# (no root required). Mirrors README.md's "Running the daemon
# persistently" section exactly, as one command for anyone who'd rather
# not copy-paste five lines by hand.
.PHONY: install-service
install-service:
	@echo -e "$(BOLD)Building release daemon...$(OFF)"
	cargo build --release -p connectibled
	@echo -e "$(BOLD)Installing connectibled as a systemd user service...$(OFF)"
	mkdir -p ~/.local/bin ~/.config/systemd/user
	cp target/release/connectibled ~/.local/bin/
	cp $(DAEMON_DIR)/packaging/connectibled.service ~/.config/systemd/user/
	systemctl --user daemon-reload
	systemctl --user enable --now connectibled
	@echo -e "Installed and started. Logs: $(BLUE)journalctl --user -u connectibled -f$(OFF)"
	@echo -e "Keep it running after logout too: $(BLUE)loginctl enable-linger \$$USER$(OFF)"

.PHONY: uninstall-service
uninstall-service:
	systemctl --user disable --now connectibled || true
	rm -f ~/.config/systemd/user/connectibled.service
	systemctl --user daemon-reload
	@echo -e "Service stopped and unit removed. Binary at ~/.local/bin/connectibled left in place."

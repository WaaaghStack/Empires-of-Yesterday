#!/usr/bin/env bash
# Cloud Agent install for Empires of Yesterday.
#
# Idempotent bootstrap that prepares a fresh checkout to run headless QA,
# the smoke tests, and the game itself:
#   1. Install a pinned Godot 4.6.x headless-capable editor binary.
#   2. Ensure a Rust toolchain new enough for the pinned gdext (edition2024).
#   3. Build the empire_territory GDExtension and install the Linux .so files
#      under the names empire_territory.gdextension expects.
#   4. Import Godot assets so the import cache (.godot/, gitignored) exists.
#
# Safe to run repeatedly. Designed to run non-interactively as the build user.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="${REPO_ROOT}/rust/empire_territory"
BIN_DIR="${CRATE_DIR}/bin"

GODOT_VERSION="4.6.3-stable"
GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${GODOT_ZIP}"
GODOT_BIN="/usr/local/bin/godot"

log() { printf '[install] %s\n' "$*"; }

# ---- retry helper for flaky network -----------------------------------------
retry() {
  local n=0 max=4 delay=4
  until "$@"; do
    n=$((n + 1))
    if [ "$n" -ge "$max" ]; then
      return 1
    fi
    log "command failed (attempt $n/$max); retrying in ${delay}s: $*"
    sleep "$delay"
    delay=$((delay * 2))
  done
}

maybe_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    "$@"
  fi
}

# ---- 1. Godot ----------------------------------------------------------------
install_godot() {
  if command -v godot >/dev/null 2>&1 && godot --headless --version 2>/dev/null | grep -q "^4\.6"; then
    log "Godot already present: $(godot --headless --version 2>/dev/null | tail -1)"
    return 0
  fi
  log "Installing Godot ${GODOT_VERSION} ..."
  local tmp
  tmp="$(mktemp -d)"
  retry curl -fL -o "${tmp}/godot.zip" "${GODOT_URL}"
  ( cd "${tmp}" && unzip -o -q godot.zip )
  maybe_sudo install -m 0755 "${tmp}/Godot_v${GODOT_VERSION}_linux.x86_64" "${GODOT_BIN}"
  rm -rf "${tmp}"
  log "Godot installed: $(godot --headless --version 2>/dev/null | tail -1)"
}

# ---- 2. Rust toolchain -------------------------------------------------------
ensure_rust() {
  if ! command -v rustup >/dev/null 2>&1; then
    log "rustup not found; installing via rustup.rs ..."
    retry bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal'
    # shellcheck disable=SC1091
    source "${CARGO_HOME:-$HOME/.cargo}/env"
  fi
  # gdext (pinned rev) pulls a workspace whose itest crate needs edition2024,
  # which is only stabilized on Rust >= 1.85, so make sure stable is current.
  retry rustup toolchain install stable --profile minimal
  rustup default stable
  log "Rust: $(rustc --version)"
}

# ---- 3. Build + install the GDExtension --------------------------------------
build_extension() {
  log "Building empire_territory (debug + release) ..."
  export CARGO_TARGET_DIR="${CRATE_DIR}/target"
  ( cd "${CRATE_DIR}" && cargo build && cargo build --release )
  mkdir -p "${BIN_DIR}"
  cp -f "${CRATE_DIR}/target/debug/libempire_territory.so" \
        "${BIN_DIR}/libempire_territory.linux.template_debug.x86_64.so"
  cp -f "${CRATE_DIR}/target/release/libempire_territory.so" \
        "${BIN_DIR}/libempire_territory.linux.template_release.x86_64.so"
  log "Installed Linux .so into ${BIN_DIR}"
}

# ---- 4. Import Godot assets --------------------------------------------------
import_assets() {
  log "Importing Godot assets (populates .godot/ cache) ..."
  # --import exits non-zero on some setups even when the cache is written; the
  # subsequent Godot runs are what actually gate on a good import.
  godot --headless --path "${REPO_ROOT}" --import >/dev/null 2>&1 || true
  log "Asset import complete."
}

main() {
  install_godot
  ensure_rust
  build_extension
  import_assets
  log "Done. Run headless QA with: godot --headless --path . res://qa_runner.tscn"
}

main "$@"

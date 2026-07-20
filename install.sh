#!/usr/bin/env bash
#
# oh-my-grok — one-line installer
#
#   curl -fsSL https://raw.githubusercontent.com/ShawnRyan2365/oh-my-grok/main/install.sh | bash
#
# Downloads a prebuilt binary from GitHub Releases for your platform. If no
# prebuilt binary exists, falls back to building from source (needs Rust).
# Installs to ~/.local/bin and ensures it is on your PATH.
set -euo pipefail

OWNER="ShawnRyan2365"
REPO="oh-my-grok"
BIN_NAME="oh-my-grok"
INSTALL_DIR="${OMG_INSTALL_DIR:-${HOME}/.local/bin}"
VERSION="${OMG_VERSION:-latest}"   # "latest" or a tag like "v0.2.106-omg.1"
BUILD_FROM_SOURCE="${OMG_BUILD_FROM_SOURCE:-0}"

c_red()   { printf '\033[31m%s\033[0m\n' "$*"; }
c_green() { printf '\033[32m%s\033[0m\n' "$*"; }
c_dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
info()    { printf '  %s\n' "$*"; }
die()     { c_red "error: $*"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
need curl
need file
if command -v shasum >/dev/null 2>&1; then SUM_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then SUM_CMD="sha256sum"
else die "missing required command: shasum or sha256sum"; fi

# ── detect platform ────────────────────────────────────────────────────────
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Darwin) platform="apple-darwin" ;;
  Linux)  platform="unknown-linux-gnu" ;;
  *)      die "unsupported OS: $os (prebuilt binaries exist for macOS and Linux; set OMG_BUILD_FROM_SOURCE=1 to build from source)" ;;
esac
case "$arch" in
  arm64|aarch64) rust_arch="aarch64" ;;
  x86_64|amd64)  rust_arch="x86_64" ;;
  *)             die "unsupported arch: $arch" ;;
esac
asset="${BIN_NAME}-${rust_arch}-${platform}"
info "detected: ${rust_arch}-${platform}"

# ── choose install path ────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
dst="${INSTALL_DIR}/${BIN_NAME}"

# ── download URL ───────────────────────────────────────────────────────────
if [ "$VERSION" = "latest" ]; then
  url="https://github.com/${OWNER}/${REPO}/releases/latest/download/${asset}"
else
  url="https://github.com/${OWNER}/${REPO}/releases/download/${VERSION}/${asset}"
fi

# ── fetch prebuilt, or build from source ───────────────────────────────────
fetch_prebuilt() {
  tmp="$(mktemp)"
  sha_url="$(dirname "$url")/checksums.txt"
  for attempt in 1 2 3; do
    info "downloading ${asset} (attempt ${attempt}/3)…"
    if ! curl -fSL "$url" -o "$tmp" 2>/dev/null; then
      sleep 1; continue
    fi
    # must be an executable image, not an HTML error/redirect page
    if ! file "$tmp" | grep -qiE "Mach-O|ELF|executable|shared object"; then
      c_dim "  response was not a binary (likely an error page); retrying"
      sleep 1; continue
    fi
    # verify checksum if checksums.txt is published alongside the asset
    expected="$(curl -fsSL "$sha_url" 2>/dev/null | awk -v a="$asset" '$2 == a {print $1; exit}')"
    if [ -n "$expected" ]; then
      actual="$(${SUM_CMD} "$tmp" | awk '{print $1}')"
      if [ "$expected" != "$actual" ]; then
        c_dim "  checksum mismatch (expected ${expected:0:12}…, got ${actual:0:12}…); retrying"
        sleep 1; continue
      fi
    fi
    install -m 755 "$tmp" "$dst"
    rm -f "$tmp"
    return 0
  done
  rm -f "$tmp"
  return 1
}

build_from_source() {
  info "building from source (needs Rust + protoc)…"
  need cargo
  src="${OMG_SOURCE_DIR:-${HOME}/.cache/oh-my-grok-src}"
  if [ ! -d "$src/.git" ]; then
    rm -rf "$src"; git clone --depth 1 "https://github.com/${OWNER}/${REPO}.git" "$src"
  else
    git -C "$src" pull -q --ff-only || true
  fi
  ( cd "$src" && PROTOC="${PROTOC:-$(command -v protoc || true)}" cargo build -p xai-grok-pager-bin --release )
  install -m 755 "$src/target/release/${BIN_NAME}" "$dst"
}

if [ "$BUILD_FROM_SOURCE" = "1" ]; then
  build_from_source
elif ! fetch_prebuilt; then
  c_dim "  no prebuilt binary for ${rust_arch}-${platform}; building from source"
  build_from_source
fi

# ── ensure PATH ────────────────────────────────────────────────────────────
on_path=0
case ":${PATH}:" in *":${INSTALL_DIR}:"*) on_path=1 ;; esac

if [ "$on_path" = "0" ] && [ "${OMG_NO_PATH_EDIT:-0}" != "1" ]; then
  rc=""
  case "$(basename "${SHELL:-}")" in
    zsh)  rc="${HOME}/.zshrc" ;;
    bash) rc="${HOME}/.bashrc" ;;
    fish) rc="${HOME}/.config/fish/config.fish" ;;
    *)    rc="${HOME}/.profile" ;;
  esac
  if [ -n "${rc:-}" ]; then
    line="export PATH=\"\$PATH:${INSTALL_DIR}\""
    case "$(basename "${SHELL:-}")" in
      fish) line="set -gx PATH \$PATH ${INSTALL_DIR}" ;;
    esac
    if ! grep -qF "${INSTALL_DIR}" "$rc" 2>/dev/null; then
      printf '\n# added by oh-my-grok installer\n%s\n' "$line" >> "$rc"
      info "added ${INSTALL_DIR} to PATH in ${rc}"
    fi
    export PATH="${PATH}:${INSTALL_DIR}"
  fi
fi

# ── report ─────────────────────────────────────────────────────────────────
c_green "✔ ${BIN_NAME} installed to ${dst}"
if "$dst" --version >/dev/null 2>&1; then
  info "version: $("$dst" --version)"
fi
if [ "$on_path" = "0" ]; then
  c_dim "  restart your shell (or open a new terminal), then run:"
else
  info "now run:"
fi
printf '    %s\n' "${BIN_NAME}"

#!/usr/bin/env bash
# Install nomen: copy script, ensure PATH.
#
#   curl -fsSL https://raw.githubusercontent.com/Comninos/nomen/master/install.sh | bash
#   curl -fsSL …/install.sh | sudo bash -s -- --system
#   ./install.sh

set -euo pipefail

RAW_BASE="${NOMEN_RAW_BASE:-https://raw.githubusercontent.com/Comninos/nomen/master}"
SYSTEM="${NOMEN_SYSTEM:-0}"
ASSUME_YES=0

say() { printf '%s\n' "$*"; }
warn() { printf 'nomen install: %s\n' "$*" >&2; }
die() { printf 'nomen install: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: install.sh [options]

  --system     Install to /usr/local/bin (requires root)
  -y, --yes    Skip prompts
  -h, --help   Show this help

Env: NOMEN_SYSTEM=1  NOMEN_RAW_BASE=<url>
EOF
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "need '$1'"
}

case "${OSTYPE:-}" in
    msys*|cygwin*|mingw*) die "Windows is not supported (use Linux, macOS, or WSL)" ;;
esac
case "$(uname -s 2>/dev/null || true)" in
    MINGW*|MSYS*|CYGWIN*) die "Windows is not supported (use Linux, macOS, or WSL)" ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system) SYSTEM=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

src_file=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
    if [[ -n "${_here}" && -f "${_here}/nomen.sh" ]]; then
        src_file="${_here}/nomen.sh"
    fi
fi

fetch_script() {
    local dest="$1"
    if [[ -n "$src_file" ]]; then
        cp "$src_file" "$dest"
        return
    fi
    need_cmd curl
    curl -fsSL "${RAW_BASE}/nomen.sh" -o "$dest"
}

path_has_dir() {
    case ":${PATH}:" in
        *":$1:"*) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_path_session() {
    local dir="$1"
    path_has_dir "$dir" && return 0
    export PATH="${dir}:${PATH}"
    say "added ${dir} to PATH for this session"
}

append_path_export() {
    local rc="$1" dir="$2"
    local marker_begin="# >>> nomen path >>>"
    local marker_end="# <<< nomen path >>>"
    if [[ -f "$rc" ]] && grep -qF "$marker_begin" "$rc" 2>/dev/null; then
        say "PATH export already present in ${rc}"
        return
    fi
    mkdir -p "$(dirname "$rc")"
    if [[ -f "$rc" && -s "$rc" ]]; then
        printf '\n' >>"$rc"
    fi
    cat >>"$rc" <<EOF
${marker_begin}
case ":\$PATH:" in *":${dir}:"*) ;; *) export PATH="${dir}:\$PATH" ;; esac
${marker_end}
EOF
    say "added PATH export to ${rc}"
}

user_rcs() {
    local found=0
    if [[ -f "${HOME}/.bashrc" || "${SHELL:-}" == *bash* || ! -f "${HOME}/.zshrc" ]]; then
        printf '%s\n' "${HOME}/.bashrc"
        found=1
    fi
    if [[ -f "${HOME}/.zshrc" || "${SHELL:-}" == *zsh* ]]; then
        printf '%s\n' "${HOME}/.zshrc"
        found=1
    fi
    if [[ "$found" -eq 0 ]]; then
        printf '%s\n' "${HOME}/.bashrc"
    fi
}

if [[ "$SYSTEM" == "1" ]]; then
    [[ "$(id -u)" -eq 0 ]] || die "--system / NOMEN_SYSTEM=1 requires root (try sudo)"
    bin_dir="/usr/local/bin"
    bin_path="${bin_dir}/nomen"
else
    bin_dir="${HOME}/.local/bin"
    bin_path="${bin_dir}/nomen"
fi

say ""
say "Install nomen to ${bin_path}"
say ""

mkdir -p "$bin_dir"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
fetch_script "$tmp"
install -m 0755 "$tmp" "$bin_path"
say "installed ${bin_path}"

if [[ "$SYSTEM" == "1" ]]; then
    if ! path_has_dir "$bin_dir"; then
        warn "${bin_dir} is not on PATH in this environment"
    fi
else
    ensure_path_session "$bin_dir"
    while IFS= read -r rc; do
        append_path_export "$rc" "$bin_dir"
    done < <(user_rcs | sort -u)
fi

say ""
if ! command -v nomen >/dev/null 2>&1; then
    warn "file installed at ${bin_path}, but the 'nomen' command is not on PATH"
    warn "open a new shell, or run:  export PATH=\"${bin_dir}:\$PATH\""
    die "install incomplete: 'nomen' not available as a command"
fi

say "verified: $(command -v nomen)"
say ""
say "run:  nomen ."
say "edit ${bin_path} to change BATCH_PAD / APPLY"

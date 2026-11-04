#!/usr/bin/env bash
# scripts/bootstrap.sh — cài toolchain + git hooks cho dev mới (macOS / Linux)
#
#   ./scripts/bootstrap.sh            # cài mọi thứ + pre-commit install
#   ./scripts/bootstrap.sh --check    # chỉ kiểm tra, không cài
#
# Idempotent: chạy lại bao nhiêu lần cũng được.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
# shellcheck source=scripts/hooks/_path.sh
source scripts/hooks/_path.sh
# shellcheck source=scripts/hooks/_platform.sh
source scripts/hooks/_platform.sh

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓ \033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✗ \033[0m %s\n' "$*" >&2; exit 1; }

kit_platform || exit 1
log "Platform: $KIT_OS/$KIT_ARCH${KIT_LIBC:+ ($KIT_LIBC)} · package manager: ${KIT_PKG:-?}"
missing=()
for c in git curl python3; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
[[ ${#missing[@]} -gt 0 ]] && die "Thiếu: ${missing[*]}. Cài rồi chạy lại:  $(kit_pkg_hint "${missing[@]}")"

# -----------------------------------------------------------------------------
# 1. mise — quản lý version mọi tool (xem mise.toml)
# -----------------------------------------------------------------------------
if ! command -v mise >/dev/null 2>&1; then
  [[ $CHECK_ONLY -eq 1 ]] && die "mise chưa cài. Xem https://mise.jdx.dev/installing-mise.html"
  log "Cài mise"
  if [[ "$KIT_OS" == "darwin" ]] && command -v brew >/dev/null 2>&1; then
    brew install mise
  else
    # Installer chính thức (tải về file rồi chạy, không curl | sh); tự chọn binary theo OS/arch/libc
    tmp="$(mktemp)"
    curl -fsSL https://mise.run -o "$tmp"
    sh "$tmp"
    rm -f "$tmp"
  fi
  source scripts/hooks/_path.sh
fi
command -v mise >/dev/null 2>&1 || die "mise vẫn không có trong PATH. Mở shell mới rồi chạy lại."
ok "mise $(mise --version)"

# Nhắc activate cho shell interactive (shims đã đủ cho git hook)
shell_rc=""
case "${SHELL:-}" in
  */zsh)  shell_rc="$HOME/.zshrc";  act='eval "$(mise activate zsh)"' ;;
  */bash) shell_rc="$HOME/.bashrc"; act='eval "$(mise activate bash)"' ;;
  */fish) shell_rc="$HOME/.config/fish/config.fish"; act='mise activate fish | source' ;;
esac
if [[ -n "$shell_rc" ]] && ! grep -qs "mise activate" "$shell_rc"; then
  warn "Thêm dòng sau vào $shell_rc để dùng tool trong terminal:  $act"
fi

# -----------------------------------------------------------------------------
# 2. Cài toolchain theo mise.toml
# -----------------------------------------------------------------------------
if [[ $CHECK_ONLY -eq 0 ]]; then
  log "mise install (theo mise.toml)"
  mise install
fi

missing_tools=0
for t in pre-commit gitleaks trivy golangci-lint govulncheck hadolint shellcheck actionlint terraform tflint go node java; do
  if mise which "$t" >/dev/null 2>&1 || command -v "$t" >/dev/null 2>&1; then
    ok "$t"
  else
    warn "thiếu: $t"
    missing_tools=1
  fi
done
[[ $missing_tools -eq 1 && $CHECK_ONLY -eq 1 ]] && die "Thiếu tool. Chạy ./scripts/bootstrap.sh (không --check)."

# -----------------------------------------------------------------------------
# 3. Node deps (eslint/prettier/tsc lấy từ node_modules của repo)
# -----------------------------------------------------------------------------
if [[ -f package.json && $CHECK_ONLY -eq 0 ]]; then
  if [[ -f pnpm-lock.yaml ]]; then
    log "pnpm install"; mise exec -- corepack enable >/dev/null 2>&1 || true; pnpm install --frozen-lockfile
  elif [[ -f yarn.lock ]]; then
    log "yarn install"; yarn install --frozen-lockfile
  elif [[ -f package-lock.json ]]; then
    log "npm ci"; mise exec -- npm ci
  fi
fi

# -----------------------------------------------------------------------------
# 4. Cài git hooks
# -----------------------------------------------------------------------------
global_hooks="$(git config --global --get core.hooksPath 2>/dev/null || true)"
if [[ $CHECK_ONLY -eq 0 && -n "$global_hooks" && -x "$global_hooks/dispatch.sh" ]]; then
  # Đã cài global bằng install.sh: dispatcher tự dùng .pre-commit-config.yaml của repo,
  # không cần (và pre-commit cũng từ chối) `pre-commit install` khi core.hooksPath được đặt.
  log "Global dispatcher đang bật ($global_hooks) -> bỏ qua pre-commit install; chỉ chuẩn bị env"
  mise exec -- pre-commit install-hooks
  ok "env của hook đã sẵn sàng"
elif [[ $CHECK_ONLY -eq 0 ]]; then
  log "pre-commit install (pre-commit, commit-msg, pre-push)"
  mise exec -- pre-commit install --install-hooks \
    --hook-type pre-commit --hook-type commit-msg --hook-type pre-push
  ok "hooks đã cài vào .git/hooks"
fi

if [[ $CHECK_ONLY -eq 0 ]]; then
  # Làm nóng trivy DB (lần đầu ~70MB) để pre-push không chờ lâu
  log "trivy: tải vuln DB (1 lần)"
  mise exec -- trivy fs --scanners vuln --quiet --exit-code 0 --no-progress \
    --skip-dirs node_modules,vendor . >/dev/null 2>&1 || warn "trivy DB chưa tải được (mạng?). Sẽ tải khi pre-push."
fi

log "Xong. Thử: pre-commit run --all-files"

#!/usr/bin/env bash
# install.sh — cài precommit-kit ở mức GLOBAL cho git (macOS / Linux)
#
#   ./install.sh                 # cài: mise -> TOÀN BỘ tool trong mise.toml (global) -> core.hooksPath, profile "full"
#   ./install.sh --minimal       # chỉ pre-commit + gitleaks; profile "minimal" (gitleaks + vệ sinh)
#   ./install.sh --no-mise       # không đụng mise; tự đảm bảo tool có trong PATH
#   ./install.sh --status        # xem trạng thái
#   ./install.sh --uninstall     # gỡ core.hooksPath + thư mục cài; không xoá tool
#
# Thứ tự dùng:  ./install.sh  ->  git clone <repo>  ->  git commit  => toàn bộ kit chạy, repo không cần file nào.
# Sau khi cài, MỌI repo trên máy:
#   - có .pre-commit-config.yaml  -> chạy config của repo
#   - không có                    -> chạy profile global (full: cả kit, config mặc định từ ~/.config/precommit-kit/config;
#                                    repo có .golangci.yml/.gitleaks.toml/... riêng thì file của repo được ưu tiên)
#   - hook cục bộ .git/hooks/* (husky, lefthook, tự viết) vẫn được chain chạy trước.
#
# Idempotent; chạy lại để cập nhật dispatcher/config sau khi pull kit mới.
set -euo pipefail

KIT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_HOME="${PRECOMMIT_KIT_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/precommit-kit}"
HOOKS_DIR="$KIT_HOME/hooks"

# Tool tối thiểu (profile minimal). Version lấy từ mise.toml của kit để không lệch.
MINIMAL_TOOLS=(pre-commit gitleaks)
# Tool profile full = toàn bộ [tools] trong mise.toml
FULL_TOOLS=(pre-commit gitleaks trivy golangci-lint govulncheck hadolint shellcheck actionlint terraform tflint go node java)
# File config mặc định copy vào $KIT_HOME/config (repo có file cùng tên thì ưu tiên repo)
CONFIG_FILES=(.gitleaks.toml .golangci.yml .trivyignore .hadolint.yaml .yamllint.yml .typos.toml .markdownlint.yaml .sqlfluff .tflint.hcl checkstyle.xml)

# Danh sách hook client-side của git (phải symlink đủ, vì core.hooksPath thay thế .git/hooks)
GIT_HOOKS=(
  applypatch-msg pre-applypatch post-applypatch
  pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit
  pre-rebase post-checkout post-merge pre-push
  pre-auto-gc post-rewrite sendemail-validate fsmonitor-watchman
  post-index-change reference-transaction
)

# shellcheck source=scripts/hooks/_platform.sh
source "$KIT_SRC/scripts/hooks/_platform.sh"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓ \033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ! \033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✗ \033[0m %s\n' "$*" >&2; exit 1; }

add_path() {
  for _p in "${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims" "$HOME/.local/bin" \
            /opt/homebrew/bin /home/linuxbrew/.linuxbrew/bin /usr/local/bin; do
    [[ -d "$_p" ]] && case ":$PATH:" in *":$_p:"*) ;; *) PATH="$_p:$PATH" ;; esac
  done
  export PATH
}

# Đọc version của 1 tool từ mise.toml (dòng dạng: name = "x.y.z")
tool_version() {
  sed -n -E "s/^\"?$1\"? *= *\"([^\"]+)\".*/\1/p" "$KIT_SRC/mise.toml" | head -1
}

# -----------------------------------------------------------------------------
status() {
  add_path
  log "Trạng thái precommit-kit"
  local hp
  hp="$(git config --global --get core.hooksPath || true)"
  if [[ "$hp" == "$HOOKS_DIR" ]]; then ok "core.hooksPath = $hp"; else warn "core.hooksPath (global) = '${hp:-<chưa đặt>}' (mong đợi: $HOOKS_DIR)"; fi
  [[ -x "$HOOKS_DIR/dispatch.sh" ]] && ok "dispatcher: $HOOKS_DIR/dispatch.sh" || warn "thiếu dispatcher"
  local prof; prof="$(git config --get precommit-kit.profile 2>/dev/null || cat "$KIT_HOME/profile" 2>/dev/null || echo full)"
  if [[ -f "$KIT_HOME/pre-commit-config.$prof.yaml" ]]; then ok "profile: $prof ($KIT_HOME/pre-commit-config.$prof.yaml)"; else warn "profile '$prof' không có config"; fi
  [[ -x "$KIT_HOME/bin/kit-run" ]] && ok "wrappers: $KIT_HOME/bin" || warn "thiếu $KIT_HOME/bin"
  [[ -d "$KIT_HOME/config" ]] && ok "config mặc định: $KIT_HOME/config ($(ls -A "$KIT_HOME/config" | wc -l | tr -d ' ') file)" || warn "thiếu $KIT_HOME/config"
  local tools=("${MINIMAL_TOOLS[@]}"); [[ "$prof" == "full" ]] && tools=("${FULL_TOOLS[@]}")
  for t in mise "${tools[@]}"; do
    if command -v "$t" >/dev/null 2>&1; then ok "$t: $(command -v "$t")"; else warn "thiếu $t"; fi
  done
  local lp
  lp="$(git config --local --get core.hooksPath 2>/dev/null || true)"
  [[ -n "$lp" ]] && warn "repo hiện tại đặt core.hooksPath=$lp (local) -> ghi đè global; hook của kit KHÔNG chạy ở repo này"
  return 0
}

# -----------------------------------------------------------------------------
uninstall() {
  log "Gỡ precommit-kit global"
  if [[ "$(git config --global --get core.hooksPath || true)" == "$HOOKS_DIR" ]]; then
    git config --global --unset core.hooksPath
    ok "đã bỏ core.hooksPath"
  fi
  rm -rf "$KIT_HOME"
  ok "đã xoá $KIT_HOME"
  echo "Tool (pre-commit, gitleaks, mise) vẫn còn; gỡ bằng: mise uninstall <tool> / brew uninstall mise"
}

# -----------------------------------------------------------------------------
check_prereqs() {
  kit_platform || exit 1
  log "Platform: $KIT_OS/$KIT_ARCH${KIT_LIBC:+ ($KIT_LIBC)}$([[ "$KIT_WSL" == 1 ]] && echo " (WSL)") · package manager: ${KIT_PKG:-?}"
  [[ "$KIT_WSL" == "1" ]] && warn "WSL: repo nên nằm trong filesystem Linux (~/...), không phải /mnt/c — hook trên /mnt/c chậm 5-10x và lỗi quyền thực thi."
  [[ "$KIT_LIBC" == "musl" ]] && warn "Alpine/musl: google-java-format sẽ dùng jar (cần java); một số wheel Python (semgrep) có thể không có bản musl."
  local missing=()
  for c in git curl; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  # pre-commit là Python; mise cài qua pipx nên vẫn cần python3 trên máy
  command -v python3 >/dev/null 2>&1 || missing+=("python3")
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Thiếu: ${missing[*]}. Cài rồi chạy lại:  $(kit_pkg_hint "${missing[@]}")"
  fi
  if [[ "$KIT_OS" == "darwin" ]] && ! xcode-select -p >/dev/null 2>&1; then
    die "macOS: thiếu Command Line Tools (git/python3 của Apple). Chạy: xcode-select --install"
  fi
}

install_mise() {
  if command -v mise >/dev/null 2>&1; then return 0; fi
  log "Cài mise"
  case "$KIT_OS" in
    darwin)
      if command -v brew >/dev/null 2>&1; then brew install mise
      else
        warn "Không có Homebrew — dùng installer chính thức của mise (binary vào ~/.local/bin)"
        local tmp; tmp="$(mktemp)"
        curl -fsSL https://mise.run -o "$tmp"; sh "$tmp"; rm -f "$tmp"
      fi ;;
    linux)
      # installer chính thức: tải về file rồi chạy (không curl|sh), tự chọn binary theo arch/libc
      local tmp; tmp="$(mktemp)"
      curl -fsSL https://mise.run -o "$tmp"
      sh "$tmp"; rm -f "$tmp" ;;
  esac
  add_path
  command -v mise >/dev/null 2>&1 || die "mise chưa vào PATH. Mở shell mới rồi chạy lại."
}

install_tools() {
  local profile="$1"
  if [[ "$profile" == "full" ]]; then
    log "mise: cài toàn bộ tool trong mise.toml ở mức global (~/.config/mise/config.toml)"
    # mise use -g đọc từng dòng tools của mise.toml
    local specs=()
    while IFS= read -r line; do
      [[ "$line" =~ ^\"?([^\"=[:space:]]+)\"?[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]] || continue
      specs+=("${BASH_REMATCH[1]}@${BASH_REMATCH[2]}")
    done < <(sed -n '/^\[tools\]/,/^\[/p' "$KIT_SRC/mise.toml")
    MISE_YES=1 mise use -g "${specs[@]}"
  else
    log "mise: cài ${MINIMAL_TOOLS[*]} ở mức global"
    local specs=()
    for t in "${MINIMAL_TOOLS[@]}"; do
      local v; v="$(tool_version "$t")"
      specs+=("$t@${v:-latest}")
    done
    MISE_YES=1 mise use -g "${specs[@]}"
  fi
  add_path
}

install_hooks() {
  local profile="$1"
  log "Cài dispatcher, wrapper, config mặc định vào $KIT_HOME (profile: $profile)"
  mkdir -p "$HOOKS_DIR" "$KIT_HOME/bin" "$KIT_HOME/config"
  install -m 0755 "$KIT_SRC/global/hooks/dispatch.sh" "$HOOKS_DIR/dispatch.sh"
  for h in "${GIT_HOOKS[@]}"; do
    ln -sfn dispatch.sh "$HOOKS_DIR/$h"
  done

  # profiles
  rm -f "$KIT_HOME/pre-commit-config.yaml"   # bản cũ (trước khi có profile)
  install -m 0644 "$KIT_SRC/global/pre-commit-config.full.yaml"    "$KIT_HOME/pre-commit-config.full.yaml"
  install -m 0644 "$KIT_SRC/global/pre-commit-config.minimal.yaml" "$KIT_HOME/pre-commit-config.minimal.yaml"
  printf '%s\n' "$profile" >"$KIT_HOME/profile"

  # wrappers: kit-run + các script hook của kit (cùng bản với scripts/hooks của repo, đổi tên kit-*)
  install -m 0755 "$KIT_SRC/scripts/hooks/kit-run"         "$KIT_HOME/bin/kit-run"
  install -m 0644 "$KIT_SRC/scripts/hooks/_path.sh"        "$KIT_HOME/bin/_path.sh"
  install -m 0755 "$KIT_SRC/scripts/hooks/trivy-scan.sh"   "$KIT_HOME/bin/kit-trivy-scan"
  install -m 0755 "$KIT_SRC/scripts/hooks/go-mod-tidy.sh"  "$KIT_HOME/bin/kit-go-mod-tidy"
  install -m 0755 "$KIT_SRC/scripts/hooks/tflint.sh"       "$KIT_HOME/bin/kit-tflint"
  install -m 0644 "$KIT_SRC/scripts/hooks/_fetch.sh"       "$KIT_HOME/bin/_fetch.sh"
  install -m 0644 "$KIT_SRC/scripts/hooks/_platform.sh"    "$KIT_HOME/bin/_platform.sh"
  for f in kit-java-format kit-checkstyle kit-dotnet-vuln; do
    install -m 0755 "$KIT_SRC/scripts/hooks/$f" "$KIT_HOME/bin/$f"
  done

  # config mặc định của từng tool
  for f in "${CONFIG_FILES[@]}"; do
    [[ -f "$KIT_SRC/$f" ]] && install -m 0644 "$KIT_SRC/$f" "$KIT_HOME/config/$f"
  done
  rm -rf "$KIT_HOME/config/.semgrep" && cp -R "$KIT_SRC/.semgrep" "$KIT_HOME/config/.semgrep"

  local cur
  cur="$(git config --global --get core.hooksPath || true)"
  if [[ -n "$cur" && "$cur" != "$HOOKS_DIR" ]]; then
    warn "core.hooksPath global đang là '$cur' — sẽ thay bằng $HOOKS_DIR (hook cũ không được chain; copy chúng vào .git/hooks của repo nếu cần)"
  fi
  git config --global core.hooksPath "$HOOKS_DIR"
  ok "git config --global core.hooksPath $HOOKS_DIR"

  # Làm nóng env của profile (cài yamllint/typos/sqlfluff/semgrep... vào cache pre-commit) để commit đầu không chờ
  log "pre-commit: chuẩn bị môi trường cho profile $profile (lần đầu có thể vài phút)"
  local tmp; tmp="$(mktemp -d)"
  ( cd "$tmp" && git init -q && pre-commit install-hooks -c "$KIT_HOME/pre-commit-config.$profile.yaml" >/dev/null ) \
    || warn "chưa chuẩn bị được env (mạng?). Sẽ tự làm ở lần commit đầu."
  rm -rf "$tmp"

  if [[ "$profile" == "full" ]] && command -v trivy >/dev/null 2>&1; then
    log "trivy: tải vuln DB (1 lần, ~70MB)"
    local empty; empty="$(mktemp -d)"
    ( cd "$empty" && trivy fs --scanners vuln --quiet --exit-code 0 --no-progress . >/dev/null 2>&1 ) \
      || warn "trivy DB chưa tải được (mạng?). Sẽ tải ở lần pre-push đầu."
    rm -rf "$empty"
  fi
}

# -----------------------------------------------------------------------------
main() {
  local profile=full use_mise=1
  for a in "$@"; do
    case "$a" in
      --minimal) profile=minimal ;;
      --full) profile=full ;;
      --no-mise) use_mise=0 ;;
      --status) status; exit 0 ;;
      --uninstall) uninstall; exit 0 ;;
      -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
      *) die "tham số lạ: $a" ;;
    esac
  done

  [[ -f "$KIT_SRC/mise.toml" && -f "$KIT_SRC/global/hooks/dispatch.sh" && -f "$KIT_SRC/scripts/hooks/kit-run" ]] || die "chạy từ thư mục precommit-kit"
  check_prereqs
  add_path

  if [[ $use_mise -eq 1 ]]; then
    install_mise
    install_tools "$profile"
  fi
  for t in "${MINIMAL_TOOLS[@]}"; do
    command -v "$t" >/dev/null 2>&1 || die "thiếu '$t' trong PATH (dùng --no-mise thì phải tự cài trước)"
  done
  if [[ "$profile" == "full" ]]; then
    for t in "${FULL_TOOLS[@]}"; do
      command -v "$t" >/dev/null 2>&1 || warn "thiếu '$t' — hook cần nó sẽ báo lỗi khi chạy (cài: mise use -g $t@<version trong mise.toml>)"
    done
  fi
  ok "pre-commit $(pre-commit --version | awk '{print $2}'), gitleaks $(gitleaks version 2>/dev/null | tail -1)"

  install_hooks "$profile"
  echo
  status
  cat <<EOF

Xong. Từ giờ mọi 'git commit' trên máy đều qua dispatcher, 2 tầng, cả hai đều chạy:
  - tầng 1 · global: profile '$profile' của kit — luôn chạy (clone về commit là chạy, không cần file nào trong repo)
  - tầng 2 · repo  : .pre-commit-config.yaml của repo nếu có (hook đặc thù; mẫu: templates/repo/)
  - đổi profile: git config --global precommit-kit.profile full|minimal|off   (hoặc per-repo, bỏ --global)
  - tắt cho 1 repo: git config precommit-kit.disable true
  - repo dùng husky (core.hooksPath local) sẽ ghi đè global: thêm 'pre-commit run' vào .husky/pre-commit nếu muốn.
Shell: thêm  eval "\$(mise activate zsh)"  (hoặc bash) vào rc để dùng tool ngoài hook.
EOF
}

main "$@"

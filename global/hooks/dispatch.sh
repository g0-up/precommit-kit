#!/usr/bin/env bash
# ~/.config/precommit-kit/hooks/dispatch.sh — git hook dispatcher toàn cục.
#
# Được cài qua `git config --global core.hooksPath ~/.config/precommit-kit/hooks`;
# mọi tên hook chuẩn của git đều symlink tới file này. Với mỗi hook, chạy tuần tự:
#   0. Hook cục bộ của repo ($GIT_COMMON_DIR/hooks/<hook>) nếu có — vì core.hooksPath thay thế
#      hoàn toàn .git/hooks, không chain thì hook của husky/lefthook/tự viết bị mất.
#   1. TẦNG 1 — GLOBAL (bắt buộc, security floor): profile của kit
#        ~/.config/precommit-kit/pre-commit-config.<profile>.yaml
#        profile = git config precommit-kit.profile (local > global) > file $KIT_HOME/profile > "full"
#        full: toàn bộ kit | minimal: gitleaks + vệ sinh | off: không chạy (chỉ cho repo cá nhân)
#   2. TẦNG 2 — REPO (bổ sung): .pre-commit-config.yaml của repo nếu có.
#   Tầng 1 fail -> dừng, không chạy tầng 2. Cả hai phải pass thì commit/push mới đi tiếp.
#
#   Repo đã nhúng nguyên kit vào .pre-commit-config.yaml (bản standalone, có dòng
#   "# precommit-kit-standalone") thì tầng 1 tự hạ xuống "minimal" để không chạy trùng 25 hook;
#   gitleaks + vệ sinh vẫn chạy từ global. Đặt PRECOMMIT_KIT_NO_DEDUP=1 nếu muốn chạy đủ cả hai.
#
# Tắt tầng 1 cho 1 repo:  git config precommit-kit.disable true   (hoặc precommit-kit.profile off)
# Tắt cho 1 lần:          PRECOMMIT_KIT_DISABLE=1 git commit ...   (hoặc --no-verify: tắt cả hai tầng)
set -uo pipefail

hook="$(basename "$0")"
kit_dir="${PRECOMMIT_KIT_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/precommit-kit}"
export PRECOMMIT_KIT_HOME="$kit_dir"

# --- PATH cho hook chạy từ GUI (JetBrains/VS Code) ---------------------------
for _p in \
  "$kit_dir/bin" \
  "${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims" \
  "$HOME/.local/bin" "$HOME/go/bin" \
  /opt/homebrew/bin /home/linuxbrew/.linuxbrew/bin /usr/local/bin; do
  [[ -d "$_p" ]] && case ":$PATH:" in *":$_p:"*) ;; *) PATH="$_p:$PATH" ;; esac
done
export PATH

# --- stdin: pre-push / post-rewrite / ... nhận dữ liệu qua stdin, phải phát lại cho từng hook
stdin_file=""
case "$hook" in
  pre-push|post-rewrite|pre-receive|post-receive|update|reference-transaction|proc-receive|sendemail-validate)
    stdin_file="$(mktemp)"
    cat >"$stdin_file"
    ;;
esac
cleanup() { [[ -n "$stdin_file" ]] && rm -f "$stdin_file"; }
trap cleanup EXIT

run_with_stdin() {
  if [[ -n "$stdin_file" ]]; then "$@" <"$stdin_file"; else "$@" </dev/null; fi
}

# --- 1. hook cục bộ của repo --------------------------------------------------
common_dir="$(git rev-parse --git-common-dir 2>/dev/null || echo .git)"
local_hook="$common_dir/hooks/$hook"
if [[ -x "$local_hook" && ! "$local_hook" -ef "$0" ]]; then
  run_with_stdin "$local_hook" "$@"
  rc=$?
  [[ $rc -ne 0 ]] && exit "$rc"
fi

# --- 2. pre-commit framework --------------------------------------------------
case "$hook" in
  pre-commit|commit-msg|pre-push) ;;
  *) exit 0 ;;
esac

if ! command -v pre-commit >/dev/null 2>&1; then
  echo "precommit-kit: không tìm thấy 'pre-commit' trong PATH — chạy lại install.sh. Bỏ qua hook $hook." >&2
  exit 0
fi

toplevel="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
repo_cfg="$toplevel/.pre-commit-config.yaml"

# hook-impl là entry mà script do `pre-commit install` sinh ra cũng gọi; nhận nguyên
# tham số/stdin của git nên hành vi giống hệt cài per-repo.
run_level() {
  local label="$1" cfg="$2"; shift 2
  echo "precommit-kit ▶ $label" >&2
  run_with_stdin pre-commit hook-impl \
    --config "$cfg" \
    --hook-type "$hook" \
    --hook-dir "$common_dir/hooks" \
    --skip-on-missing-config \
    -- "$@"
}

# --- TẦNG 1: global ------------------------------------------------------------
level1_skip=0
[[ "${PRECOMMIT_KIT_DISABLE:-0}" == "1" ]] && level1_skip=1
[[ "$(git config --get precommit-kit.disable 2>/dev/null)" == "true" ]] && level1_skip=1

if [[ $level1_skip -eq 0 ]]; then
  profile="$(git config --get precommit-kit.profile 2>/dev/null || true)"
  [[ -z "$profile" && -f "$kit_dir/profile" ]] && profile="$(tr -d '[:space:]' <"$kit_dir/profile")"
  profile="${profile:-full}"
  if [[ "$profile" == "full" && "${PRECOMMIT_KIT_NO_DEDUP:-0}" != "1" && -f "$repo_cfg" ]] \
     && grep -q '^# *precommit-kit-standalone' "$repo_cfg"; then
    profile=minimal   # repo đã nhúng nguyên kit -> global chỉ giữ security floor
  fi
  if [[ "$profile" != "off" ]]; then
    cfg="$kit_dir/pre-commit-config.$profile.yaml"
    if [[ -f "$cfg" ]]; then
      run_level "tầng 1 · global ($profile)" "$cfg" "$@"
      rc=$?
      [[ $rc -ne 0 ]] && exit "$rc"
    else
      echo "precommit-kit: profile '$profile' không có ($cfg) -> bỏ qua tầng 1" >&2
    fi
  fi
fi

# --- TẦNG 2: repo --------------------------------------------------------------
if [[ -f "$repo_cfg" ]]; then
  run_level "tầng 2 · repo (.pre-commit-config.yaml)" "$repo_cfg" "$@"
  exit $?
fi
exit 0

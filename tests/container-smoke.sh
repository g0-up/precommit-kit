#!/usr/bin/env bash
# tests/container-smoke.sh — smoke test precommit-kit BÊN TRONG một container/máy sạch.
#
# Giả định: git, curl, python3, pre-commit, gitleaks, golangci-lint, go đã có trong PATH
# (tests/run-matrix.sh lo phần cài). Không cần mạng ngoài trừ PyPI/GitHub cho env của pre-commit.
# Kết quả: in bảng PASS/FAIL, exit 1 nếu có FAIL. Có thể chạy trực tiếp trên máy dev để tự kiểm tra.
set -uo pipefail
KIT="${KIT_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
results=()
pass() { results+=("PASS  $1"); }
fail() { results+=("FAIL  $1 — ${2:-}"); }
section() { printf '\n\033[1;34m## %s\033[0m\n' "$*"; }

export HOME="${HOME:-/root}"
git config --global user.email kit@test >/dev/null 2>&1 || true
git config --global user.name kit >/dev/null 2>&1 || true
git config --global init.defaultBranch main

# --- 1. platform ---------------------------------------------------------------
section "1. platform detection"
# shellcheck source=../scripts/hooks/_platform.sh
source "$KIT/scripts/hooks/_platform.sh"
if kit_platform; then
  pass "kit_platform: os=$KIT_OS arch=$KIT_ARCH libc=$KIT_LIBC pkg=$KIT_PKG wsl=$KIT_WSL"
else
  fail "kit_platform" "không nhận diện được"
fi
hint="$(kit_pkg_hint git curl python3)"
case "$hint" in *apt-get*|*dnf*|*apk*|*pacman*|*zypper*|*yum*|*brew*) pass "kit_pkg_hint: $hint" ;; *) fail "kit_pkg_hint" "$hint" ;; esac

# --- 2. prerequisite messaging (PATH thiếu curl) --------------------------------
section "2. install.sh báo thiếu prerequisite đúng cách"
tmpbin="$(mktemp -d)"
for c in git python3 bash sh uname grep awk sed mktemp ls cat tr head tail dirname basename readlink id env xargs wc sort install ln rm mkdir cp mv chmod printf apt-get dnf yum apk pacman zypper brew; do
  p="$(command -v "$c" 2>/dev/null || true)"; [[ -n "$p" ]] && ln -sf "$p" "$tmpbin/$c"
done
out="$(PATH="$tmpbin" "$KIT/install.sh" --no-mise 2>&1 || true)"
if grep -q 'Thiếu: curl' <<<"$out" && grep -qE 'apt-get|dnf|apk|pacman|zypper|yum|brew' <<<"$out"; then
  pass "thiếu curl -> '$(grep -o 'Thiếu.*' <<<"$out" | head -1)'"
else
  fail "prereq message" "$(tail -2 <<<"$out" | tr '\n' ' ')"
fi
rm -rf "$tmpbin"

# --- 3. install.sh --no-mise ----------------------------------------------------
section "3. install.sh --no-mise"
out="$("$KIT/install.sh" --no-mise 2>&1)"; rc=$?
if [[ $rc -eq 0 && "$(git config --global --get core.hooksPath)" == "$HOME/.config/precommit-kit/hooks" ]]; then
  pass "install.sh: core.hooksPath=$(git config --global --get core.hooksPath)"
else
  fail "install.sh" "rc=$rc $(tail -3 <<<"$out" | tr '\n' ' ')"
fi
[[ -x "$HOME/.config/precommit-kit/bin/kit-run" ]] && pass "bin/kit-run cài" || fail "bin/kit-run" "thiếu"
n="$(ls -A "$HOME/.config/precommit-kit/config" 2>/dev/null | wc -l | tr -d ' ')"
[[ "$n" -eq 11 ]] && pass "config mặc định: $n file (10 file + .semgrep/)" || fail "config mặc định" "$n file, mong đợi 11"
"$KIT/install.sh" --status >/dev/null 2>&1 && pass "install.sh --status" || fail "install.sh --status" ""
export PATH="$HOME/.config/precommit-kit/bin:$PATH"   # chạy pre-commit tay (ngoài dispatcher) cần bin/ trong PATH

# --- 4. end-to-end: repo sạch, không có file kit ------------------------------------
section "4. clone sạch -> commit (tầng 1 global)"
work="$(mktemp -d)"; cd "$work" && git init -q && git checkout -q -b dev
printf 'module example.com/app\n\ngo 1.24\n' > go.mod
printf 'package main\n\nfunc main() {}\n' > main.go
git add -A && git commit -q -m "chore: init" --no-verify

# 4a secret bị chặn
python3 - <<'EOF'
import random,string
r=''.join(random.choices(string.ascii_letters+string.digits,k=36))
open('cfg.txt','w').write('token = "ghp_'+r+'"\n')
EOF
git add -A
out="$(SKIP=trivy-misconfig,hadolint git commit -q -m "feat: secret" 2>&1 || true)"
if grep -q 'tầng 1' <<<"$out" && grep -qE 'gitleaks.*Failed' <<<"$out" && [[ "$(git log --oneline | wc -l | tr -d ' ')" == "1" ]]; then
  pass "gitleaks chặn secret (global, repo không có config)"
else
  fail "gitleaks" "$(grep -E 'gitleaks|tầng|Error|error' <<<"$out" | head -3 | tr '\n' ' ')"
fi
git rm -q --cached cfg.txt && rm -f cfg.txt

# 4b golangci-lint (config mặc định của kit) chặn errcheck
printf 'package main\n\nimport "net/http"\n\nfunc fetch() {\n\thttp.Get("http://x")\n}\n' > fetch.go
git add -A
out="$(SKIP=trivy-misconfig,hadolint git commit -q -m "feat: fetch" 2>&1 || true)"
if grep -q 'errcheck' <<<"$out"; then
  pass "golangci-lint chặn errcheck (config mặc định kit)"
else
  fail "golangci-lint" "$(grep -E 'golangci|error|Error' <<<"$out" | head -3 | tr '\n' ' ')"
fi
printf 'package main\n\nimport "net/http"\n\nfunc fetch() error {\n\tresp, err := http.Get("http://x")\n\tif err != nil {\n\t\treturn err\n\t}\n\treturn resp.Body.Close()\n}\n' > fetch.go
gofmt -w fetch.go 2>/dev/null || true
git add -A

# 4c commit-msg sai format bị chặn
out="$(SKIP=trivy-misconfig,hadolint,golangci-lint git commit -q -m "bad message" 2>&1 || true)"
grep -q 'Conventional Commit.*Failed' <<<"$out" && pass "conventional commit chặn message sai" || fail "conventional commit" "$(tail -2 <<<"$out" | tr '\n' ' ')"

# 4d commit sạch đi qua
out="$(SKIP=trivy-misconfig,hadolint,golangci-lint git commit -q -m "feat: fetch" 2>&1 || true)"
if [[ "$(git log --oneline | wc -l | tr -d ' ')" == "2" ]]; then
  pass "commit sạch đi qua cả pre-commit + commit-msg"
else
  fail "commit sạch" "$(grep -E 'Failed' <<<"$out" | head -3 | tr '\n' ' ')"
fi

# 4e hook Python do pre-commit tự quản lý env (yamllint, typos, ruff) — quan trọng với musl
printf 'key: value\n' > ok.yaml
printf 'import os\n\ndef f(x):\n    return x\n' > app.py
git add -A
out="$(pre-commit run -c "$HOME/.config/precommit-kit/pre-commit-config.full.yaml" yamllint --all-files 2>&1 || true)"
grep -qE 'yamllint.*Passed' <<<"$out" && pass "yamllint (env Python của pre-commit)" || fail "yamllint" "$(tail -2 <<<"$out" | tr '\n' ' ')"
out="$(pre-commit run -c "$HOME/.config/precommit-kit/pre-commit-config.full.yaml" typos --all-files 2>&1 || true)"
grep -qE 'typos.*(Passed|Failed)' <<<"$out" && ! grep -q 'unexpected error' <<<"$out" && pass "typos (wheel Rust)" || fail "typos" "$(tail -2 <<<"$out" | tr '\n' ' ')"
printf '# Title\n\nsome   text\n' > doc.md; git add doc.md
out="$(pre-commit run -c "$HOME/.config/precommit-kit/pre-commit-config.full.yaml" rumdl-check --all-files 2>&1 || true)"
grep -qE 'rumdl.*(Passed|Failed)' <<<"$out" && ! grep -q 'unexpected error' <<<"$out" && pass "rumdl markdown (wheel Rust, không cần Node)" || fail "rumdl" "$(tail -2 <<<"$out" | tr '\n' ' ')"
out="$(pre-commit run -c "$HOME/.config/precommit-kit/pre-commit-config.full.yaml" ruff-check --all-files 2>&1 || true)"
grep -qE 'F401|ruff check.*(Passed|Failed)' <<<"$out" && pass "ruff (wheel Rust): $(grep -oE 'F401[^\n]*' <<<"$out" | head -1)" || fail "ruff" "$(tail -2 <<<"$out" | tr '\n' ' ')"

# 4f tầng 2 (repo config) chạy sau tầng 1
cp "$KIT/templates/repo/.pre-commit-config.yaml" .
printf 'X=1\n' > .env
git add -A
out="$(SKIP=trivy-misconfig,hadolint,golangci-lint,typos,ruff-check,ruff-format,yamllint git commit -q -m "feat: env" 2>&1 || true)"
if grep -q 'tầng 2' <<<"$out" && grep -q 'forbid .env' <<<"$out"; then
  pass "tầng 2 chạy sau tầng 1 và chặn .env"
else
  fail "tầng 2" "$(grep -E 'tầng|forbid|Failed' <<<"$out" | head -3 | tr '\n' ' ')"
fi

# 4g gỡ cài
"$KIT/install.sh" --uninstall >/dev/null 2>&1 && [[ -z "$(git config --global --get core.hooksPath || true)" ]] && pass "install.sh --uninstall sạch" || fail "uninstall" ""

# --- report -----------------------------------------------------------------------
section "KẾT QUẢ ($(grep PRETTY /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"'); bash $BASH_VERSION)"
printf '%s\n' "${results[@]}"
grep -q '^FAIL' <<<"$(printf '%s\n' "${results[@]}")" && exit 1 || exit 0

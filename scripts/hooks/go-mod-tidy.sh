#!/usr/bin/env bash
# scripts/hooks/go-mod-tidy.sh
# Chạy `go mod tidy` cho MỌI module trong repo (hỗ trợ monorepo nhiều go.mod)
# và fail nếu go.mod/go.sum thay đổi -> dev phải `git add` lại.
# Bash 3.2 compatible (macOS).
set -euo pipefail
# shellcheck source=scripts/hooks/_path.sh
source "$(dirname "${BASH_SOURCE[0]}")/_path.sh"
# shellcheck source=scripts/hooks/_platform.sh
source "$(dirname "${BASH_SOURCE[0]}")/_platform.sh"

if ! command -v go >/dev/null 2>&1; then
  echo "go: không tìm thấy toolchain" >&2
  exit 1
fi

status=0
# -print0/-0 có ở cả BSD find (macOS) và GNU find
while IFS= read -r -d '' modfile; do
  dir="$(dirname "$modfile")"
  case "$dir" in
    */vendor|*/vendor/*|*/node_modules|*/node_modules/*|*/testdata|*/testdata/*) continue ;;
  esac
  before="$(cd "$dir" && { cat go.mod go.sum 2>/dev/null || true; } | { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi; })"
  (cd "$dir" && go mod tidy)
  after="$(cd "$dir" && { cat go.mod go.sum 2>/dev/null || true; } | { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi; })"
  if [[ "$before" != "$after" ]]; then
    echo "go mod tidy đã sửa $dir/go.mod hoặc go.sum — hãy git add lại." >&2
    status=1
  fi
done < <(find . -name go.mod -not -path './.git/*' -print0)

exit "$status"

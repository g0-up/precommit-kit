#!/usr/bin/env bash
# tests/run-matrix.sh — chạy tests/container-smoke.sh trên nhiều distro bằng Docker (máy có Docker + mạng).
#
#   tests/run-matrix.sh                      # ubuntu:24.04 debian:12 fedora:43 alpine:3.21 archlinux
#   tests/run-matrix.sh ubuntu:22.04         # chỉ 1 image
#   FULL=1 tests/run-matrix.sh               # cài qua mise đầy đủ (install.sh không --no-mise), chậm hơn, cần mạng tới GitHub/Adoptium/nodejs.org
#
# Mỗi image: cài prerequisite bằng package manager của distro -> install.sh -> smoke test. In bảng tổng kết.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
images=("$@"); [[ ${#images[@]} -eq 0 ]] && images=(ubuntu:24.04 debian:12 fedora:43 alpine:3.21 archlinux:latest)
FULL="${FULL:-0}"

# Cài prerequisite + toolchain tối thiểu để smoke test chạy được khi FULL=0 (không qua mise)
provision='
set -e
if command -v apk >/dev/null; then apk add -q bash git curl python3 py3-pip go shellcheck
elif command -v apt-get >/dev/null; then export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq git curl python3 python3-pip python3-venv golang-go shellcheck >/dev/null
elif command -v dnf >/dev/null; then dnf install -y -q git curl python3 python3-pip golang ShellCheck >/dev/null
elif command -v pacman >/dev/null; then pacman -Sy --noconfirm --needed git curl python python-pip go shellcheck >/dev/null
fi
python3 -m venv /opt/venv && /opt/venv/bin/pip install -q pre-commit
export PATH=/opt/venv/bin:/root/go/bin:$PATH
# binary Go tĩnh từ GitHub releases (version theo mise.toml của kit)
ver() { sed -n -E "s/^\"?$1\"? *= *\"([^\"]+)\".*/\1/p" /kit/mise.toml | head -1; }
A=$(uname -m); [ "$A" = x86_64 ] && GA=x64 && GL=amd64 || { GA=arm64; GL=arm64; }
curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v$(ver gitleaks)/gitleaks_$(ver gitleaks)_linux_$GA.tar.gz" | tar -xz -C /usr/local/bin gitleaks
curl -fsSL "https://github.com/golangci/golangci-lint/releases/download/v$(ver golangci-lint)/golangci-lint-$(ver golangci-lint)-linux-$GL.tar.gz" | tar -xz --strip-components=1 -C /usr/local/bin "golangci-lint-$(ver golangci-lint)-linux-$GL/golangci-lint"
'

summary=()
for img in "${images[@]}"; do
  echo; echo "=================== $img"
  if [[ "$FULL" == "1" ]]; then
    cmd='bash -c "$0" && cd /kit && ./install.sh && export PATH=$HOME/.local/share/mise/shims:$PATH && bash tests/container-smoke.sh'
  else
    cmd='bash -c "$0" && export PATH=/opt/venv/bin:$PATH && bash /kit/tests/container-smoke.sh'
  fi
  if docker run --rm -v "$KIT:/kit:ro" -e HOME=/root "$img" sh -c "$cmd" "$provision"; then
    summary+=("PASS  $img")
  else
    summary+=("FAIL  $img")
  fi
done
echo; echo "=================== TỔNG KẾT"; printf '%s\n' "${summary[@]}"
grep -q '^FAIL' <<<"$(printf '%s\n' "${summary[@]}")" && exit 1 || exit 0

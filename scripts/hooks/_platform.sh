# scripts/hooks/_platform.sh — nhận diện OS / arch / libc / package manager. Source từ install.sh, bootstrap.sh, hook.
# Export: KIT_OS (darwin|linux), KIT_ARCH (x86_64|arm64), KIT_LIBC (glibc|musl|""), KIT_PKG (brew|apt|dnf|yum|apk|pacman|zypper|"")
# shellcheck shell=bash
kit_platform() {
  local s m
  s="$(uname -s)"; m="$(uname -m)"
  case "$s" in
    Darwin) KIT_OS=darwin ;;
    Linux)  KIT_OS=linux ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "precommit-kit: không hỗ trợ Windows native (Git Bash/MSYS). Dùng WSL2 (Ubuntu) rồi cài trong đó." >&2
      return 1 ;;
    *) echo "precommit-kit: OS không hỗ trợ: $s" >&2; return 1 ;;
  esac
  case "$m" in
    x86_64|amd64)  KIT_ARCH=x86_64 ;;
    arm64|aarch64) KIT_ARCH=arm64 ;;
    *) echo "precommit-kit: kiến trúc không hỗ trợ: $m" >&2; return 1 ;;
  esac
  KIT_LIBC=""
  if [[ "$KIT_OS" == "linux" ]]; then
    if [[ -f /etc/alpine-release ]] || ldd --version 2>&1 | grep -qi musl; then KIT_LIBC=musl; else KIT_LIBC=glibc; fi
  fi
  KIT_PKG=""
  if   command -v brew   >/dev/null 2>&1; then KIT_PKG=brew
  elif command -v apt-get >/dev/null 2>&1; then KIT_PKG=apt
  elif command -v dnf    >/dev/null 2>&1; then KIT_PKG=dnf
  elif command -v yum    >/dev/null 2>&1; then KIT_PKG=yum
  elif command -v apk    >/dev/null 2>&1; then KIT_PKG=apk
  elif command -v pacman >/dev/null 2>&1; then KIT_PKG=pacman
  elif command -v zypper >/dev/null 2>&1; then KIT_PKG=zypper
  fi
  # WSL: coi là linux, chỉ để báo
  KIT_WSL=0; grep -qi microsoft /proc/version 2>/dev/null && KIT_WSL=1
  export KIT_OS KIT_ARCH KIT_LIBC KIT_PKG KIT_WSL
}

# kit_pkg_hint <pkg...>: in lệnh cài gói hệ thống theo package manager
kit_pkg_hint() {
  case "${KIT_PKG:-}" in
    brew)   echo "brew install $*" ;;
    apt)    echo "sudo apt-get update && sudo apt-get install -y $*" ;;
    dnf)    echo "sudo dnf install -y $*" ;;
    yum)    echo "sudo yum install -y $*" ;;
    apk)    echo "sudo apk add $*" ;;
    pacman) echo "sudo pacman -S --needed $*" ;;
    zypper) echo "sudo zypper install -y $*" ;;
    *)      echo "(cài bằng package manager của hệ: $*)" ;;
  esac
}

# kit_sha256 <file>: shasum (mac, hầu hết linux) hoặc sha256sum (alpine/busybox)
kit_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else echo "precommit-kit: không có shasum/sha256sum" >&2; return 1; fi
}

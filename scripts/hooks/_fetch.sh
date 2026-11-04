# scripts/hooks/_fetch.sh — source từ hook cần tải binary/jar pin version về cache (1 lần / máy).
# kit_fetch <tên-file-cache> <url> [sha256]  -> in đường dẫn file đã có trong cache
# Cache: $PRECOMMIT_KIT_CACHE > $XDG_CACHE_HOME/precommit-kit > ~/.cache/precommit-kit
# shellcheck shell=bash
# shellcheck source=scripts/hooks/_platform.sh
source "$(dirname "${BASH_SOURCE[0]}")/_platform.sh"
kit_fetch() {
  local name="$1" url="$2" sha="${3:-}"
  local dir="${PRECOMMIT_KIT_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/precommit-kit}"
  local dst="$dir/$name"
  if [[ ! -s "$dst" ]]; then
    mkdir -p "$dir"
    echo "precommit-kit: tải $name (1 lần) từ $url" >&2
    if ! curl -fsSL --retry 2 -o "$dst.part" "$url"; then
      rm -f "$dst.part"
      echo "precommit-kit: không tải được $url (mạng chặn github.com?). Tải tay rồi đặt vào $dst" >&2
      return 1
    fi
    if [[ -n "$sha" ]]; then
      local got
      got="$(kit_sha256 "$dst.part")"
      if [[ "$got" != "$sha" ]]; then
        rm -f "$dst.part"
        echo "precommit-kit: sha256 của $name không khớp (got $got, want $sha)" >&2
        return 1
      fi
    fi
    mv "$dst.part" "$dst"
    chmod +x "$dst"
  fi
  printf '%s\n' "$dst"
}

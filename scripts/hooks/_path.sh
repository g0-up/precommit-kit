# scripts/hooks/_path.sh — source từ các hook script.
# Git hook chạy từ GUI (JetBrains, VS Code, GitHub Desktop) có PATH rất tối giản
# trên macOS -> không thấy mise shims / homebrew. Prepend các vị trí phổ biến.
# shellcheck shell=bash
for _p in \
  "${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims" \
  "$HOME/.local/bin" \
  "$HOME/go/bin" \
  /opt/homebrew/bin \
  /home/linuxbrew/.linuxbrew/bin \
  /usr/local/bin; do
  if [[ -d "$_p" ]]; then
    case ":$PATH:" in
      *":$_p:"*) ;;
      *) PATH="$_p:$PATH" ;;
    esac
  fi
done
unset _p
export PATH

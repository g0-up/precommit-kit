#!/usr/bin/env bash
# scripts/hooks/tflint.sh — chạy tflint trên mọi module Terraform trong repo.
# `tflint --init` tải plugin khai báo trong .tflint.hcl (1 lần, cần mạng); sau đó offline.
set -euo pipefail
# shellcheck source=scripts/hooks/_path.sh
source "$(dirname "${BASH_SOURCE[0]}")/_path.sh"

if ! command -v tflint >/dev/null 2>&1; then
  echo "tflint: không tìm thấy binary. Chạy ./scripts/bootstrap.sh (hoặc: mise install)" >&2
  exit 1
fi

# Config: .tflint.hcl của repo, không có thì mặc định của kit (global mode)
kit_home="${PRECOMMIT_KIT_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/precommit-kit}"
cfg_args=()
cfg_file=".tflint.hcl"
if [[ ! -f "$cfg_file" && -f "$kit_home/config/.tflint.hcl" ]]; then
  cfg_file="$kit_home/config/.tflint.hcl"
  cfg_args=(--config "$cfg_file")
fi

plugin_dir="${TFLINT_PLUGIN_DIR:-$HOME/.tflint.d/plugins}"
if [[ -f "$cfg_file" ]] && grep -Eq '^\s*source\s*=' "$cfg_file" && [[ ! -d "$plugin_dir" || -z "$(ls -A "$plugin_dir" 2>/dev/null)" ]]; then
  echo "tflint: tải plugin (1 lần)..." >&2
  tflint --init "${cfg_args[@]+"${cfg_args[@]}"}"
fi

# --recursive: mọi thư mục có *.tf ; --minimum-failure-severity: warning trở lên mới fail
exec tflint --recursive --minimum-failure-severity=warning --format compact "${cfg_args[@]+"${cfg_args[@]}"}"

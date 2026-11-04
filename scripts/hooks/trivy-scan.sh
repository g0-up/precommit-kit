#!/usr/bin/env bash
# scripts/hooks/trivy-scan.sh <misconfig|vuln>
#
# Wrapper cho trivy để hook pre-commit/pre-push ổn định trên macOS + Linux:
#   - misconfig : quét Dockerfile / compose / k8s / terraform. Không cần vuln DB -> nhanh.
#   - vuln      : quét go.sum, package-lock, pnpm-lock... Cần DB (~70MB lần đầu).
#   - secret scanner của trivy TẮT (gitleaks đảm nhiệm).
#   - Chỉ fail với HIGH/CRITICAL đã có fix. Override: TRIVY_SEVERITY=MEDIUM,HIGH,CRITICAL
#   - Offline / mạng chậm: TRIVY_OFFLINE=1 -> dùng DB + checks bundle đang cache.
#
# Bash 3.2 compatible (macOS mặc định), không dùng GNU-only flag.
set -euo pipefail
# shellcheck source=scripts/hooks/_path.sh
source "$(dirname "${BASH_SOURCE[0]}")/_path.sh"

mode="${1:-}"
severity="${TRIVY_SEVERITY:-HIGH,CRITICAL}"
timeout="${TRIVY_TIMEOUT:-5m}"

if ! command -v trivy >/dev/null 2>&1; then
  echo "trivy: không tìm thấy binary. Chạy ./scripts/bootstrap.sh (hoặc: mise install)" >&2
  exit 1
fi

common=(
  fs
  --exit-code 1
  --severity "$severity"
  --timeout "$timeout"
  --skip-dirs "node_modules,vendor,dist,build,.git"
  --no-progress
  --format table
)

# .trivyignore ở root repo (nếu có) để whitelist CVE/misconfig ID có lý do
if [[ -f .trivyignore ]]; then
  common+=(--ignorefile .trivyignore)
fi
if [[ "${TRIVY_OFFLINE:-0}" == "1" ]]; then
  common+=(--skip-db-update --skip-check-update --offline-scan)
fi

case "$mode" in
  misconfig)
    # Không cần vuln DB, nhưng cần checks bundle (nhỏ). --skip-db-update bỏ qua vuln DB.
    # misconfig không cần vuln DB; checks bundle nhỏ, nếu tải lỗi trivy tự fallback về bản nhúng.
    exec trivy "${common[@]}" \
      --scanners misconfig \
      --skip-db-update \
      .
    ;;
  vuln)
    exec trivy "${common[@]}" \
      --scanners vuln \
      --ignore-unfixed \
      --skip-check-update \
      .
    ;;
  *)
    echo "usage: $0 <misconfig|vuln>" >&2
    exit 2
    ;;
esac

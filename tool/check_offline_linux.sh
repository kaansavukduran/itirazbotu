#!/usr/bin/env bash
# Release uygulamasını temiz veri dizini ve kapalı ağ alanıyla başlatır.
# Arayüzde ilk açılış, üç örnek, GGUF aktarımı ve üretimi elle sınayın; sonra kapatın.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=${1:-build/linux/x64/release/bundle/itiraz_botu}
[[ "$APP" = /* ]] || APP="$PWD/$APP"
[[ -x "$APP" ]] || { echo 'Önce: flutter build linux --release'; exit 1; }
for cmd in unshare strace; do
  command -v "$cmd" >/dev/null || { echo "Eksik araç: $cmd"; exit 1; }
done
RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/itiraz-offline.XXXXXX")
mkdir -p "$RUN_DIR/data" "$RUN_DIR/config"
echo "Temiz veri ve ağ izi: $RUN_DIR"
unshare -Urn sh -c '
  cat /proc/net/dev > "$1/interfaces.txt"
  exec env XDG_DATA_HOME="$1/data" XDG_CONFIG_HOME="$1/config" \
    strace -f -e trace=network -o "$1/network.log" "$2"
' sh "$RUN_DIR" "$APP"
if grep -Eq 'AF_INET6?' "$RUN_DIR/network.log"; then
  echo 'IPv4/IPv6 ağ işlemi görüldü. network.log dosyasını inceleyin.'
  exit 1
fi
echo 'IPv4/IPv6 ağ işlemi görülmedi. Arayüz ve model adımlarını ayrıca kaydedin.'

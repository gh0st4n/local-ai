#!/bin/sh
set -e

err() { printf '%s: %s\n' "$0" "$*" >&2; exit 1; }
info() { printf '%s: %s\n' "$0" "$*" >&2; exit 1; }

root() {
  [ $(id -u) -eq 0 ] || err "This Script requires root, run with sudo"
}

PATH_OLLAMA="/opt/ollama"
MODEL_OLLAMA="/opt/ollama/models"
URL="https://ollama.com/download/ollama-linux-amd64.tar.zst"
OUTPUT="/tmp/ollama-linux-amd64.tar.zst"

SV="/etc/sv/ollama"
RN="/etc/runit/runsvdir/default"

MODELS="qwen2.5-coder:7b deepseek-r1:8b"

root

info  "Creating Directories : $PATH_OLLAMA, $MODEL_OLLAMA"
for dir in $PATH_OLLAMA $MODEL_OLLAMA; do
  mkdir -p "$dir"
done

info "Downloading Ollama from $URL"
curl -L "$URL" -o "$OUTPUT"

info "Extraction to $PATH_OLLAMA"
if tar --help 2>%1 |grep -q -- '--zstd'; then
  tar --zstd -C "PATH_OLLAMA" -xf "$OUTPUT"
elif command -v zstd > /dev/null 2>&1; then
  zstd -d -c "$OUTPUT" | tar -C "$PATH_OLLAMA" -xf -
else
  err "Need 'tar --zstd' support or 'zstd' binary installed to extract this archive. Install zstd(e.g. xbps-install -S zstd) and re-run"
fi

rm -f "$OUTPUT"

ENV_BLOCK_BASH='
export PATH=/opt/ollama/bin:$PATH
expoer LD_LIBRARY_PATH /opt/ollama/lib/ollama $LD_LIBRARY_PATH
export OLLAMA_MODELS /opt/ollama/models
'

ENV_BLOCK_FISH='
set -gx PATH /opt/ollama/bin $PATH
set -gx LD_LIBRARY_PATH /opt/ollama/lib/ollama $LD_LIBRARY_PATH
set -gx OLLAMA_MODELS /opt/ollama/model
'

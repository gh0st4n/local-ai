#!/bin/sh
# Install Ollama to Root Patition(/opt/ollama), & setup Runit Service

set -e

err() { printf '%s: %s\n' "$0" "$*" >&2; exit 1; }
info() { printf '%s: %s\n' "$0" "$*" >&2; }

root() {
  [ $(id -u) -eq 0 ] || err "This Script requires root, run with sudo"
}

PATH_OLLAMA="/opt/ollama"
MODEL_OLLAMA="/opt/ollama/models"
URL="https://ollama.com/download/ollama-linux-amd64.tar.zst"
OUTPUT="/tmp/ollama-linux-amd64.tar.zst"

SV="/etc/sv/ollama"
RN="/etc/runit/runsvdir/default"

MODELS="qwen2.5-coder:7b qwen2.5-coder:3b qwen3:8b qwen3:4b"

root

info  "Creating Directories : $PATH_OLLAMA, $MODEL_OLLAMA"
for dir in $PATH_OLLAMA $MODEL_OLLAMA; do
  mkdir -p "$dir"
done

info "Downloading Ollama from $URL"
curl -L "$URL" -o "$OUTPUT"

info "Extraction to $PATH_OLLAMA"
if tar --help 2>&1 |grep -q -- '--zstd'; then
  tar --zstd -C "$PATH_OLLAMA" -xf "$OUTPUT"
elif command -v zstd > /dev/null 2>&1; then
  zstd -d -c "$OUTPUT" | tar -C "$PATH_OLLAMA" -xf -
else
  err "Need 'tar --zstd' support or 'zstd' binary installed to extract this archive. Install zstd(e.g. xbps-install -S zstd) and re-run"
fi

rm -f "$OUTPUT"

ENV_BLOCK_BASH='
export PATH=/opt/ollama/bin:$PATH
export LD_LIBRARY_PATH=/opt/ollama/lib/ollama:$LD_LIBRARY_PATH
export OLLAMA_MODELS=/opt/ollama/models
'

ENV_BLOCK_FISH='
set -gx PATH /opt/ollama/bin $PATH
set -gx LD_LIBRARY_PATH /opt/ollama/lib/ollama $LD_LIBRARY_PATH
set -gx OLLAMA_MODELS /opt/ollama/models
'

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

append_once() {
  file="$1"; marker="$2"; block="$3"
  [ -f "$file" ] || touch "$file"
  if grep -q "$marker" "$file" 2>/dev/null; then
    info "Env already present in $file, skipping"
  else
    printf '\n# %s\n%s\n' "$marker" "$block" >> "$file"
    info "Appended ollama env to $file"
  fi
}

if [ -n "$REAL_HOME" ]; then
  [ -f "$REAL_HOME/.bashrc" ] && append_once "$REAL_HOME/.bashrc" "ollama-env" "$ENV_BLOCK_BASH"
  [ -f "$REAL_HOME/.zshrc" ] && append_once "$REAL_HOME/.zshrc" "ollama-env" "$ENV_BLOCK_BASH"
  if [ -d "$REAL_HOME/.config/fish" ]; then
    mkdir -p "$REAL_HOME/.config/fish"
    append_once "$REAL_HOME/.config/fish/config.fish" "ollama-env" "$ENV_BLOCK_FISH"
  fi
  chown -R "$REAL_USER" "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc" 2>/dev/null || true
else
  info "Could not resolve home directory from $REAL_USER, skipping shell rc setup"
fi

info "Setting up runit service at $SV"
mkdir -p "$SV"
cat > "$SV/run" << 'EOF'
#!/bin/sh
export HOME=/root
export PATH=/opt/ollama/bin:$PATH
export LD_LIBRARY_PATH=/opt/ollama/lib/ollama:$LD_LIBRARY_PATH
export OLLAMA_MODELS=/opt/ollama/models
exec /opt/ollama/bin/ollama serve
EOF
chmod +x "$SV/run"

if [ -L "$RN/ollama" ] || [ -e "$RN/ollama" ]; then
  info "Service already linked at $RN/ollama, skipping"
else
  ln -s "$SV" "$RN/ollama"
  info "Linked $SV -> $RN/ollama"
fi

info "Waiting for runsvdir to pick up the new service (polling, no global signal)"

tries=0
while [ ! -e "$RN/ollama/supervise/ok" ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 15 ]; then
    info "runsvdir still hasn't picked up the service after 15s, trying anyway"
    break
  fi
  sleep 1
done

info "Starting Ollama service via runit"
sv start ollama > /dev/null 2>&1 || true

info "Waiting for Ollama service to come up..."
tries=0
until curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:11434 2>/dev/null | grep -q '^200$'; do
  if [ "$tries" -ge 30 ]; then
    err "Ollama service did not become ready in time. Check 'sudo sv status ollama' and 'sudo sh /etc/sv/ollama/run' manually."
  fi
  sleep 1
done
info "Ollama service is up (http://127.0.0.1:11434)"

info "Giving DNS/Network a moment to settle before pulling models"
sleep 5

info "Pulling Models: $MODELS"
for model in $MODELS; do
  info "Pulling $model (this can take a while depending on model size and connection)"
  pull_tries=0
  until /opt/ollama/bin/ollama pull "$model"; do
    pull_tries=$((pull_tries + 1))
    if [ "$pull_tries" -ge 3 ]; then
      err "Failed to pull $model after 3 attempts. Check your internet connection and run manually: 'ollama pull $model'"
    fi
    info "Pull failed, retrying in 10s ($pull_tries/3)..."
    sleep 10
  done
done

if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
  info "Fixing ownership of $PATH_OLLAMA to $REAL_USER"
  chown -R "$REAL_USER" "$PATH_OLLAMA"
fi

shell() {
  if [ -f "$HOME/.bashrc" ]; then
    echo "~/.bashrc"
  fi

  if [ -f "$HOME/.zshrc" ]; then
    echo "~/.zshrc"
  fi

  if [ -f "$HOME/.config/fish/config.fish" ]; then
    echo "~/.config/fish/config.fish"
  fi
}
check=$(shell)

info "Done"
info "Binary     : $PATH_OLLAMA/bin/ollama"
info "Models dir : $MODEL_OLLAMA"
info "Service    : sudo sv status ollama"
info "Restart your shell (or run: source $check) to pick up the new PATH"
info "Usage:"
info "  ollama run qwen2.5-coder:7b # Coding/Assistant"
info "  ollama run qwen3:8b         # Security/CTF"

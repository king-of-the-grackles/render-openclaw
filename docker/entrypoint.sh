#!/bin/bash
# OpenClaw Docker Entrypoint
# Handles runtime plugin installation before starting the main process
set -e

# ============================================
# RUNTIME PLUGIN INSTALLATION
# ============================================
# Install plugins listed in plugins-install.txt at container startup.
# This allows users to add custom plugins without rebuilding the image.
#
# Format of plugins-install.txt (one plugin per line):
#   ./extensions/my-plugin        # Local extension
#   npm:my-plugin@1.0.0           # npm package
#   gh:owner/repo                 # GitHub repo
#   # This is a comment          # Comments start with #
#
PLUGINS_FILE="/home/node/.openclaw/plugins-install.txt"

if [ -f "$PLUGINS_FILE" ]; then
  echo "[entrypoint] Installing plugins from plugins-install.txt..."
  while IFS= read -r plugin || [ -n "$plugin" ]; do
    # Trim whitespace
    plugin=$(echo "$plugin" | xargs)

    # Skip empty lines and comments
    [[ -z "$plugin" || "$plugin" == \#* ]] && continue

    # Extract plugin name for existence check
    plugin_name="${plugin##*/}"
    plugin_name="${plugin_name%%@*}"

    # Check if already installed
    if [ -d "/home/node/.openclaw/extensions/${plugin_name}" ]; then
      echo "[entrypoint] Plugin already installed: $plugin_name"
      continue
    fi

    echo "[entrypoint] Installing plugin: $plugin"
    node /app/dist/index.js plugins install "$plugin" || echo "[entrypoint] Warning: Failed to install $plugin"
  done < "$PLUGINS_FILE"
  echo "[entrypoint] Plugin installation complete."
fi

# ============================================
# SECURE TELEGRAM CONFIGURATION
# ============================================
# If TELEGRAM_BOT_TOKEN is set and no config exists, create a secure initial config.
# This sets up Telegram with maximum security settings:
#   - dmPolicy: "allowlist" (only pre-approved users can message)
#   - groupPolicy: "disabled" (no group access)
#   - configWrites: false (no remote config changes)
#
CONFIG_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ ! -f "$CONFIG_FILE" ]; then
  echo "[entrypoint] Creating secure Telegram configuration..."
  mkdir -p "$CONFIG_DIR"

  # Build allowFrom array if TELEGRAM_ALLOWFROM is set
  if [ -n "$TELEGRAM_ALLOWFROM" ]; then
    ALLOWFROM_JSON="[\"$TELEGRAM_ALLOWFROM\"]"
  else
    ALLOWFROM_JSON="[]"
  fi

  cat > "$CONFIG_FILE" << EOF
{
  "gateway": {
    "mode": "local"
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "\${TELEGRAM_BOT_TOKEN}",
      "dmPolicy": "allowlist",
      "allowFrom": $ALLOWFROM_JSON,
      "groupPolicy": "disabled",
      "configWrites": false
    }
  }
}
EOF
  chmod 600 "$CONFIG_FILE"
  echo "[entrypoint] Secure Telegram config created at $CONFIG_FILE"
  echo "[entrypoint] Security settings: dmPolicy=allowlist, groupPolicy=disabled, configWrites=false"
fi

# ============================================
# SKILL CONFIGURATION
# ============================================
# Disable Homebrew preference for Docker (Linux has apt/pip)
export SKILLS_INSTALL_PREFER_BREW="${SKILLS_INSTALL_PREFER_BREW:-false}"

# ============================================
# EXECUTE MAIN COMMAND
# ============================================
exec "$@"

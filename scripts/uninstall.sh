#!/bin/zsh
set -euo pipefail

user_id="$(id -u)"
support_dir="${HOME}/Library/Application Support/CodexUsageOverlay"
app_bundle="${support_dir}/Codex Usage Overlay.app"
launch_agent="${HOME}/Library/LaunchAgents/io.local.codex-usage-overlay.plist"

launchctl bootout "gui/${user_id}" "${launch_agent}" 2>/dev/null || true
rm -f "${launch_agent}"
rm -rf "${support_dir}"
echo "Uninstalled Codex Usage Overlay."

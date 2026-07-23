#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
user_home="${HOME}"
user_id="$(id -u)"
support_dir="${user_home}/Library/Application Support/CodexUsageOverlay"
app_bundle="${support_dir}/Codex Usage Overlay.app"
app_executable="${app_bundle}/Contents/MacOS/CodexUsageOverlay"
launch_agent="${user_home}/Library/LaunchAgents/io.local.codex-usage-overlay.plist"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is required. Install Xcode Command Line Tools or Xcode first." >&2
  exit 1
fi

cd "${project_dir}"
swift build -c release

mkdir -p "${app_bundle}/Contents/MacOS" "${app_bundle}/Contents/Resources" "${user_home}/Library/LaunchAgents"
cp ".build/release/CodexUsageOverlay" "${app_executable}"
cp "Resources/Info.plist" "${app_bundle}/Contents/Info.plist"
codesign --force --deep --sign - "${app_bundle}" >/dev/null

cp "Resources/io.local.codex-usage-overlay.plist" "${launch_agent}"
plutil -replace ProgramArguments -json "[\"${app_executable}\"]" "${launch_agent}"
launchctl bootout "gui/${user_id}" "${launch_agent}" 2>/dev/null || true
launchctl bootstrap "gui/${user_id}" "${launch_agent}"
launchctl kickstart -k "gui/${user_id}/io.local.codex-usage-overlay"

echo "Installed: ${app_bundle}"
echo "If prompted, allow Accessibility access for Codex Usage Overlay."

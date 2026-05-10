<#
.SYNOPSIS
  Full auth/session reset helper for Claude/OpenAI + browsers on Windows.

.DESCRIPTION
  This script is designed to troubleshoot broken sign-in flows by removing local
  authentication/session artifacts. It supports three cleanup modes:

  - Safe: like Soft, but skips Windows Credential Manager and network reset.
  - Soft: keeps browser profiles, but removes key auth/session web artifacts.
  - Hard: removes entire browser profile folders (all sessions/logins/cookies).

  Safety controls:
  - By default, script refuses destructive execution unless -ConfirmReset is passed.
  - Dry-run mode (-DryRun) shows exactly what would happen without making changes.

  IMPORTANT:
  - Hard mode logs you out of everything in supported browsers.
  - Reboot after a real run is strongly recommended.

.EXAMPLES
  # Preview only (no changes):
  powershell -ExecutionPolicy Bypass -File .\scripts\reset-claude-and-browser-logins.ps1 -Mode Safe -DryRun

  # Real cleanup, safest first step:
  powershell -ExecutionPolicy Bypass -File .\scripts\reset-claude-and-browser-logins.ps1 -Mode Safe -ConfirmReset

  # Real cleanup, deeper reset:
  powershell -ExecutionPolicy Bypass -File .\scripts\reset-claude-and-browser-logins.ps1 -Mode Soft -ConfirmReset

  # Real cleanup, maximum reset:
  powershell -ExecutionPolicy Bypass -File .\scripts\reset-claude-and-browser-logins.ps1 -Mode Hard -ConfirmReset
#>

param(
    # Cleanup depth:
    # Soft = targeted cleanup of auth/session artifacts.
    # Hard = full browser profile deletion.
    [ValidateSet('Safe','Soft','Hard')]
    [string]$Mode = 'Safe',

    # Which product scope to clean:
    # All = Claude + ChatGPT/OpenAI
    # Claude = only Claude/Anthropic artifacts
    # ChatGPT = only ChatGPT/OpenAI artifacts
    [ValidateSet('All','Claude','ChatGPT')]
    [string]$Product = 'All',

    # Required for destructive execution.
    # If not set, script refuses to make changes (unless -DryRun is used).
    [switch]$ConfirmReset,

    # Preview mode: no deletions/stops/resets are actually executed.
    # Script prints what would be done.
    [switch]$DryRun,

    # Optional: do not touch Windows Credential Manager.
    [switch]$SkipCredentialManager,

    # Optional: rename this PC (hostname) to help appear as a new machine identity.
    [switch]$EnableHostnameChange,

    # New hostname to set when -EnableHostnameChange is used.
    [string]$NewHostname,

    # Optional: deeper network contour refresh (IP release/renew + winsock reset).
    [switch]$EnableNetworkContourRefresh,
    # Optional basic network reset (DNS flush + WinHTTP proxy reset).
    [switch]$EnableBasicNetworkReset,
    # Run only basic network reset step.
    [switch]$NetworkResetOnly,
    # Status-only mode: inspect login/session artifacts without any changes.
    [switch]$StatusOnly,
    # In status mode, remove only artifacts that were found by checks.
    [switch]$StatusDeleteFound,

    # Run privacy hardening checks/fixes (env + git identity + git remotes audit).
    [switch]$PrivacyHardening,

    # UI language for menu and key messages:
    # Auto = detect from system UI culture; ru/en = force language.
    [ValidateSet('Auto','ru','en')]
    [string]$Language = 'Auto'
)

# Reduce noisy non-critical errors; script tracks failures in summary counters.
$ErrorActionPreference = 'SilentlyContinue'
$script:InteractiveMenu = $false
$script:LogPath = Join-Path $env:TEMP ("claude-reset-log-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:UiLang = if ($Language -eq 'Auto') {
    if ((Get-Culture).Name -like 'ru*') { 'ru' } else { 'en' }
} else {
    $Language
}

function L {
    param(
        [string]$Ru,
        [string]$En
    )
    if ($script:UiLang -eq 'ru') { return $Ru }
    return $En
}

# Interactive menu when script is launched without parameters.
# This makes it easy to choose execution mode directly from terminal.
if ($PSBoundParameters.Count -eq 0) {
    $script:InteractiveMenu = $true
    Write-Host ''
    Write-Host (L 'Выберите режим запуска:' 'Choose run mode:') -ForegroundColor Cyan
    Write-Host (L '  1) Проверка статуса входов (диагностика + опция удалить найденное) [НЕ РАЗЛОГИНИТ]' '  1) Login status check (diagnostics + optional delete found) [WILL NOT LOG OUT]') -ForegroundColor Green
    Write-Host (L '     Что делает: показывает, где найдены артефакты входа, и предлагает удалить только найденное.' '     Shows where login artifacts were found and can delete only found items.')
    Write-Host (L '  2) SAFE dry-run (предпросмотр) [НЕ РАЗЛОГИНИТ]' '  2) SAFE dry-run (preview) [WILL NOT LOG OUT]') -ForegroundColor Green
    Write-Host (L '  3) SOFT dry-run (предпросмотр) [НЕ РАЗЛОГИНИТ]' '  3) SOFT dry-run (preview) [WILL NOT LOG OUT]') -ForegroundColor Green
    Write-Host (L '  4) HARD dry-run (предпросмотр) [НЕ РАЗЛОГИНИТ]' '  4) HARD dry-run (preview) [WILL NOT LOG OUT]') -ForegroundColor Green
    Write-Host (L '  5) SAFE (реальный запуск) — мягкая очистка. [МОЖЕТ РАЗЛОГИНИТЬ ТОЧЕЧНО]' '  5) SAFE (real run) - gentle cleanup. [MAY LOG OUT SOME SITES]') -ForegroundColor Green
    Write-Host (L '  6) SOFT (реальный запуск) — как SAFE, плюс Credential Manager. [МОЖЕТ РАЗЛОГИНИТЬ ЧАСТИЧНО]' '  6) SOFT (real run) - SAFE + Credential Manager. [MAY LOG OUT PARTIALLY]') -ForegroundColor Yellow
    Write-Host (L '  7) HARD (реальный запуск) — полный сброс профилей браузеров. [РАЗЛОГИНИТ ВЕЗДЕ И ВСЁ]' '  7) HARD (real run) - full browser profile reset. [LOGS OUT EVERYWHERE]') -ForegroundColor Red
    Write-Host (L '  8) Сброс сети dry-run (предпросмотр) [НЕ РАЗЛОГИНИТ]' '  8) Network reset dry-run (preview) [WILL NOT LOG OUT]') -ForegroundColor Green
    Write-Host (L '  9) Сброс сети (реальный запуск) — только DNS/WinHTTP. [НЕ РАЗЛОГИНИТ]' '  9) Network reset (real run) - DNS/WinHTTP only. [WILL NOT LOG OUT]') -ForegroundColor Green
    Write-Host (L ' 10) Privacy hardening dry-run (предпросмотр) [НЕ РАЗЛОГИНИТ]' ' 10) Privacy hardening dry-run (preview) [WILL NOT LOG OUT]') -ForegroundColor Green
    Write-Host (L ' 11) Privacy hardening (реальный запуск) [НЕ РАЗЛОГИНИТ]' ' 11) Privacy hardening (real run) [WILL NOT LOG OUT]') -ForegroundColor Green
    Write-Host ((L " 12) Смена имени компьютера (hostname) [НЕ РАЗЛОГИНИТ] (текущее: {0})" " 12) Change computer hostname [WILL NOT LOG OUT] (current: {0})") -f $env:COMPUTERNAME) -ForegroundColor Yellow
    Write-Host (L ' 13) Выход' ' 13) Exit')
    $choice = Read-Host (L 'Введите 1-13' 'Enter 1-13')

    switch ($choice) {
        '1' { $Mode = 'Safe'; $DryRun = $true; $StatusOnly = $true; $SkipCredentialManager = $true }
        '2' { $Mode = 'Safe'; $DryRun = $true }
        '3' { $Mode = 'Soft'; $DryRun = $true }
        '4' { $Mode = 'Hard'; $DryRun = $true }
        '5' { $Mode = 'Safe'; $ConfirmReset = $true; $DryRun = $false }
        '6' { $Mode = 'Soft'; $ConfirmReset = $true; $DryRun = $false }
        '7' { $Mode = 'Hard'; $ConfirmReset = $true; $DryRun = $false }
        '8' { $Mode = 'Safe'; $DryRun = $true; $EnableBasicNetworkReset = $true; $NetworkResetOnly = $true; $SkipCredentialManager = $true }
        '9' { $Mode = 'Safe'; $ConfirmReset = $true; $EnableBasicNetworkReset = $true; $NetworkResetOnly = $true; $SkipCredentialManager = $true }
        '10' { $Mode = 'Safe'; $DryRun = $true; $PrivacyHardening = $true; $SkipCredentialManager = $true }
        '11' { $Mode = 'Safe'; $ConfirmReset = $true; $PrivacyHardening = $true; $SkipCredentialManager = $true }
        '12' {
            $Mode = 'Safe'; $ConfirmReset = $true; $SkipCredentialManager = $true
            $EnableHostnameChange = $true
            Write-Host ((L "Текущее имя компьютера: {0}" "Current computer name: {0}") -f $env:COMPUTERNAME) -ForegroundColor Cyan
            $hn = Read-Host (L 'Введите новое имя компьютера (1-15: A-Z,0-9,-), Enter=авто' 'Enter new computer name (1-15: A-Z,0-9,-), Enter=auto')
            if (-not [string]::IsNullOrWhiteSpace($hn)) { $NewHostname = $hn }
        }
        default {
            Write-Host (L 'Выход без изменений.' 'Exit without changes.') -ForegroundColor Yellow
            exit 0
        }
    }

    if ((-not $NetworkResetOnly) -and (-not $StatusOnly)) {
        Write-Host ''
        Write-Host (L 'Выберите продукт для очистки:' 'Choose product scope:') -ForegroundColor Cyan
        Write-Host (L '  1) Все (Claude + ChatGPT/OpenAI)' '  1) All (Claude + ChatGPT/OpenAI)')
        Write-Host (L '  2) Только Claude' '  2) Claude only')
        Write-Host (L '  3) Только ChatGPT/OpenAI' '  3) ChatGPT/OpenAI only')
        $scopeChoice = Read-Host (L 'Введите 1-3' 'Enter 1-3')
        switch ($scopeChoice) {
            '2' { $Product = 'Claude' }
            '3' { $Product = 'ChatGPT' }
            default { $Product = 'All' }
        }

        if ($Mode -eq 'Soft' -or $Mode -eq 'Hard') {
            $askCred = Read-Host (L 'Очистить Credential Manager? (Y/n)' 'Clean Credential Manager entries? (Y/n)')
            if ($askCred -match '^(?i)n|no|н|нет$') { $SkipCredentialManager = $true }
        }
    }
    elseif ($StatusOnly) {
        Write-Host ''
        Write-Host (L 'Выберите продукт для проверки статуса:' 'Choose product scope for status check:') -ForegroundColor Cyan
        Write-Host (L '  1) Все (Claude + ChatGPT/OpenAI)' '  1) All (Claude + ChatGPT/OpenAI)')
        Write-Host (L '  2) Только Claude' '  2) Claude only')
        Write-Host (L '  3) Только ChatGPT/OpenAI' '  3) ChatGPT/OpenAI only')
        $scopeChoice = Read-Host (L 'Введите 1-3' 'Enter 1-3')
        switch ($scopeChoice) {
            '2' { $Product = 'Claude' }
            '3' { $Product = 'ChatGPT' }
            default { $Product = 'All' }
        }
    }
}

# Guardrail: prevent accidental destructive run when running with explicit flags.
if (-not $ConfirmReset -and -not $DryRun) {
    Write-Host (L 'ОТКАЗ: укажите -ConfirmReset для реального запуска или -DryRun для предпросмотра.' 'REFUSED: use -ConfirmReset for real run or -DryRun for preview.') -ForegroundColor Yellow
    Write-Host (L 'Примеры:' 'Examples:')
    Write-Host '  Interactive menu: powershell -ExecutionPolicy Bypass -File .\scripts\reset-claude-and-browser-logins.ps1'
    Write-Host '  Dry:  powershell -ExecutionPolicy Bypass -File .\scripts\reset-claude-and-browser-logins.ps1 -Mode Safe -DryRun'
    Write-Host '  Safe: powershell -ExecutionPolicy Bypass -File .\scripts\reset-claude-and-browser-logins.ps1 -Mode Safe -ConfirmReset'
    Write-Host '  Soft: powershell -ExecutionPolicy Bypass -File .\scripts\reset-claude-and-browser-logins.ps1 -Mode Soft -ConfirmReset'
    Write-Host '  Hard: powershell -ExecutionPolicy Bypass -File .\scripts\reset-claude-and-browser-logins.ps1 -Mode Hard -ConfirmReset'
    exit 1
}

# Runtime counters for final summary.
$script:Deleted = 0
$script:Skipped = 0
$script:Errors = 0
$script:Step = 0
$script:StatusFound = 0
$script:StatusMiss = 0

# Prints a numbered step header.
function Write-Step {
    param([string]$Text)
    $script:Step++
    Write-Host ""
    Write-Host ("[{0}] {1}" -f $script:Step, $Text) -ForegroundColor Cyan
    Add-Content -LiteralPath $script:LogPath -Value ("[{0}] {1}" -f $script:Step, $Text)
}

function Write-Explain {
    param([string]$Text)
    Write-Host ("    -> {0}" -f $Text) -ForegroundColor DarkCyan
    Add-Content -LiteralPath $script:LogPath -Value ("    -> {0}" -f $Text)
}

# Prints one structured log line.
function Write-Item {
    param(
        [string]$Status,
        [string]$Path,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host ("  [{0}] {1}" -f $Status, $Path) -ForegroundColor $Color
    Add-Content -LiteralPath $script:LogPath -Value ("  [{0}] {1}" -f $Status, $Path)
}

function Write-ModeMatrix {
    $browserTargeted = ($Mode -eq 'Safe' -or $Mode -eq 'Soft')
    $browserFull = ($Mode -eq 'Hard')
    $credEnabled = ($Mode -ne 'Safe' -and -not $SkipCredentialManager)
    $networkBasic = $EnableBasicNetworkReset

    Write-Host ''
    Write-Host 'Execution Matrix:' -ForegroundColor White
    Write-Host ("  Product scope                 : {0}" -f $Product) -ForegroundColor Gray
    Write-Host ("  Local app state cleanup       : ON") -ForegroundColor Green
    Write-Host ("  Browser targeted cleanup      : {0}" -f $(if ($browserTargeted) { 'ON' } else { 'OFF' })) -ForegroundColor $(if ($browserTargeted) { 'Green' } else { 'DarkGray' })
    Write-Host ("  Browser full profile wipe     : {0}" -f $(if ($browserFull) { 'ON' } else { 'OFF' })) -ForegroundColor $(if ($browserFull) { 'Green' } else { 'DarkGray' })
    Write-Host ("  Credential Manager cleanup    : {0}" -f $(if ($credEnabled) { 'ON' } else { 'OFF' })) -ForegroundColor $(if ($credEnabled) { 'Green' } else { 'DarkGray' })
    Write-Host ("  Basic network reset           : {0}" -f $(if ($networkBasic) { 'ON' } else { 'OFF' })) -ForegroundColor $(if ($networkBasic) { 'Green' } else { 'DarkGray' })
    Write-Host ("  Hostname change               : {0}" -f $(if ($EnableHostnameChange) { 'ON' } else { 'OFF' })) -ForegroundColor $(if ($EnableHostnameChange) { 'Green' } else { 'DarkGray' })
    Write-Host ("  Deep network contour refresh  : {0}" -f $(if ($EnableNetworkContourRefresh) { 'ON' } else { 'OFF' })) -ForegroundColor $(if ($EnableNetworkContourRefresh) { 'Green' } else { 'DarkGray' })
    Write-Host ("  Privacy hardening             : {0}" -f $(if ($PrivacyHardening) { 'ON' } else { 'OFF' })) -ForegroundColor $(if ($PrivacyHardening) { 'Green' } else { 'DarkGray' })
    Write-Host ("  Status-only check             : {0}" -f $(if ($StatusOnly) { 'ON' } else { 'OFF' })) -ForegroundColor $(if ($StatusOnly) { 'Green' } else { 'DarkGray' })
    Write-Host ("  Delete found in status mode   : {0}" -f $(if ($StatusDeleteFound) { 'ON' } else { 'OFF' })) -ForegroundColor $(if ($StatusDeleteFound) { 'Green' } else { 'DarkGray' })
    Add-Content -LiteralPath $script:LogPath -Value ''
    Add-Content -LiteralPath $script:LogPath -Value 'Execution Matrix:'
    Add-Content -LiteralPath $script:LogPath -Value ("  Product scope                 : {0}" -f $Product)
    Add-Content -LiteralPath $script:LogPath -Value ("  Local app state cleanup       : ON")
    Add-Content -LiteralPath $script:LogPath -Value ("  Browser targeted cleanup      : {0}" -f $(if ($browserTargeted) { 'ON' } else { 'OFF' }))
    Add-Content -LiteralPath $script:LogPath -Value ("  Browser full profile wipe     : {0}" -f $(if ($browserFull) { 'ON' } else { 'OFF' }))
    Add-Content -LiteralPath $script:LogPath -Value ("  Credential Manager cleanup    : {0}" -f $(if ($credEnabled) { 'ON' } else { 'OFF' }))
    Add-Content -LiteralPath $script:LogPath -Value ("  Basic network reset           : {0}" -f $(if ($networkBasic) { 'ON' } else { 'OFF' }))
    Add-Content -LiteralPath $script:LogPath -Value ("  Hostname change               : {0}" -f $(if ($EnableHostnameChange) { 'ON' } else { 'OFF' }))
    Add-Content -LiteralPath $script:LogPath -Value ("  Deep network contour refresh  : {0}" -f $(if ($EnableNetworkContourRefresh) { 'ON' } else { 'OFF' }))
    Add-Content -LiteralPath $script:LogPath -Value ("  Privacy hardening             : {0}" -f $(if ($PrivacyHardening) { 'ON' } else { 'OFF' }))
    Add-Content -LiteralPath $script:LogPath -Value ("  Status-only check             : {0}" -f $(if ($StatusOnly) { 'ON' } else { 'OFF' }))
    Add-Content -LiteralPath $script:LogPath -Value ("  Delete found in status mode   : {0}" -f $(if ($StatusDeleteFound) { 'ON' } else { 'OFF' }))
}

function Write-StatusCheck {
    param(
        [string]$Name,
        [string]$Path
    )
    if (Test-Path -LiteralPath $Path) {
        $script:StatusFound++
        Write-Item -Status 'НАЙДЕНО' -Path ("{0}: {1}" -f $Name, $Path) -Color Green
        if ($StatusDeleteFound) {
            if ($DryRun) {
                Write-Item -Status 'DRY RUN (WOULD REMOVE)' -Path $Path -Color Yellow
            }
            else {
                Remove-PathSafe -Path $Path
            }
        }
    }
    else {
        $script:StatusMiss++
        Write-Item -Status 'НЕ НАЙДЕНО' -Path ("{0}: {1}" -f $Name, $Path) -Color DarkGray
    }
}

function Write-MatchingStatus {
    param(
        [string]$Name,
        [string]$BasePath,
        [string[]]$Patterns
    )
    if (-not (Test-Path -LiteralPath $BasePath)) {
        $script:StatusMiss++
        Write-Item -Status 'НЕ НАЙДЕНО' -Path ("{0}: {1}" -f $Name, $BasePath) -Color DarkGray
        return
    }
    $count = 0
    $matchedNames = @()
    $matchedPaths = @()
    Get-ChildItem -LiteralPath $BasePath -Force | ForEach-Object {
        foreach ($p in $Patterns) {
            if ($_.Name -like $p) {
                $count++
                $matchedNames += $_.Name
                $matchedPaths += $_.FullName
                break
            }
        }
    }
    if ($count -gt 0) {
        $script:StatusFound++
        $previewLimit = 8
        $shown = $matchedNames | Select-Object -First $previewLimit
        $tail = ''
        if ($count -gt $previewLimit) {
            $tail = (" ... +{0} еще" -f ($count - $previewLimit))
        }
        Write-Item -Status 'НАЙДЕНО' -Path ("{0}: {1} в {2}" -f $Name, ($shown -join ', '), $BasePath) -Color Green
        if (-not [string]::IsNullOrWhiteSpace($tail)) {
            Write-Item -Status 'INFO' -Path ("{0}:{1}" -f $Name, $tail) -Color DarkYellow
        }
        if ($StatusDeleteFound) {
            foreach ($mp in $matchedPaths) {
                if ($DryRun) {
                    Write-Item -Status 'DRY RUN (WOULD REMOVE)' -Path $mp -Color Yellow
                }
                else {
                    Remove-PathSafe -Path $mp
                }
            }
        }
    }
    else {
        $script:StatusMiss++
        Write-Item -Status 'НЕ НАЙДЕНО' -Path ("{0}: совпадений нет в {1}" -f $Name, $BasePath) -Color DarkGray
    }
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-DryRunPreview {
    param([string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.PSIsContainer) {
            Write-Item -Status 'PREVIEW' -Path ("Directory found: {0}" -f $Path) -Color DarkYellow
            return
        }

        $size = [int64]$item.Length
        $lineCount = 0
        try {
            $lineCount = (Get-Content -LiteralPath $Path -ErrorAction Stop | Measure-Object -Line).Lines
        }
        catch {
            Write-Item -Status 'PREVIEW' -Path ("Binary/locked file: {0} ({1} bytes)" -f $Path, $size) -Color DarkYellow
            return
        }

        if ($size -le 8192 -and $lineCount -le 60) {
            Write-Item -Status 'PREVIEW' -Path ("File found: {0} ({1} bytes, {2} lines)" -f $Path, $size, $lineCount) -Color DarkYellow
            Write-Host '    ---- file content start ----' -ForegroundColor DarkYellow
            Get-Content -LiteralPath $Path | ForEach-Object { Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray }
            Write-Host '    ---- file content end ----' -ForegroundColor DarkYellow
            Add-Content -LiteralPath $script:LogPath -Value ("  [PREVIEW] File content shown for: {0}" -f $Path)
        }
        else {
            Write-Item -Status 'PREVIEW' -Path ("File found (too long to print): {0} ({1} bytes, {2} lines)" -f $Path, $size, $lineCount) -Color DarkYellow
        }
    }
    catch {
        Write-Item -Status 'PREVIEW' -Path ("Could not inspect: {0}" -f $Path) -Color DarkYellow
    }
}

# Safe remove helper:
# - checks existence
# - supports dry-run
# - logs deleted/skipped/error
function Remove-PathSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    try {
        if (Test-Path -LiteralPath $Path) {
            if ($DryRun) {
                Write-Item -Status 'DRY RUN (WOULD REMOVE)' -Path $Path -Color Yellow
                Show-DryRunPreview -Path $Path
                $script:Skipped++
                return
            }
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            $script:Deleted++
            Write-Item -Status 'DELETED' -Path $Path -Color Green
        }
        else {
            $script:Skipped++
            Write-Item -Status 'NO CHANGES NEEDED' -Path $Path -Color DarkGray
        }
    }
    catch {
        $script:Errors++
        Write-Item -Status 'ERROR' -Path ("{0} ({1})" -f $Path, $_.Exception.Message) -Color Red
    }
}

# Deletes children in a directory matching wildcard patterns.
# Useful for targeted browser storage cleanup by domain-like names.
function Remove-MatchingInDir {
    param(
        [string]$BasePath,
        [string[]]$Patterns
    )

    if (-not (Test-Path -LiteralPath $BasePath)) {
        $script:Skipped++
        Write-Item -Status 'NO CHANGES NEEDED' -Path $BasePath -Color DarkGray
        return
    }

    $foundAny = $false
    Get-ChildItem -LiteralPath $BasePath -Force | ForEach-Object {
        $name = $_.Name
        foreach ($p in $Patterns) {
            if ($name -like $p) {
                $foundAny = $true
                Remove-PathSafe -Path $_.FullName
                break
            }
        }
    }

    if (-not $foundAny) {
        Write-Item -Status 'INFO' -Path ("Совпадений не найдено в: {0}" -f $BasePath) -Color DarkYellow
    }
}

# Stops running processes that can lock files (browsers/clients/editors).
# In dry-run mode, only reports what would be stopped.
function Stop-Processes {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $procs = Get-Process -Name $n -ErrorAction SilentlyContinue
        if ($procs) {
            foreach ($p in $procs) {
                try {
                    if ($DryRun) {
                        Write-Item -Status 'DRY RUN (WOULD STOP)' -Path ("Stop {0} (PID {1})" -f $p.ProcessName, $p.Id) -Color Yellow
                    }
                    else {
                        Stop-Process -Id $p.Id -Force -ErrorAction Stop
                        Write-Item -Status 'STOPPED' -Path ("{0} (PID {1})" -f $p.ProcessName, $p.Id) -Color Yellow
                    }
                }
                catch {
                    Write-Item -Status 'INFO' -Path ("Не удалось остановить {0} (PID {1}) — процесс уже завершен или нет прав." -f $p.ProcessName, $p.Id) -Color DarkYellow
                }
            }
        }
    }
}

# Standard user paths used by Windows apps.
$local = $env:LOCALAPPDATA
$roam  = $env:APPDATA
$home  = $env:USERPROFILE

# Script header.
Write-Host '========================================' -ForegroundColor White
Write-Host ' Claude/Auth Reset Script (Windows)     ' -ForegroundColor White
Write-Host '========================================' -ForegroundColor White
Write-Host ("Mode: {0}" -f $Mode) -ForegroundColor White
Write-Host ("Product: {0}" -f $Product) -ForegroundColor White
Write-Host ("DryRun: {0}" -f $DryRun.IsPresent) -ForegroundColor White
Write-Host ("Time: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor White
Write-Host ("Log: {0}" -f $script:LogPath) -ForegroundColor DarkGray
Set-Content -LiteralPath $script:LogPath -Value ("Claude/Auth Reset Script Log`r`nTime: {0}`r`nMode: {1}`r`nDryRun: {2}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Mode, $DryRun.IsPresent)
if ($EnableHostnameChange) {
    Write-Host ("Hostname change: enabled (target: {0})" -f ($(if ($NewHostname) { $NewHostname } else { 'AUTO-GENERATED' }))) -ForegroundColor White
}
if ($EnableNetworkContourRefresh) {
    Write-Host 'Network contour refresh: enabled' -ForegroundColor White
}
if ($PrivacyHardening) {
    Write-Host 'Privacy hardening: enabled' -ForegroundColor White
}
Write-ModeMatrix

if ($StatusOnly) {
    Write-Step 'Проверка статуса входов (без изменений)'
    if ($StatusDeleteFound) {
        Write-Explain 'Режим проверки с удалением: будут удалены только найденные артефакты из этого отчета.'
    }
    else {
        Write-Explain 'Это диагностический режим: ничего не удаляется и процессы не закрываются.'
    }
    Write-Explain 'Статус "НАЙДЕНО" означает наличие локальных артефактов сессии, но не гарантирует 100% активный вход.'

    $patterns = @()
    if ($Product -eq 'All' -or $Product -eq 'Claude') { $patterns += @('*claude*','*anthropic*') }
    if ($Product -eq 'All' -or $Product -eq 'ChatGPT') { $patterns += @('*openai*','*chatgpt*') }

    Write-Step 'Локальные данные приложений'
    if ($Product -eq 'All' -or $Product -eq 'Claude') {
        Write-StatusCheck -Name 'Claude home' -Path (Join-Path $home '.claude')
        Write-StatusCheck -Name 'Claude roaming' -Path (Join-Path $roam 'Claude')
        Write-StatusCheck -Name 'Claude local' -Path (Join-Path $local 'Claude')
    }
    if ($Product -eq 'All' -or $Product -eq 'ChatGPT') {
        Write-StatusCheck -Name 'OpenAI roaming' -Path (Join-Path $roam 'OpenAI')
        Write-StatusCheck -Name 'OpenAI local' -Path (Join-Path $local 'OpenAI')
        Write-MatchingStatus -Name 'ChatGPT Desktop package' -BasePath (Join-Path $local 'Packages') -Patterns @('OpenAI.ChatGPT-Desktop_*')
    }

    Write-Step 'Браузерные артефакты по выбранному продукту'
    $bases = @(
        (Join-Path $local 'Google\Chrome\User Data'),
        (Join-Path $local 'Microsoft\Edge\User Data'),
        (Join-Path $local 'BraveSoftware\Brave-Browser\User Data'),
        (Join-Path $local 'Yandex\YandexBrowser\User Data')
    )
    foreach ($base in $bases) {
        if (-not (Test-Path -LiteralPath $base)) {
            Write-Item -Status 'НЕ НАЙДЕНО' -Path ("Браузерная база: {0}" -f $base) -Color DarkGray
            continue
        }
        Write-Item -Status 'ПРОВЕРКА' -Path ("Браузерная база: {0}" -f $base) -Color Cyan
        $profiles = Get-ChildItem -LiteralPath $base -Directory -Force | Where-Object {
            $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile' -or $_.Name -eq 'System Profile'
        }
        foreach ($pr in $profiles) {
            Write-MatchingStatus -Name ("{0} LocalStorage" -f $pr.Name) -BasePath (Join-Path $pr.FullName 'Local Storage\leveldb') -Patterns $patterns
            Write-MatchingStatus -Name ("{0} IndexedDB" -f $pr.Name) -BasePath (Join-Path $pr.FullName 'IndexedDB') -Patterns $patterns
            Write-MatchingStatus -Name ("{0} ServiceWorker" -f $pr.Name) -BasePath (Join-Path $pr.FullName 'Service Worker') -Patterns $patterns
        }
    }

    Write-Step 'Credential Manager (индикатор)'
    if ($SkipCredentialManager) {
        Write-Item -Status 'ПРОПУЩЕНО' -Path 'Проверка credential manager отключена флагом.' -Color DarkGray
    }
    else {
        $credPattern = '(?i)claude|anthropic|openai|chatgpt'
        if ($Product -eq 'Claude') { $credPattern = '(?i)claude|anthropic' }
        elseif ($Product -eq 'ChatGPT') { $credPattern = '(?i)openai|chatgpt' }
        $raw = cmdkey /list
        $count = 0
        foreach ($line in $raw) {
            if ($line -match 'Target:\s*(.+)$') {
                if ($Matches[1].Trim() -match $credPattern) { $count++ }
            }
        }
        if ($count -gt 0) {
            $script:StatusFound++
            Write-Item -Status 'НАЙДЕНО' -Path ("Credential записей по scope: {0}" -f $count) -Color Green
            if ($StatusDeleteFound) {
                foreach ($line in $raw) {
                    if ($line -match 'Target:\s*(.+)$') {
                        $t = $Matches[1].Trim()
                        if ($t -match $credPattern) {
                            if ($DryRun) {
                                Write-Item -Status 'DRY RUN (WOULD REMOVE)' -Path ("Delete credential: {0}" -f $t) -Color Yellow
                            }
                            else {
                                cmdkey /delete:$t | Out-Null
                                Write-Item -Status 'CRED-DEL' -Path $t -Color Green
                            }
                        }
                    }
                }
            }
        }
        else { $script:StatusMiss++; Write-Item -Status 'НЕ НАЙДЕНО' -Path 'Credential записей по scope не найдено' -Color DarkGray }
    }

    Write-Step 'Итог диагностики статуса'
    Write-Item -Status 'INFO' -Path ("Сигналы НАЙДЕНО: {0}" -f $script:StatusFound) -Color Cyan
    Write-Item -Status 'INFO' -Path ("Сигналы НЕ НАЙДЕНО: {0}" -f $script:StatusMiss) -Color DarkGray
    if ($script:StatusFound -gt 0) {
        Write-Item -Status 'ВЫВОД' -Path 'Локальные артефакты входа обнаружены (как минимум в одном источнике).' -Color Green
    }
    else {
        Write-Item -Status 'ВЫВОД' -Path 'Артефакты в проверенных источниках не найдены. Это не гарантирует 100% отсутствие активной веб-сессии.' -Color Yellow
    }

    if ($script:InteractiveMenu -and -not $StatusDeleteFound) {
        Write-Host ''
        $ansDelete = Read-Host 'Удалить найденные артефакты по этому отчету? (y/N)'
        if ($ansDelete -match '^(?i)y|yes|д|да$') {
            $StatusDeleteFound = $true
            $DryRun = $false
            Write-Step 'Удаление найденных артефактов (по текущему scope)'
            Write-Explain 'Удаляются только артефакты, найденные паттернами текущей проверки.'
            $askStopForDelete = Read-Host 'Закрыть браузеры/клиенты перед удалением, чтобы снять блокировки файлов? (Y/n)'
            if (-not ($askStopForDelete -match '^(?i)n|no|н|нет$')) {
                Write-Explain 'Останавливаю браузеры и связанные процессы перед удалением.'
                Stop-Processes -Names @(
                    'claude', 'claude-code', 'node',
                    'chrome', 'msedge', 'firefox', 'brave', 'opera', 'opera_gx', 'vivaldi', 'browser'
                )
                Start-Sleep -Seconds 1
            }

            if ($Product -eq 'All' -or $Product -eq 'Claude') {
                Remove-PathSafe -Path (Join-Path $home '.claude')
                Remove-PathSafe -Path (Join-Path $roam 'Claude')
                Remove-PathSafe -Path (Join-Path $local 'Claude')
                Remove-PathSafe -Path (Join-Path $roam 'Anthropic')
                Remove-PathSafe -Path (Join-Path $local 'Anthropic')
            }
            if ($Product -eq 'All' -or $Product -eq 'ChatGPT') {
                Remove-PathSafe -Path (Join-Path $roam 'OpenAI')
                Remove-PathSafe -Path (Join-Path $local 'OpenAI')
                Remove-MatchingInDir -BasePath (Join-Path $local 'Packages') -Patterns @('OpenAI.ChatGPT-Desktop_*')
            }

            $delPatterns = @()
            if ($Product -eq 'All' -or $Product -eq 'Claude') { $delPatterns += @('*claude*','*anthropic*') }
            if ($Product -eq 'All' -or $Product -eq 'ChatGPT') { $delPatterns += @('*openai*','*chatgpt*') }

            $delBases = @(
                (Join-Path $local 'Google\Chrome\User Data'),
                (Join-Path $local 'Microsoft\Edge\User Data'),
                (Join-Path $local 'BraveSoftware\Brave-Browser\User Data'),
                (Join-Path $local 'Yandex\YandexBrowser\User Data')
            )
            foreach ($db in $delBases) {
                if (-not (Test-Path -LiteralPath $db)) { continue }
                $profiles = Get-ChildItem -LiteralPath $db -Directory -Force | Where-Object {
                    $_.Name -eq 'Default' -or $_.Name -like 'Profile *' -or $_.Name -eq 'Guest Profile' -or $_.Name -eq 'System Profile'
                }
                foreach ($pr in $profiles) {
                    Remove-MatchingInDir -BasePath (Join-Path $pr.FullName 'Local Storage\leveldb') -Patterns $delPatterns
                    Remove-MatchingInDir -BasePath (Join-Path $pr.FullName 'IndexedDB') -Patterns $delPatterns
                    Remove-MatchingInDir -BasePath (Join-Path $pr.FullName 'Service Worker') -Patterns $delPatterns
                }
            }
        }
    }

    # Force non-destructive path after status check.
    $NetworkResetOnly = $true
    $EnableBasicNetworkReset = $false
    $EnableNetworkContourRefresh = $false
    $PrivacyHardening = $false
}

if ($StatusOnly) {
    # status-only branch already executed above
}
elseif ($NetworkResetOnly) {
    Write-Step 'Режим "только сеть"'
    Write-Explain 'Очистка приложений и браузерных данных пропущена.'
}
else {
# Step 1: close relevant processes to unlock files.
Write-Step 'Закрытие процессов Claude/браузеров/редакторов'
Write-Explain 'Останавливает запущенные приложения, чтобы файлы не были заблокированы.'
Write-Explain 'В DryRun только показывает, какие процессы будут остановлены.'
Stop-Processes -Names @(
    'claude', 'claude-code', 'node',
    'chrome', 'msedge', 'firefox', 'brave', 'opera', 'opera_gx', 'vivaldi', 'browser',
    'Code', 'Code - Insiders'
)
Start-Sleep -Seconds 1

# Step 2: remove app-local state for Claude/Anthropic/OpenAI.
# This targets common token/session/cache/config locations.
Write-Step 'Удаление локального состояния выбранного продукта'
Write-Explain 'Удаляет локальные папки, где обычно лежат токены, кэш сессий и состояние клиента.'
Write-Explain ("Выбранный scope: {0}" -f $Product)
$coreTargets = @()
if ($Product -eq 'All' -or $Product -eq 'Claude') {
    $coreTargets += @(
        (Join-Path $home '.claude'),
        (Join-Path $home '.config\claude'),
        (Join-Path $home '.cache\claude'),
        (Join-Path $roam 'Claude'),
        (Join-Path $local 'Claude'),
        (Join-Path $local 'claude'),
        (Join-Path $roam 'Anthropic'),
        (Join-Path $local 'Anthropic')
    )
}
if ($Product -eq 'All' -or $Product -eq 'ChatGPT') {
    $coreTargets += @(
        (Join-Path $roam 'OpenAI'),
        (Join-Path $local 'OpenAI')
    )
}
$coreTargets | ForEach-Object { Remove-PathSafe -Path $_ }

# Step 3: optional cleanup of ChatGPT desktop package data (only for scopes that include ChatGPT/OpenAI).
if ($Product -eq 'All' -or $Product -eq 'ChatGPT') {
    Write-Step 'Удаление пакета ChatGPT Desktop (если установлен)'
    Write-Explain 'Удаляет папки пакета ChatGPT Desktop в Windows, если они существуют.'
    Remove-MatchingInDir -BasePath (Join-Path $local 'Packages') -Patterns @('OpenAI.ChatGPT-Desktop_*')
}

if ($Mode -eq 'Safe' -or $Mode -eq 'Soft') {
    # Soft mode keeps browser profiles but removes key auth/session artifacts
    # and targeted domain-related storage entries.
    Write-Step ("Режим {0}: точечная очистка веб-артефактов в существующих профилях браузеров" -f $Mode)
    Write-Explain 'Сохраняет профили браузера, но удаляет ключевые артефакты входа/сессий по выбранному scope.'
    Write-Explain 'Это исправляет циклы входа без полного сброса всех данных браузера.'
    $domainPatterns = @()
    if ($Product -eq 'All' -or $Product -eq 'Claude') { $domainPatterns += @('*claude*','*anthropic*') }
    if ($Product -eq 'All' -or $Product -eq 'ChatGPT') { $domainPatterns += @('*openai*','*chatgpt*') }

    $softTargets = @(
        (Join-Path $local 'Google\Chrome\User Data'),
        (Join-Path $local 'Microsoft\Edge\User Data'),
        (Join-Path $local 'BraveSoftware\Brave-Browser\User Data'),
        (Join-Path $local 'Yandex\YandexBrowser\User Data')
    )

    foreach ($base in $softTargets) {
        if (-not (Test-Path -LiteralPath $base)) {
            $script:Skipped++
            Write-Item -Status 'NO CHANGES NEEDED' -Path $base -Color DarkGray
            continue
        }

        # Only iterate real browser profiles to avoid scanning component/cache folders.
        $profiles = Get-ChildItem -LiteralPath $base -Directory -Force | Where-Object {
            $_.Name -eq 'Default' -or
            $_.Name -like 'Profile *' -or
            $_.Name -eq 'Guest Profile' -or
            $_.Name -eq 'System Profile'
        }

        if (-not $profiles) {
            Write-Item -Status 'INFO' -Path ("Профили браузера не найдены в: {0}" -f $base) -Color DarkYellow
            continue
        }

        $profiles | ForEach-Object {
            $profile = $_.FullName

            # General auth/session databases in Chromium profiles are shared by many sites.
            # To keep product isolation strict, only remove these for Product=All.
            if ($Product -eq 'All') {
                Remove-PathSafe -Path (Join-Path $profile 'Cookies')
                Remove-PathSafe -Path (Join-Path $profile 'Network\Cookies')
                Remove-PathSafe -Path (Join-Path $profile 'Web Data')
                Remove-PathSafe -Path (Join-Path $profile 'Login Data')
            }
            else {
                Write-Item -Status 'NO CHANGES NEEDED' -Path ("Shared browser DB skipped by scope isolation: {0}" -f (Join-Path $profile 'Cookies')) -Color DarkGray
                Write-Item -Status 'NO CHANGES NEEDED' -Path ("Shared browser DB skipped by scope isolation: {0}" -f (Join-Path $profile 'Network\Cookies')) -Color DarkGray
                Write-Item -Status 'NO CHANGES NEEDED' -Path ("Shared browser DB skipped by scope isolation: {0}" -f (Join-Path $profile 'Web Data')) -Color DarkGray
                Write-Item -Status 'NO CHANGES NEEDED' -Path ("Shared browser DB skipped by scope isolation: {0}" -f (Join-Path $profile 'Login Data')) -Color DarkGray
            }

            # Targeted domain-ish remnants for Claude/OpenAI families.
            Remove-MatchingInDir -BasePath (Join-Path $profile 'Local Storage\leveldb') -Patterns $domainPatterns
            Remove-MatchingInDir -BasePath (Join-Path $profile 'IndexedDB') -Patterns $domainPatterns
            Remove-MatchingInDir -BasePath (Join-Path $profile 'Service Worker') -Patterns $domainPatterns
        }
    }

    # Firefox uses different storage layout.
    $ffProfiles = Join-Path $roam 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $ffProfiles) {
        Get-ChildItem -LiteralPath $ffProfiles -Directory -Force | ForEach-Object {
            Remove-MatchingInDir -BasePath (Join-Path $_.FullName 'storage\default') -Patterns $domainPatterns
            Remove-MatchingInDir -BasePath (Join-Path $_.FullName 'storage\permanent') -Patterns $domainPatterns
        }
    }
    else {
        $script:Skipped++
        Write-Item -Status 'NO CHANGES NEEDED' -Path $ffProfiles -Color DarkGray
    }
}
else {
    # Hard mode removes complete user profile folders for supported browsers.
    # This is the maximum local reset, equivalent to browser fresh-start.
    Write-Step 'Режим HARD: удаление полных папок профилей браузеров (все сессии/логины)'
    Write-Explain 'Полностью удаляет данные профилей в поддерживаемых браузерах.'
    Write-Explain 'Это разлогинит со всех сайтов и удалит сохраненные сессии/cookies/состояние профилей.'
    $browserTargets = @(
        (Join-Path $local 'Google\Chrome\User Data'),
        (Join-Path $local 'Chromium\User Data'),
        (Join-Path $local 'Microsoft\Edge\User Data'),
        (Join-Path $local 'BraveSoftware\Brave-Browser\User Data'),
        (Join-Path $local 'Yandex\YandexBrowser\User Data'),
        (Join-Path $roam  'Mozilla\Firefox\Profiles'),
        (Join-Path $roam  'Opera Software\Opera Stable'),
        (Join-Path $roam  'Opera Software\Opera GX Stable'),
        (Join-Path $local 'Vivaldi\User Data')
    )
    $browserTargets | ForEach-Object { Remove-PathSafe -Path $_ }
}

if ($Mode -eq 'Safe') {
    Write-Step 'Режим SAFE: очистка Credential Manager отключена'
    Write-Explain 'В SAFE не удаляются записи Windows Credential Manager.'
}
elseif (-not $SkipCredentialManager) {
    # Step: remove saved credentials with relevant provider names.
    # This covers Windows credential vault entries that can survive app cleanup.
    Write-Step 'Очистка подходящих записей из Windows Credential Manager'
    Write-Explain 'Удаляет сохраненные Windows-учетные данные с ключами: claude, anthropic, openai, chatgpt.'
    Write-Explain 'Убирает системные секреты, которые могут пережить очистку приложений/браузеров.'
    $raw = cmdkey /list
    $targets = @()

    foreach ($line in $raw) {
        if ($line -match 'Target:\s*(.+)$') {
            $t = $Matches[1].Trim()
            $credPattern = '(?i)claude|anthropic|openai|chatgpt'
            if ($Product -eq 'Claude') { $credPattern = '(?i)claude|anthropic' }
            elseif ($Product -eq 'ChatGPT') { $credPattern = '(?i)openai|chatgpt' }
            if ($t -match $credPattern) {
                $targets += $t
            }
        }
    }

    $targets = $targets | Sort-Object -Unique
    if ($targets.Count -eq 0) {
        Write-Item -Status 'INFO' -Path 'Подходящие credential-записи не найдены' -Color DarkYellow
    }
    else {
        foreach ($t in $targets) {
            if ($DryRun) {
                Write-Item -Status 'DRY RUN (WOULD REMOVE)' -Path ("Удалил бы credential: {0}" -f $t) -Color Yellow
            }
            else {
                cmdkey /delete:$t | Out-Null
                Write-Item -Status 'CRED-DEL' -Path $t -Color Green
            }
        }
    }
}
else {
    Write-Step 'Очистка Credential Manager пропущена по флагу'
}

# Optional machine identity change: rename computer (hostname).
if ($EnableHostnameChange) {
    Write-Step 'Optional machine identity step: rename hostname'
    Write-Explain 'Changes computer name to help services treat this as a new device identity.'
    Write-Explain 'Windows usually requires reboot before the new hostname is fully active.'

    $targetName = $NewHostname
    if ([string]::IsNullOrWhiteSpace($targetName)) {
        $targetName = ("DESKTOP-{0}" -f (Get-Date -Format 'yyMMddHHmm'))
    }

    if ($targetName -notmatch '^[A-Za-z0-9-]{1,15}$') {
        $script:Errors++
        Write-Item -Status 'ERROR' -Path ("Invalid hostname: {0}. Use 1-15 chars: A-Z, 0-9, '-'" -f $targetName) -Color Red
    }
    elseif ($DryRun) {
        Write-Item -Status 'DRY RUN (WOULD RUN)' -Path ("Rename-Computer -NewName {0}" -f $targetName) -Color Yellow
    }
    else {
        if (-not (Test-IsAdmin)) {
            $script:Errors++
            Write-Item -Status 'ERROR' -Path 'Hostname change requires Administrator PowerShell.' -Color Red
        }
        else {
            try {
                Rename-Computer -NewName $targetName -Force -ErrorAction Stop
                Write-Item -Status 'OK' -Path ("Hostname will change to: {0} (after reboot)" -f $targetName) -Color Green
            }
            catch {
                $script:Errors++
                Write-Item -Status 'ERROR' -Path ("Rename failed: {0}" -f $_.Exception.Message) -Color Red
            }
        }
    }
}
}

# Optional network-auth-adjacent cleanup.
# Flush DNS + reset WinHTTP proxy to remove stale network path settings.
if (-not $EnableBasicNetworkReset) {
    Write-Step 'Базовый сетевой сброс отключен'
    Write-Explain 'Чтобы включить, используйте отдельный пункт меню "Сброс сети".'
}
else {
    Write-Step 'Базовый сброс сети'
    Write-Explain 'Очищает DNS-кэш и сбрасывает WinHTTP proxy.'
    if ($DryRun) {
        Write-Item -Status 'DRY RUN (WOULD RUN)' -Path 'ipconfig /flushdns' -Color Yellow
        Write-Item -Status 'DRY RUN (WOULD RUN)' -Path 'netsh winhttp reset proxy' -Color Yellow
    }
    else {
        ipconfig /flushdns | Out-Null
        Write-Item -Status 'OK' -Path 'DNS cache flushed' -Color Green
        netsh winhttp reset proxy | Out-Null
        Write-Item -Status 'OK' -Path 'WinHTTP proxy reset' -Color Green
    }
}

if ($EnableNetworkContourRefresh) {
    Write-Step 'Optional deeper network contour refresh'
    Write-Explain 'Releases/renews IP leases and resets Winsock stack.'
    Write-Explain 'May temporarily drop network and may require reboot for full effect.'
    if ($DryRun) {
        Write-Item -Status 'DRY RUN (WOULD RUN)' -Path 'ipconfig /release' -Color Yellow
        Write-Item -Status 'DRY RUN (WOULD RUN)' -Path 'ipconfig /renew' -Color Yellow
        Write-Item -Status 'DRY RUN (WOULD RUN)' -Path 'netsh winsock reset' -Color Yellow
    }
    else {
        if (-not (Test-IsAdmin)) {
            $script:Errors++
            Write-Item -Status 'ERROR' -Path 'Network contour refresh requires Administrator PowerShell.' -Color Red
        }
        else {
            ipconfig /release | Out-Null
            Write-Item -Status 'OK' -Path 'IP release done' -Color Green
            ipconfig /renew | Out-Null
            Write-Item -Status 'OK' -Path 'IP renew done' -Color Green
            netsh winsock reset | Out-Null
            Write-Item -Status 'OK' -Path 'Winsock reset done (reboot recommended)' -Color Green
        }
    }
}

if ($PrivacyHardening) {
    Write-Step 'Privacy hardening: session environment cleanup'
    Write-Explain 'Removes sensitive env vars from current PowerShell session to reduce accidental leakage.'
    $sensitiveEnv = @(
        'OPENAI_API_KEY','ANTHROPIC_API_KEY','CLAUDE_API_KEY','AZURE_OPENAI_API_KEY',
        'GITHUB_TOKEN','GH_TOKEN','GIT_ASKPASS','SSH_AUTH_SOCK'
    )
    foreach ($name in $sensitiveEnv) {
        if (Test-Path ("Env:{0}" -f $name)) {
            if ($DryRun) {
                Write-Item -Status 'DRY RUN (WOULD REMOVE)' -Path ("env:{0}" -f $name) -Color Yellow
            }
            else {
                Remove-Item ("Env:{0}" -f $name) -ErrorAction SilentlyContinue
                Write-Item -Status 'REMOVED' -Path ("env:{0}" -f $name) -Color Green
            }
        }
        else {
            Write-Item -Status 'NO CHANGES NEEDED' -Path ("env:{0}" -f $name) -Color DarkGray
        }
    }

    Write-Step 'Privacy hardening: global git identity technical values'
    Write-Explain 'Sets neutral machine-level git identity to avoid leaking personal name/email in future commits.'
    $techName = 'machine-user'
    $techEmail = 'machine-user@local.invalid'
    if ($DryRun) {
        Write-Item -Status 'DRY RUN (WOULD RUN)' -Path ("git config --global user.name `"{0}`"" -f $techName) -Color Yellow
        Write-Item -Status 'DRY RUN (WOULD RUN)' -Path ("git config --global user.email `"{0}`"" -f $techEmail) -Color Yellow
    }
    else {
        git config --global user.name $techName
        git config --global user.email $techEmail
        Write-Item -Status 'OK' -Path ("git user.name={0}" -f $techName) -Color Green
        Write-Item -Status 'OK' -Path ("git user.email={0}" -f $techEmail) -Color Green
    }

    Write-Step 'Privacy hardening: git remote audit'
    Write-Explain 'Shows git remotes and marks entries that may contain private hostnames or usernames.'
    $gitDir = Join-Path (Get-Location) '.git'
    if (Test-Path -LiteralPath $gitDir) {
        $remotes = git remote -v
        if (-not $remotes) {
            Write-Item -Status 'INFO' -Path 'No remotes configured in this repository.' -Color DarkYellow
        }
        else {
            foreach ($r in $remotes) {
                if ($r -match '(?i)github\.com|gitlab\.com|bitbucket\.org|ssh://|@') {
                    Write-Item -Status 'CHECK REMOTE' -Path $r -Color Yellow
                }
                else {
                    Write-Item -Status 'REMOTE' -Path $r -Color Gray
                }
            }
            Write-Explain 'Use: git remote set-url <name> <new-url> to replace sensitive remote URLs.'
        }
    }
    else {
        Write-Item -Status 'INFO' -Path 'Current folder is not a git repository; remote audit skipped.' -Color DarkYellow
    }
}

# Final summary for quick diagnostics.
Write-Host ''
Write-Host '============== SUMMARY ==============' -ForegroundColor White
Write-Explain 'Deleted = removed now, No changes needed = already absent or not applicable, Errors = failed actions.'
Write-Host ("Deleted: {0}" -f $script:Deleted) -ForegroundColor Green
Write-Host ("No changes needed: {0}" -f $script:Skipped) -ForegroundColor DarkGray
Write-Host ("Errors : {0}" -f $script:Errors) -ForegroundColor Red
Write-Host '=====================================' -ForegroundColor White
if ($DryRun) {
    Write-Host 'Dry run complete. No changes were made.' -ForegroundColor Cyan
}
else {
    Write-Host 'Done. Reboot Windows before login.' -ForegroundColor Cyan
}
Write-Host ''
Write-Host 'Recommended next step for clean identity:' -ForegroundColor White
Write-Host '  Use a separate Windows user account for Claude work.' -ForegroundColor Cyan
Write-Host '  This is the most reliable way to isolate env vars, app data, browser profiles, and git global settings.' -ForegroundColor DarkCyan
Write-Host ("Full log saved to: {0}" -f $script:LogPath) -ForegroundColor DarkGray
Add-Content -LiteralPath $script:LogPath -Value ''
Add-Content -LiteralPath $script:LogPath -Value ("SUMMARY: Deleted={0}, Skipped={1}, Errors={2}" -f $script:Deleted, $script:Skipped, $script:Errors)
Add-Content -LiteralPath $script:LogPath -Value 'RECOMMENDED: Use a separate Windows user account for Claude work.'

if ($script:InteractiveMenu) {
    Write-Host ''
    Write-Host 'What next?' -ForegroundColor Cyan
    Write-Host '  1) Return to menu'
    Write-Host '  2) Exit'
    $next = Read-Host 'Enter 1-2'

    if ($next -eq '1') {
        Write-Host 'Returning to menu...' -ForegroundColor Cyan
        powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    }
}

<#
.SYNOPSIS
  Runs the Snow Tools checks: a syntax check, then the self-test in an isolated copy.

.DESCRIPTION
  The self-test opens real windows, types into a scratch window and briefly uses the
  clipboard (your clipboard is restored afterwards), so leave the machine alone for about
  a minute. It runs in a temp copy of the project, so your clips, snippets, sticky notes
  and Startup folder are never touched.

  A running Snow Tools would react to the test's key presses and record its test clips in
  your real history, so the run is refused while one is running. Exit it from its tray
  menu, or use -StopLive to stop it for the run and start it again afterwards.

  Exit code: 0 = all passed, 1 = something failed.

.PARAMETER Screenshots
  Copy the window screenshots the test takes into tests\shots (git-ignored).

.PARAMETER Showcase
  Instead of testing, regenerate the README screenshots in docs\ from the real app on
  made-up sample data (tools\showcase.ahk). Leave the machine alone while it runs.

.PARAMETER StopLive
  If Snow Tools is running, exit it for the run and start it again afterwards (also when
  the run fails).

.PARAMETER KeepTemp
  Keep the temp copy (it's printed) instead of deleting it.

.PARAMETER LiveScriptName
  The script name that identifies a running Snow Tools (default hotstrings.ahk). Only
  tests\test-live-guard.ps1 changes it, to exercise the guard with a stand-in script.

.PARAMETER LiveCheckOnly
  Only run the running-instance check (and, with -StopLive, the stop and restart), then
  exit. Used by tests\test-live-guard.ps1.
#>
param(
    [switch]$Screenshots,
    [switch]$Showcase,
    [switch]$StopLive,
    [switch]$KeepTemp,
    [string]$LiveScriptName = 'hotstrings.ahk',
    [switch]$LiveCheckOnly,
    [int]$TimeoutSec = 180
)

. (Join-Path $PSScriptRoot 'live-instances.ps1')

$root = Split-Path $PSScriptRoot -Parent
$ahk = Find-AutoHotkey
if (-not $ahk) { Write-Host "AutoHotkey v2 not found (install it, or set AHK_EXE)"; exit 1 }

# 0. A running Snow Tools: refuse, or (with -StopLive) stop it and start it again at the end.
$live = @(Get-LiveSnowTools -ScriptName $LiveScriptName)
if ($live.Count -gt 0) {
    if (-not $StopLive) {
        $who = ($live | ForEach-Object { "PID $($_.ProcessId): $($_.Script)" }) -join '; '
        Write-Host "FAIL  Snow Tools is running ($who)."
        Write-Host "      The tests send real key presses and use the real clipboard. The running app would"
        Write-Host "      react to them and record the test clips in your history."
        Write-Host "      Exit it from its tray menu and run again, or run with -StopLive to stop it for the"
        Write-Host "      run and start it again afterwards."
        exit 1
    }
    Write-Host "Stopping Snow Tools for the run (it is started again afterwards)..."
    Stop-LiveSnowTools -Instances $live -Ahk $ahk
}

try {
    if ($LiveCheckOnly) { exit 0 }

    # 1. Syntax check (/Validate exits 0 when the script and its includes parse)
    $p = Start-Process $ahk -ArgumentList '/ErrorStdOut', '/Validate', 'hotstrings.ahk' -WorkingDirectory $root -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { Write-Host "FAIL  syntax check (exit $($p.ExitCode))"; exit 1 }
    Write-Host "PASS  syntax check"

    # 2. Isolated copy
    $tmp = Join-Path $env:TEMP ('snowtools-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory $tmp | Out-Null
    foreach ($d in 'lib', 'features') { Copy-Item (Join-Path $root $d) $tmp -Recurse }
    foreach ($f in 'hotstrings.ahk', 'snowflake-32x32.ico') { Copy-Item (Join-Path $root $f) $tmp }
    Copy-Item (Join-Path $PSScriptRoot 'selftest.ahk') $tmp
    Copy-Item (Join-Path $PSScriptRoot 'sample.ahk') $tmp

    # Showcase mode: documentation screenshots of the real app on made-up sample data.
    if ($Showcase) {
        Copy-Item (Join-Path $root 'tools\showcase.ahk') $tmp
        $proc = Start-Process $ahk -ArgumentList 'showcase.ahk' -WorkingDirectory $tmp -PassThru
        if (-not $proc.WaitForExit(120 * 1000)) { $proc.Kill(); Write-Host "FAIL  showcase timed out"; exit 1 }
        $errFile = Join-Path $tmp 'showcase-error.txt'
        if (Test-Path $errFile) { Get-Content $errFile | Write-Host; Write-Host "Temp copy kept at $tmp"; exit 1 }
        $dest = Join-Path $root 'docs'
        New-Item -ItemType Directory $dest -Force | Out-Null
        Copy-Item (Join-Path $tmp 'docs\*.png') $dest -Force
        Write-Host "Screenshots written to $dest (look at each one before committing)"
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # 3. Run it
    $proc = Start-Process $ahk -ArgumentList 'selftest.ahk' -WorkingDirectory $tmp -PassThru
    $timedOut = $false
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        $proc.Kill()
        $timedOut = $true
        Write-Host "FAIL  self-test timed out after $TimeoutSec s"
    }

    # 4. Report
    $results = Join-Path $tmp 'results.txt'
    $failed = $timedOut
    if (Test-Path $results) {
        $lines = Get-Content $results
        $lines | ForEach-Object { Write-Host $_ }
        if ($lines | Where-Object { $_ -like 'FAIL*' }) { $failed = $true }
    } elseif (-not $timedOut) {
        Write-Host "FAIL  self-test produced no results (it likely crashed while loading)"
        $failed = $true
    }

    if ($Screenshots -and (Test-Path (Join-Path $tmp 'shots'))) {
        $dest = Join-Path $PSScriptRoot 'shots'
        New-Item -ItemType Directory $dest -Force | Out-Null
        Copy-Item (Join-Path $tmp 'shots\*') $dest -Force
        Write-Host "Screenshots copied to $dest"
    }

    if ($KeepTemp -or $failed) {
        Write-Host "Temp copy kept at $tmp"
    } else {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($failed) { exit 1 } else { exit 0 }
} finally {
    # Runs on every exit above, including failures: put back what -StopLive stopped.
    if ($live.Count -gt 0 -and $StopLive) {
        Write-Host "Starting Snow Tools again."
        Start-LiveSnowTools -Instances $live
    }
}

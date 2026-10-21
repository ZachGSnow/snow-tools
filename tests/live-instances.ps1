# Helpers for finding, stopping and restarting a running Snow Tools, and for locating
# AutoHotkey. Dot-sourced by run-tests.ps1 and test-live-guard.ps1.

# The AutoHotkey v2 executable: $env:AHK_EXE, then the usual install folders, then PATH.
function Find-AutoHotkey {
    @(
        $env:AHK_EXE,
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
        (Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue).Source
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

# Running AutoHotkey processes whose command line names a script called $ScriptName
# (default hotstrings.ahk, the app's entry point). The test runs start selftest.ahk and
# showcase.ahk, so they never match.
function Get-LiveSnowTools {
    param([string]$ScriptName = 'hotstrings.ahk')
    $pattern = '(?i)([A-Za-z]:\\(?:[^"]*\\)?' + [regex]::Escape($ScriptName) + ')'
    foreach ($p in Get-CimInstance Win32_Process -Filter "Name like 'AutoHotkey%'") {
        if ($p.ProcessId -eq $PID -or -not $p.CommandLine) { continue }
        if ($p.CommandLine -match $pattern) {
            [pscustomobject]@{ ProcessId = $p.ProcessId; Exe = $p.ExecutablePath; Script = $Matches[1] }
        }
    }
}

# Ask each instance to exit through its own Exit command (so it shuts down cleanly), and
# only force it if it has not gone after 8 seconds.
function Stop-LiveSnowTools {
    param($Instances, [string]$Ahk)
    $helper = Join-Path $env:TEMP 'snowtools-exit.ahk'
    Set-Content -Path $helper -Encoding UTF8 -Value @'
#Requires AutoHotkey v2.0
; Asks a running script to exit through its own Exit command (tray menu > Exit).
DetectHiddenWindows(true)
if WinExist(A_Args[1] " ahk_class AutoHotkey")
    PostMessage(0x111, 65307, 0, , A_Args[1] " ahk_class AutoHotkey")    ; WM_COMMAND, ID_FILE_EXIT
'@
    foreach ($i in @($Instances)) {
        if (-not $i) { continue }
        Start-Process $Ahk -ArgumentList ('"' + $helper + '"'), ('"' + $i.Script + '"') -Wait
        $deadline = (Get-Date).AddSeconds(8)
        while ((Get-Process -Id $i.ProcessId -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 200
        }
        if (Get-Process -Id $i.ProcessId -ErrorAction SilentlyContinue) {
            Stop-Process -Id $i.ProcessId -Force
        }
    }
    Remove-Item $helper -ErrorAction SilentlyContinue
}

# Start the instances again, each from its own folder.
function Start-LiveSnowTools {
    param($Instances)
    foreach ($i in @($Instances)) {
        if (-not $i) { continue }
        Start-Process $i.Exe -ArgumentList ('"' + $i.Script + '"') -WorkingDirectory (Split-Path $i.Script -Parent)
    }
}

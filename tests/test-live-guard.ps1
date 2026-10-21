<#
.SYNOPSIS
  Checks the running-instance guard in run-tests.ps1 with a stand-in script, never with the
  real app: it must refuse while an instance runs, and -StopLive must stop it and start it
  again. Quick (a few seconds). Exit code: 0 = all passed, 1 = something failed.
#>
. (Join-Path $PSScriptRoot 'live-instances.ps1')

$ahk = Find-AutoHotkey
if (-not $ahk) { Write-Host "AutoHotkey v2 not found (install it, or set AHK_EXE)"; exit 1 }
$runner = Join-Path $PSScriptRoot 'run-tests.ps1'
$name = 'snowtools-standin.ahk'

$tmp = Join-Path $env:TEMP ('snowtools-guard-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory $tmp | Out-Null
$standIn = Join-Path $tmp $name
Set-Content -Path $standIn -Value "#Requires AutoHotkey v2.0`nPersistent"

$script:failures = 0
function Check($label, $ok, $detail = '') {
    if ($ok) { Write-Host "PASS  $label" } else { Write-Host "FAIL  $label $detail"; $script:failures++ }
}
function WaitFor($fn, $seconds = 10) {
    $end = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $end) { if (& $fn) { return $true }; Start-Sleep -Milliseconds 200 }
    return $false
}
function RunRunner($extra) {
    $out = & pwsh -NoProfile -File $runner -LiveScriptName $name -LiveCheckOnly @extra 2>&1 | Out-String
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

try {
    # nothing running: the runner goes ahead and starts nothing
    $r = RunRunner @()
    Check 'with nothing running the check passes' ($r.Code -eq 0 -and @(Get-LiveSnowTools -ScriptName $name).Count -eq 0) $r.Out

    $first = Start-Process $ahk -ArgumentList ('"' + $standIn + '"') -PassThru
    Check 'a running instance is found by script name' (WaitFor { @(Get-LiveSnowTools -ScriptName $name).Count -eq 1 })
    Check 'a different script name does not match' (@(Get-LiveSnowTools -ScriptName 'something-else.ahk').Count -eq 0)

    $r = RunRunner @()
    Check 'the runner refuses while an instance is running and leaves it alone' `
        ($r.Code -eq 1 -and $r.Out -match 'Snow Tools is running' -and $r.Out -match '-StopLive' -and (Get-Process -Id $first.Id -ErrorAction SilentlyContinue)) $r.Out

    $r = RunRunner @('-StopLive')
    $again = $null
    WaitFor { $script:again = @(Get-LiveSnowTools -ScriptName $name); $script:again.Count -eq 1 } | Out-Null
    Check '-StopLive stops the instance and starts it again' `
        ($r.Code -eq 0 -and $again.Count -eq 1 -and $again[0].ProcessId -ne $first.Id -and -not (Get-Process -Id $first.Id -ErrorAction SilentlyContinue)) $r.Out
    Check 'it is started again from its own script' ($again.Count -eq 1 -and $again[0].Script -eq $standIn)
} finally {
    foreach ($i in @(Get-LiveSnowTools -ScriptName $name)) { Stop-Process -Id $i.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failures -gt 0) { exit 1 } else { exit 0 }

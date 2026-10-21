#Requires AutoHotkey v2.0
#SingleInstance Off
; Documentation screenshots: runs the real app on made-up sample data and saves PNGs to
; docs\ in the temp copy. Do NOT run this directly: tests\run-tests.ps1 -Showcase copies the
; project to a temp folder (so your own clips and snippets are never used), puts this file
; and tests\sample.ahk at its root, runs it there and copies the images back to docs\.
#Include hotstrings.ahk
#Include sample.ahk

OnError(ShowFatal, 1)
ShowFatal(err, mode) {
    FileAppend("FATAL  " err.Message " @ " err.File ":" err.Line "`n", A_ScriptDir "\showcase-error.txt", "UTF-8")
    ExitApp
}

global ShowOut := A_ScriptDir "\docs"
DirCreate(ShowOut)

Snap(win, name) {
    global ShowOut
    Sleep(500)
    WinGetPos(&x, &y, &w, &h, win.g)
    GdipCaptureRect(x, y, w, h, ShowOut "\" name ".png")
}

Ago(minutes) {
    return FormatTime(DateAdd(A_Now, -minutes, "Minutes"), "yyyyMMddHHmmss")
}

savedClip := ClipboardAll()

; --- sample clips: oldest first, fictional people and hosts only
p := ClipAddText("Thanks for reaching out. I'll have an update for you by end of day.", Ago(600))
ClipTogglePin({kind: "txt", e: p})
ClipAddText("https://learn.microsoft.com/powershell/scripting/overview", Ago(240))
ClipAddText("Get-ADUser -Filter 'Enabled -eq $false' | Select-Object Name, LastLogonDate", Ago(180))
ClipAddText("fileserver01.contoso.com  192.0.2.14", Ago(120))
ClipAddText("Reset MFA for jordan.lee@contoso.com (ticket 48213)", Ago(75))
note := "CALL: Printer queue stuck`nCLIENT: Northwind Traders`nSTART: 0905 | END: 0950 | TOTAL:`n"
    . "SUMMARY: Cleared the spooler and reinstalled the driver.`nNEXT: confirm with the user tomorrow.`nSTATUS: PENDING"
ClipAddText(note, Ago(20))
SampleImage(ShowOut "\sample1.png", 320, 180, "SAMPLE IMAGE")
GdipPngToClipboard(ShowOut "\sample1.png")
Sleep(300)
ClipAddImageFromClipboard(Ago(300))
FileDelete(ShowOut "\sample1.png")

; --- HUD
HudToggle()
Snap(HudWin, "hud")
HudWin.Hide()

; --- clipboard window: the time-block note selected, then the image
ClipToggle()
Sleep(300)
ClipSearch.Focus()
Loop ClipItems.Length {
    if (ClipItems[A_Index].kind = "txt" && InStr(ClipItems[A_Index].e.text, "CALL: Printer")) {
        ClipList.Modify(A_Index, "Select Focus Vis")
        break
    }
}
ClipMove(0)
Snap(ClipUI, "clips")
Loop ClipItems.Length {
    if (ClipItems[A_Index].kind = "img") {
        ClipList.Modify(A_Index, "Select Focus Vis")
        break
    }
}
ClipMove(0)
Snap(ClipUI, "clips-image")
ClipUI.Hide()

; --- snippets editor with the call-note template selected
SnippetsToggle()
Loop Snippets.Length {
    if (Snippets[A_Index].trigger = "callnote") {
        SnipRefreshList(A_Index)
        break
    }
}
Snap(SnipWin, "snippets")
SnipWin.Hide()

; --- settings
SettingsToggle()
Snap(SettingsWin, "settings")
SettingsWin.Hide()
SettingsWipeDialog()
Snap(WipeWin, "delete-confirm")
WipeWin.Hide()

; --- hotkeys window with one shortcut changed
HotkeyRebind("note", "^!n")
HotkeysToggle()
HkList.Modify(3, "Select Focus Vis")
Snap(HkWin, "hotkeys")
HotkeysClose()
HotkeysResetAll()

; --- import dialog: a made-up export from a colleague
sample := A_ScriptDir "\colleague-settings.txt"
FileOpen(sample, "w", "UTF-8").Write("# Snow Tools settings`nformat = 1`n[prefs]`nclips.autodecimal = 0`nclips.skipsensitive = 1`n"
    . "[hotkeys]`npad = ^!n`n"
    . "[snippets]`nzem = jordan.lee@contoso.com`nzph = 555-0100`nsignoff = Thanks,\nJordan Lee\nContoso Service Desk`n"
    . "zip = 192.0.2.14`n")
TransferImportStart(sample)
Snap(TransferWin, "import-settings")
TransferWin.Hide()
FileDelete(sample)

; --- calculator
CalcToggle()
CalcInput.Value := "9:30-17:05"
CalcRun()
Snap(CalcWin, "calc")
CalcClose()

if (savedClip != "")
    try A_Clipboard := savedClip
ExitApp

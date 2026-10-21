#Requires AutoHotkey v2.0
#SingleInstance Off
; Snow Tools self-test. Do NOT run this directly: tests\run-tests.ps1 copies the project
; to a temp folder (so live data, stickies and the real Startup folder are never touched),
; puts this file at the root of the copy and runs it there. Results go to results.txt.
#Include hotstrings.ahk
#Include sample.ahk

; The app's error handler swallows errors (by design); in a test a crash must fail fast.
OnError(TestFatal, 1)
TestFatal(err, mode) {
    FileAppend("FATAL  " err.Message " @ " err.File ":" err.Line "`n", A_ScriptDir "\results.txt", "UTF-8")
    ExitApp
}

global TestResults := []
global TestShots := A_ScriptDir "\shots"
DirCreate(TestShots)
global TestSavedClip := ""
Loop 20 {    ; the clipboard can be briefly locked by another process
    try {
        TestSavedClip := ClipboardAll()
        break
    } catch {
        Sleep(150)
    }
}

Check(name, ok, detail := "") {
    TestResults.Push((ok ? "PASS  " : "FAIL  ") name (detail != "" ? "  [" StrReplace(StrReplace(detail, "`r", ""), "`n", " / ") "]" : ""))
}

Group(name, fn) {
    try {
        fn()
    } catch as err {
        Check(name " (group crashed)", false, err.Message " @ " err.File ":" err.Line)
    }
}

Snap(win, name) {
    Sleep(350)
    try {
        WinGetPos(&x, &y, &w, &h, win.g)
        GdipCaptureRect(x, y, w, h, TestShots "\" name ".png")
    }
}

; Puts a distinct image (by width) on the clipboard, then stores it.
AddTestImage(width) {
    SampleImage(TestShots "\img" width ".png", width, 120, "TEST " width)
    GdipPngToClipboard(TestShots "\img" width ".png")
    Sleep(250)
    return ClipAddImageFromClipboard()
}

; Types into a scratch window at send level 1 so the script's own hotstrings react.
global TypeGui := ""
global TypeEdit := ""
TypeBegin() {
    global TypeGui, TypeEdit
    TypeGui := Gui("+AlwaysOnTop", "snowtools typing test")
    TypeEdit := TypeGui.Add("Edit", "w700 r12 Multi")
    TypeGui.Show("x120 y120")
    WinActivate("snowtools typing test")
    Sleep(400)
    TypeEdit.Focus()
}
TypeIn(keys) {
    global TypeEdit
    TypeEdit.Value := ""
    SendEvent("{Right}")    ; arrow keys reset the hotstring recognizer's typed-text buffer
    Sleep(80)
    SendEvent(keys)
    Sleep(350)
    return StrReplace(TypeEdit.Value, "`r`n", "`n")
}
TypeEnd() {
    global TypeGui
    TypeGui.Destroy()
}

; --------------------------------------------------------------------------
Group("store", GroupStore)
GroupStore() {
    e1 := AddTestImage(201)
    e2 := AddTestImage(202)
    Check("image capture stores PNG", e1 && FileExist(ClipImagePath(e1)) && e1.w = 201 && e1.h = 120)
    n := ClipImages.Length
    ClipAddImageFromClipboard()    ; same image again -> bump, not a new entry
    Check("duplicate image is bumped, not duplicated", ClipImages.Length = n)

    tricky := "x`n@3|20260101000000|1`nabc`nCRLF line`r`nend"
    ClipAddText("hello world")
    ClipAddText(tricky)
    p := ClipAddText("pin me")
    ClipTogglePin({kind: "txt", e: p})
    ClipAddText("hello world")
    Check("text dedupe + bump", ClipTexts.Length = 3 && ClipTexts[ClipTexts.Length].text = "hello world")
    before := ClipTexts.Length
    ClipLoadTexts()
    ClipLoadImages()
    Check("journal round-trips (tricky text, count)", ClipTexts.Length = before && ClipTextMap.Has(tricky))
    Check("pin survives reload", ClipTextMap["pin me"].pin = 1 && ClipTextPins = 1)

    ; text cap (pinned entries are exempt)
    global CLIP_MAX_TEXT
    old := CLIP_MAX_TEXT
    CLIP_MAX_TEXT := 20
    Loop 40
        ClipAddText("cap test " A_Index)
    Check("text cap enforced, pinned kept", ClipTexts.Length = 21 && ClipTextMap.Has("pin me"), "len=" ClipTexts.Length)
    CLIP_MAX_TEXT := old

    ; image cap
    global CLIP_MAX_IMG
    oldImg := CLIP_MAX_IMG
    CLIP_MAX_IMG := 2
    AddTestImage(203)
    AddTestImage(204)
    Check("image cap enforced", ClipImages.Length = 2, "len=" ClipImages.Length)
    files := 0
    Loop Files ClipImgDir "\*.png"
        files++
    Check("evicted image files are deleted", files = 2, "files=" files)
    CLIP_MAX_IMG := oldImg
}

Group("clips window", GroupClipUI)
GroupClipUI() {
    ClipToggle()
    Sleep(300)
    Check("clips list shows every clip", ClipItems.Length = ClipTexts.Length + ClipImages.Length, ClipItems.Length)
    Snap(ClipUI, "clips_text")
    Loop ClipItems.Length {
        if (ClipItems[A_Index].kind = "img") {
            ClipList.Modify(A_Index, "Select Focus Vis")
            break
        }
    }
    ClipMove(0)
    Check("image row shows the picture pane", ClipPreviewPic.Visible && !ClipPreviewEdit.Visible)
    Snap(ClipUI, "clips_image")
    ClipSearch.Value := "pin me"
    ClipRefresh()
    Check("search filters the list", ClipItems.Length = 1)
    ClipUI.Hide()
}

; Puts text on the clipboard the way another program would, optionally with a privacy flag:
; flag "exclude" = ExcludeClipboardContentFromMonitorProcessing (password managers),
; flag "history0" = CanIncludeInClipboardHistory with the value 0, "" = no flag.
TestSetFlaggedClip(text, flag) {
    CF_UNICODETEXT := 13
    GlobalAlloc := (n) => DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", n, "Ptr")    ; GMEM_MOVEABLE | ZEROINIT
    DllCall("OpenClipboard", "Ptr", A_ScriptHwnd)
    DllCall("EmptyClipboard")
    size := (StrLen(text) + 1) * 2
    h := GlobalAlloc(size)
    p := DllCall("GlobalLock", "Ptr", h, "Ptr")
    StrPut(text, p, "UTF-16")
    DllCall("GlobalUnlock", "Ptr", h)
    DllCall("SetClipboardData", "UInt", CF_UNICODETEXT, "Ptr", h)
    if (flag != "") {
        name := (flag = "exclude") ? "ExcludeClipboardContentFromMonitorProcessing" : "CanIncludeInClipboardHistory"
        fmt := DllCall("RegisterClipboardFormat", "Str", name, "UInt")
        hf := GlobalAlloc(4)
        pf := DllCall("GlobalLock", "Ptr", hf, "Ptr")
        NumPut("UInt", (flag = "exclude") ? 1 : 0, pf)
        DllCall("GlobalUnlock", "Ptr", hf)
        DllCall("SetClipboardData", "UInt", fmt, "Ptr", hf)
    }
    DllCall("CloseClipboard")
    Sleep(600)    ; let OnClipboardChange run
}

Group("clipboard privacy", GroupPrivacy)
GroupPrivacy() {
    TestSetFlaggedClip("visible-clip-456", "")
    Check("an unflagged copy is recorded", ClipTextMap.Has("visible-clip-456"))
    TestSetFlaggedClip("secret-exclude-123", "exclude")
    Check("a password-manager copy is not recorded", !ClipTextMap.Has("secret-exclude-123"))
    TestSetFlaggedClip("secret-history0-123", "history0")
    Check("a CanIncludeInClipboardHistory=0 copy is not recorded", !ClipTextMap.Has("secret-history0-123"))
    global ClipPaused
    ClipTogglePause()
    TestSetFlaggedClip("while-paused-789", "")
    Check("nothing is recorded while paused", !ClipTextMap.Has("while-paused-789"))
    ClipTogglePause()
    TestSetFlaggedClip("after-resume-789", "")
    Check("recording resumes after a pause", ClipTextMap.Has("after-resume-789"))
}

Group("calc", GroupCalc)
GroupCalc() {
    CalcToggle()
    for pair in [["1100-1115", "0.25"], ["25-2*3", "19"], ["9:30-17:05", "7.58"], ["2300-0100", "2.00"], ["(1+2)*3", "9"]] {
        CalcInput.Value := pair[1]
        CalcRun()
        Check("calc " pair[1], CalcResult.Value = pair[2], CalcResult.Value)
    }
    CalcInput.Value := "1/0"
    CalcRun()
    Check("calc division by zero is an error", InStr(CalcResult.Value, "Error"))
    CalcInput.Value := "9:30-17:05"
    CalcRun()
    Snap(CalcWin, "calc")
    CalcClose()
    Check("calc copies result on close", A_Clipboard = "7.58", A_Clipboard)
}

Group("hotstrings", GroupHotstrings)
GroupHotstrings() {
    SendLevel(1)
    TypeBegin()
    Check("zem expands", TypeIn("zem") = "you@example.com")
    Check(":ty expands", TypeIn(":ty") = "Thanks for reaching out.")
    Check(":TY keeps case", TypeIn(":TY") = "Thanks for reaching out.")
    Check("ty without colon does not expand", TypeIn("ty") = "ty")
    Check("cdate expands", TypeIn("cdate") = FormatTime(, "yyyy-MM-dd"))
    Check("tdate expands", TypeIn("tdate") = FormatTime(DateAdd(A_Now, 1, "days"), "yyyy-MM-dd"))
    Check("ctime expands", RegExMatch(TypeIn("ctime"), "^\d\d:\d\d$"))
    got := TypeIn("callnote")
    Check("callnote expands the template", InStr(got, "CALL: `nCLIENT:") = 1 && InStr(got, "STATUS: PENDING"), SubStr(got, 1, 30))
    start := SendMessage(0xB0, 0, 0, TypeEdit.Hwnd) & 0xFFFF    ; EM_GETSEL: low word = selection start
    Check("callnote leaves the caret after 'CALL: '", start = 6, "caret=" start)
    TypeEnd()
}

Group("snippets", GroupSnippets)
GroupSnippets() {
    s := "a\b`n`tc\n end\\"
    Check("snippet encode/decode round-trips", SnipDecode(SnipEncode(s)) = s)
    Check("trigger validation", SnipValidTrigger(":ty") && !SnipValidTrigger("a b") && !SnipValidTrigger("a=b") && !SnipValidTrigger(""))

    base := Snippets.Length
    Check("default snippets were seeded", base = 7, base)
    SnippetsToggle()
    SnipNew()
    SnipTrigger.Value := "tst1"
    SnipText.Value := "hello`r`nworld {date}"
    ok := SnipSave()
    Check("editor saves a new snippet", ok && Snippets.Length = base + 1, Snippets.Length)
    Check("snippets file has the entry", InStr(FileRead(SnipPath, "UTF-8"), "tst1 = hello\nworld {date}"))
    Snap(SnipWin, "snippets")
    SnipWin.Hide()

    SendLevel(1)
    TypeBegin()
    Check("new snippet expands without reload", TypeIn("tst1") = "hello`nworld " FormatTime(, "yyyy-MM-dd"))
    TypeEnd()

    n := Snippets.Length
    SnipNew()
    SnipTrigger.Value := "TST1"
    SnipText.Value := "dup"
    Check("duplicate trigger (any case) rejected", !SnipSave() && Snippets.Length = n && SnipWarn.Value != "")
    SnipNew()
    SnipTrigger.Value := "z"
    SnipText.Value := "prefix"
    SnipOnTriggerChange()
    Check("prefix conflict warns", InStr(SnipWarn.Value, "start of"), SnipWarn.Value)
    global SnipReserved
    SnipReserved.Push("zdemo")
    SnipTrigger.Value := "ZDemo"
    SnipOnTriggerChange()
    Check("built-in trigger warns", InStr(SnipWarn.Value, "built-in"), SnipWarn.Value)

    ; edit the existing snippet, then delete it
    SnipRefreshList(Snippets.Length)
    SnipText.Value := "changed"
    SnipSave()
    Check("editing updates the text", Snippets[Snippets.Length].text = "changed")
    global SnipAskConfirm
    SnipAskConfirm := false
    SnipDelete()
    SnipAskConfirm := true
    Check("delete removes it from the list and file", Snippets.Length = base && !InStr(FileRead(SnipPath, "UTF-8"), "tst1"))
    SendLevel(1)
    TypeBegin()
    Check("deleted snippet no longer expands", TypeIn("tst1") = "tst1")
    TypeEnd()
    Check("HUD rebuilds after snippet changes", HudWin = "")
}

Group("hud", GroupHud)
GroupHud() {
    HudToggle()
    Check("HUD builds and shows", HudWin != "" && HudWin.IsVisible())
    found := 0
    for r in SnowRegistry
        if (r.key = "zem" || r.key = "Alt+Y" || r.key = "Ctrl+Alt+P")
            found++
    Check("registry lists snippets and hotkeys", found = 3, found)
    Snap(HudWin, "hud")
    HudWin.Hide()
}

Group("notes", GroupNotes)
GroupNotes() {
    PadToggle()
    PadEdit.Value := "pad test`r`nsecond line & more"
    PadSave(true)
    Check("snow pad saves text", InStr(FileRead(PadPath, "UTF-8"), "second line & more"))
    Snap(PadWin, "pad")
    PadClose()

    ; a window saved on a monitor that no longer exists must reopen on-screen
    posFile := FileOpen(PadPosPath, "w")
    posFile.Write("99999,99999,500,300")
    posFile.Close()
    PadToggle()
    WinGetPos(&x, &y, &w, &h, PadWin.g)
    Check("snow pad position is clamped onto the screen", x >= -10 && y >= -10 && x < A_ScreenWidth && y < A_ScreenHeight, x "," y)
    PadClose()

    StickyCreate(901, 99999, -99999)
    WinGetPos(&sx, &sy, , , StickyNotes[901].win.g)
    Check("sticky position is clamped onto the screen", sx >= -10 && sy >= -10 && sx < A_ScreenWidth && sy < A_ScreenHeight, sx "," sy)
    StickyClose(901)
    Check("empty sticky closes without prompting", !StickyNotes.Has(901))
}

Group("clamp", GroupClamp)
GroupClamp() {
    x := 99999, y := 99999
    ClampToScreen(&x, &y, 300, 200)
    Check("clamp pulls far bottom-right back", x < A_ScreenWidth && y < A_ScreenHeight && x >= 0 && y >= 0, x "," y)
    x := -5000, y := -5000
    ClampToScreen(&x, &y, 300, 200)
    Check("clamp pulls far top-left back", x >= 0 && y >= 0, x "," y)
    x := 100, y := 100
    ClampToScreen(&x, &y, 300, 200)
    Check("clamp leaves a visible window alone", x = 100 && y = 100, x "," y)
}

Group("log and tray", GroupLogTray)
GroupLogTray() {
    SnowLog("selftest marker 12345")
    Check("log writes entries", InStr(FileRead(SnowLogPath, "UTF-8"), "selftest marker 12345"))
    r := SnowOnError(Error("boom-test", -1), "Return")
    Check("error handler logs and suppresses the dialog", r = 1 && InStr(FileRead(SnowLogPath, "UTF-8"), "boom-test"))
    big := SnowLogPath ".big"
    f := FileOpen(SnowLogPath, "w", "UTF-8")
    f.Write(SnowRepeat("0123456789abcdef`n", 80000))
    f.Close()
    SnowLog("after trim")
    Check("log is trimmed when over the cap", FileGetSize(SnowLogPath) < SNOW_LOG_MAX, FileGetSize(SnowLogPath))
    ok := true
    try {
        A_TrayMenu.Check("Run at startup")
        A_TrayMenu.Uncheck("Run at startup")
    } catch {
        ok := false
    }
    Check("tray menu has the expected items", ok)
}

Group("performance", GroupPerf)
GroupPerf() {
    t0 := A_TickCount
    Loop 10050
        ClipAddText("perf clip number " A_Index " " SnowRepeat("lorem ipsum ", Mod(A_Index, 20)))
    t1 := A_TickCount - t0
    Check("add 10,000 clips in under 10 s", t1 < 10000, t1 " ms")
    Check("text cap holds at 10,000 (+pinned)", ClipTexts.Length <= 10001, ClipTexts.Length)
    t0 := A_TickCount
    ClipLoadTexts()
    Check("reload 10,000 clips in under 2 s", A_TickCount - t0 < 2000, (A_TickCount - t0) " ms")
    ClipToggle()
    t0 := A_TickCount
    ClipRefresh()
    Check("populate the list in under 2 s", A_TickCount - t0 < 2000, (A_TickCount - t0) " ms")
    Snap(ClipUI, "clips_10k")
    ClipUI.Hide()
}

; Answers the next Snow Tools MsgBox by clicking a button: "Button1" = Yes, "Button2" = No.
TestAnswer(button) {
    SetTimer(TestAnswerNow.Bind(button), -150)
}
TestAnswerNow(button) {
    title := "*  Snow Tools  * ahk_class #32770"
    if WinWait(title, , 5)
        ControlClick(button, title)
}

Group("settings: preferences", GroupPrefs)
GroupPrefs() {
    Check("skip-sensitive defaults to on", SnowPrefGet("clips.skipsensitive") = "1")
    SnowPrefSet("clips.autodecimal", "0")
    Check("a preference is written to prefs.ini", IniRead(SnowPrefsPath, "clips", "autodecimal", "?") = "0")
    SnowPrefSet("clips.autodecimal", "1")
    threw := false
    try SnowPrefSet("clips.nosuchthing", "1")
    catch
        threw := true
    Check("an unknown preference name is rejected", threw)
}

Group("settings: password guard toggle", GroupGuardToggle)
GroupGuardToggle() {
    SettingsToggle()
    Check("settings window opens with the guard shown as on", SettingsWin.IsVisible() && InStr(SettingsChecks[1].ctrl.Value, "[x]") = 1)
    Snap(SettingsWin, "settings")
    TestAnswer("Button2")
    SettingsSetSensitive(false)
    Check("declining the warning keeps the guard on", SnowPrefGet("clips.skipsensitive") = "1")
    TestAnswer("Button1")
    SettingsSetSensitive(false)
    SettingsRefresh()
    Check("accepting the warning turns the guard off", SnowPrefGet("clips.skipsensitive") = "0"
        && InStr(SettingsChecks[1].ctrl.Value, "[ ]") = 1 && InStr(SettingsSensNote.Value, "OFF") = 1)
    TestSetFlaggedClip("secret-guard-off-123", "exclude")
    Check("with the guard off a flagged copy is recorded", ClipTextMap.Has("secret-guard-off-123"))
    SettingsSetSensitive(true)
    SettingsRefresh()
    TestSetFlaggedClip("secret-guard-on-456", "exclude")
    Check("turning the guard back on needs no confirmation and skips flagged copies"
        , SnowPrefGet("clips.skipsensitive") = "1" && !ClipTextMap.Has("secret-guard-on-456"))
    SettingsWin.Hide()
}

Group("settings: clear clipboard history", GroupClearHistory)
GroupClearHistory() {
    p := ClipAddText("pinned before clear")
    ClipTogglePin({kind: "txt", e: p})
    AddTestImage(205)
    Check("the store has something to clear", ClipTexts.Length > 0 && ClipImages.Length > 0)
    TestAnswer("Button2")
    SettingsClearHistory()
    Check("declining keeps the history", ClipTexts.Length > 0 && ClipImages.Length > 0 && FileExist(ClipTextPath))
    TestAnswer("Button1")
    SettingsClearHistory()
    imgs := 0
    Loop Files ClipImgDir "\*.*"
        imgs++
    Check("accepting deletes every clip, pinned too", ClipTexts.Length = 0 && ClipTextMap.Count = 0 && ClipTextPins = 0)
    Check("accepting deletes every image file and the index", ClipImages.Length = 0 && ClipImgPins = 0 && imgs = 0 && !FileExist(ClipImgIdxPath))
    Check("the journal file is gone", !FileExist(ClipTextPath))
    ClipLoadTexts()
    ClipLoadImages()
    Check("nothing comes back when the store is reloaded from disk", ClipTexts.Length = 0 && ClipImages.Length = 0)
    ClipToggle()
    Check("the open clips list is empty afterwards", ClipItems.Length = 0)
    ClipUI.Hide()
    e := ClipAddText("recorded after clear")
    ClipLoadTexts()
    Check("the store works again after a clear", e != "" && ClipTexts.Length = 1 && ClipTextMap.Has("recorded after clear"))
}

Group("settings: delete all data", GroupDeleteAll)
GroupDeleteAll() {
    Check("only DELETE is accepted", SettingsWipeTypedOk("DELETE") && SettingsWipeTypedOk(" DELETE ")
        && !SettingsWipeTypedOk("delete") && !SettingsWipeTypedOk("DELET") && !SettingsWipeTypedOk("DELETE ALL") && !SettingsWipeTypedOk(""))
    PadToggle()
    PadEdit.Value := "pad secret text"
    PadSave(true)
    PadClose()
    StickyCreate(902, 300, 300, "sticky secret text")
    StickySaveAll()
    SnowLog("wipe test marker")
    ClipAddText("clip before wipe")
    stickyFiles := 0
    Loop Files StickyDir "*.txt"
        stickyFiles++
    Check("data exists before the wipe", FileExist(PadPath) && stickyFiles = 1 && FileExist(SnowLogPath) && ClipTexts.Length > 0, stickyFiles)

    SettingsDeleteAll()
    Check("the confirmation window opens and deletes nothing yet", WipeWin.IsVisible() && FileExist(PadPath) && ClipTexts.Length > 0)
    Snap(WipeWin, "wipe")
    WipeEdit.Value := "delete"
    SettingsWipeAccept()
    Check("wrong text deletes nothing and says so", WipeWin.IsVisible() && FileExist(PadPath) && ClipTexts.Length > 0 && WipeMsg.Value != "")
    WipeEdit.Value := "DELETE"
    SettingsWipeAccept()
    stickyFiles := 0
    Loop Files StickyDir "*.txt"
        stickyFiles++
    Check("typing DELETE closes the window", !WipeWin.IsVisible())
    Check("clips and images are gone", ClipTexts.Length = 0 && ClipImages.Length = 0 && !FileExist(ClipTextPath))
    Check("pad and sticky notes are gone", !FileExist(PadPath) && !FileExist(PadPosPath) && stickyFiles = 0 && StickyNotes.Count = 0)
    Check("the error log is gone", !FileExist(SnowLogPath))
    Check("snippets and preferences are kept", FileExist(SnipPath) && Snippets.Length > 0 && SnowPrefGet("clips.skipsensitive") = "1")
    PadToggle()
    Check("the pad reopens empty", PadEdit.Value = "")
    PadClose()
}

Group("settings: reset", GroupReset)
GroupReset() {
    ClipSetAutoDecimal(false)
    Snippets.Push({trigger: "zzreset", text: "x"})
    SnippetsSave()
    SnippetsApply()
    TestAnswer("Button2")
    SettingsReset()
    Check("declining keeps the changes", !ClipAutoDecimal && Snippets.Length = 8)
    TestAnswer("Button1")
    SettingsReset()
    Check("preferences return to the defaults", ClipAutoDecimal && SnowPrefGet("clips.autodecimal") = "1" && !FileExist(SnowPrefsPath))
    Check("snippets return to the built-in set", Snippets.Length = 7 && !InStr(FileRead(SnipPath, "UTF-8"), "zzreset"))
    SendLevel(1)
    TypeBegin()
    Check("a removed snippet stops expanding and a default still works", TypeIn("zzreset") = "zzreset" && TypeIn("zem") = "you@example.com")
    TypeEnd()
}

; --------------------------------------------------------------------------
if (TestSavedClip != "")
    try A_Clipboard := TestSavedClip
out := ""
fails := 0
for line in TestResults {
    out .= line "`n"
    if (SubStr(line, 1, 4) = "FAIL")
        fails++
}
out .= "`n" (TestResults.Length - fails) " passed" (fails > 0 ? ", " fails " failed" : "") "`n"
FileAppend(out, A_ScriptDir "\results.txt", "UTF-8")
ExitApp

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

Group("transfer: export and parse", GroupTransferParse)
GroupTransferParse() {
    text := TransferExportText()
    Check("an export has the header, preferences and snippets", InStr(text, "format = 1") && InStr(text, "[prefs]")
        && InStr(text, "clips.skipsensitive = 1") && InStr(text, "[snippets]") && InStr(text, "zem = you@example.com"))
    p := TransferParse(text)
    Check("an export parses back to the same snippets and preferences", p.ok && p.snippets.Length = Snippets.Length
        && p.prefs["clips.skipsensitive"] = "1" && p.ignored.Length = 0 && p.snippets[7].text == Snippets[7].text, p.error)
    Check("CRLF line endings parse the same", TransferParse(StrReplace(text, "`n", "`r`n")).snippets.Length = Snippets.Length)
    Check("an empty file is rejected", !TransferParse("").ok)
    Check("plain text without a format line is rejected", !TransferParse("hello world`n[snippets]`nzz = x`n").ok)
    n := TransferParse("format = 2`n[prefs]`n")
    Check("a newer format is rejected with a clear message", !n.ok && InStr(n.error, "newer"), n.error)
    Check("an oversized file is rejected", !TransferParse(SnowRepeat("x", 1048577)).ok)
    odd := "format = 1`n[prefs]`nclips.skipsensitive = 0`nbogus.pref = 1`nclips.autodecimal = maybe`n"
        . "[snippets]`nok1 = hello`nbad trigger = x`nok1 = dup`nline without equals`n[hotkeys]`nfoo = bar`n"
    q := TransferParse(odd)
    Check("unknown or invalid entries are skipped and listed", q.ok && q.prefs.Count = 1 && q.prefs["clips.skipsensitive"] = "0"
        && q.snippets.Length = 1 && q.snippets[1].text = "hello" && q.ignored.Length = 6, q.ignored.Length)
    Check("parsing changes nothing", Snippets.Length = 7 && SnowPrefGet("clips.skipsensitive") = "1")
}

Group("transfer: plan and apply", GroupTransferApply)
GroupTransferApply() {
    file := "format = 1`n[prefs]`nclips.autodecimal = 0`nclips.skipsensitive = 0`n"
        . "[snippets]`nzem = new@example.com`nzph = 555-0100`nzimp = imported {date}`n"
    plan := TransferPlan(TransferParse(file))
    risky := 0
    for pr in plan.prefs
        if pr.risky
            risky++
    Check("the plan counts new, changed and identical snippets", plan.added = 1 && plan.changed = 1 && plan.same = 1 && plan.removed = 5
        , plan.added "," plan.changed "," plan.same "," plan.removed)
    Check("only the privacy-lowering preference is flagged risky", plan.prefs.Length = 2 && risky = 1)

    r := TransferApply(plan, "merge", false)
    Check("merge applies the safe preference and holds back the risky one", r.ok && !ClipAutoDecimal
        && SnowPrefGet("clips.skipsensitive") = "1" && InStr(r.message, "skipped"), r.message)
    Check("merge adds and updates snippets and keeps the rest", Snippets.Length = 8 && Snippets[1].text = "new@example.com"
        && FileRead(SnipPath, "UTF-8") ~= "callnote" && InStr(FileRead(SnipPath, "UTF-8"), "zimp = imported {date}"))
    SendLevel(1)
    TypeBegin()
    Check("imported snippets expand without a reload", TypeIn("zimp") = "imported " FormatTime(, "yyyy-MM-dd") && TypeIn("zem") = "new@example.com")
    TypeEnd()
    backups := []
    Loop Files TransferBackupDir "\settings-*.txt"
        backups.Push(A_LoopFileFullPath)
    Check("a backup of the old settings was written first", backups.Length >= 1
        && InStr(FileRead(backups[backups.Length], "UTF-8"), "zem = you@example.com"), backups.Length)

    plan := TransferPlan(TransferParse(file))
    r := TransferApply(plan, "replace", true)
    Check("replace makes the snippets exactly the file's", r.ok && Snippets.Length = 3 && !(FileRead(SnipPath, "UTF-8") ~= "callnote"), Snippets.Length)
    Check("an allowed risky preference is applied", SnowPrefGet("clips.skipsensitive") = "0")
    SendLevel(1)
    TypeBegin()
    Check("a snippet that was replaced away no longer expands", TypeIn("callnote") = "callnote")
    TypeEnd()
    empty := TransferPlan(TransferParse("format = 1`n[snippets]`n"))
    r := TransferApply(empty, "replace", false)
    Check("replacing with a file that has no snippets is refused", !r.ok && Snippets.Length = 3, r.message)

    ClipSetAutoDecimal(true)
    SnowPrefSet("clips.skipsensitive", "1")
    Loop 12
        TransferBackup()
    n := 0
    Loop Files TransferBackupDir "\settings-*.txt"
        n++
    Check("only the newest 10 backups are kept", n = 10, n)
}

Group("transfer: files and dialog", GroupTransferDialog)
GroupTransferDialog() {
    SnowPrefsReset()
    ClipApplyPrefs()
    SnippetsResetToDefaults()
    path := TestShots "\export-test.txt"
    TransferExportFile(path)
    Check("export writes a file that parses", TransferParse(FileRead(path, "UTF-8")).ok)

    Snippets[1].text := "changed@example.com"
    SnippetsSave()
    SnippetsApply()
    ClipSetAutoDecimal(false)
    TransferImportStart(path)
    Check("the import dialog opens", TransferWin.IsVisible())
    Check("it summarizes what would change", InStr(TransferInfo.Value, "START/END to hours: off -> on")
        && InStr(TransferInfo.Value, "1 changed"), TransferInfo.Value)
    Snap(TransferWin, "import")
    TransferWin.Hide()
    Check("cancelling changes nothing", Snippets[1].text = "changed@example.com" && !ClipAutoDecimal)
    TransferImportStart(path)
    TransferChoose("replace")
    Check("importing the export restores the settings", Snippets[1].text = "you@example.com" && ClipAutoDecimal && !TransferWin.IsVisible())

    bad := TestShots "\not-settings.txt"
    FileOpen(bad, "w").Write("just some notes`nnothing to see")
    TestAnswer("Button1")
    TransferImportStart(bad)
    Check("a file that is not a settings export is refused and nothing opens", !TransferWin.IsVisible() && Snippets.Length = 7)
    TestAnswer("Button1")
    TransferImportStart(TestShots "\does-not-exist.txt")
    Check("a missing file is reported, not a crash", !TransferWin.IsVisible())

    guardOff := TestShots "\guard-off.txt"
    FileOpen(guardOff, "w").Write("format = 1`n[prefs]`nclips.skipsensitive = 0`n")
    TransferImportStart(guardOff)
    Check("a file that lowers privacy shows the opt-in line", TransferRiskyBtn.Visible && InStr(TransferInfo.Value, "Password-manager guard: on -> OFF"))
    TransferChoose("merge")
    Check("by default the risky setting is not applied", SnowPrefGet("clips.skipsensitive") = "1")
    TransferImportStart(guardOff)
    TransferToggleRisky()
    TransferChoose("merge")
    Check("it is applied only after the opt-in is ticked", SnowPrefGet("clips.skipsensitive") = "0")
    SnowPrefSet("clips.skipsensitive", "1")
}

TestWaitFor(fn, ms := 5000) {
    t0 := A_TickCount
    while (A_TickCount - t0 < ms) {
        if fn()
            return true
        Sleep(50)
    }
    return false
}

; Sends keys with a scratch window focused (so a stray key cannot land in another program),
; at send level 1 so this script's own hotkeys react.
TestSend(keys) {
    SendLevel(1)
    TypeBegin()
    SendEvent(keys)
    Sleep(500)
    TypeEnd()
}

Group("hotkeys: rules", GroupHotkeyRules)
GroupHotkeyRules() {
    ok := true
    for k in ["^!F9", "#n", "!c", "^!Space", "F5", "+F5", "^!k", "^!Home", "^!Escape"]
        if (HotkeyCheck(k) != "")
            ok := false, bad := k
    Check("sensible shortcuts are accepted", ok, IsSet(bad) ? bad : "")
    rejected := true
    for k in ["", "a", "+a", "^", "^!", "^;", "^!F25", "^^a", "^c", "!F4", "#l", "^!Delete", "^v"]
        if (HotkeyCheck(k) = "")
            rejected := false, bad2 := k
    Check("plain keys, unsupported keys, duplicates and reserved shortcuts are refused", rejected, IsSet(bad2) ? bad2 : "")
    Check("a shortcut on a plain key says why", InStr(HotkeyCheck("a"), "break typing"))
    Check("shortcuts compare by meaning, not spelling", HotkeyNormalize("#^!x") = "^!#x"
        && HotkeyNormalize("!+A") = HotkeyNormalize("+!a") && HotkeyNormalize("^!Escape") = "^!esc")
    Check("a captured key is built in a fixed order", HotkeyBuild("#^", "N") = "^#n" && HotkeyBuild("", "Escape") = "Esc"
        && HotkeyBuild("^!", "F9") = "^!F9" && HotkeyBuild("+", "A") = "+a")
    Check("virtual-key codes map to modifiers", HotkeyModOf(0x5B) = "#" && HotkeyModOf(0xA2) = "^" && HotkeyModOf(0xA4) = "!"
        && HotkeyModOf(0x10) = "+" && HotkeyModOf(0x41) = "")
}

Group("hotkeys: rebinding", GroupHotkeyRebind)
GroupHotkeyRebind() {
    Check("every global hotkey has an id", SnowHotkeys.Count = 8 && HotkeyText("pad") = "Win+N" && HotkeyText("hud") = "Alt+Y"
        , SnowHotkeys.Count)
    r := HotkeyRebind("calc", "^!F8")
    entry := ""
    for e in SnowRegistry
        if (e.HasOwnProp("id") && e.id = "calc")
            entry := e
    Check("rebinding changes the key, the HUD entry and the saved choice", r.ok && HotkeyText("calc") = "Ctrl+Alt+F8"
        && entry.key = "Ctrl+Alt+F8" && IniRead(SnowPrefsPath, "hotkeys", "calc", "") = "^!F8" && HudWin = "", r.error)
    TestSend("^!{F8}")
    Check("the new shortcut works at once", IsObject(CalcWin) && CalcWin.IsVisible())
    CalcClose()
    TestSend("!c")
    Check("the old shortcut no longer does", !CalcWin.IsVisible())
    Check("a shortcut already used is refused and names its owner", !HotkeyRebind("pad", "!s").ok
        && InStr(HotkeyRebind("pad", "!s").error, "Snippets") && HotkeyText("pad") = "Win+N")
    Check("reserved and plain-key shortcuts are refused and nothing changes", !HotkeyRebind("pad", "^c").ok
        && !HotkeyRebind("pad", "a").ok && HotkeyText("pad") = "Win+N")
    r := HotkeyReset("calc")
    Check("reset returns the default and forgets the saved choice", r.ok && HotkeyText("calc") = "Alt+C"
        && IniRead(SnowPrefsPath, "hotkeys", "calc", "") = "")
    TestSend("!c")
    Check("the default works again", CalcWin.IsVisible())
    CalcClose()

    failed := HotkeyRebindMany([{id: "calc", key: "^!F8"}])
    TestSend("!c")
    stale := IsObject(CalcWin) && CalcWin.IsVisible()
    CalcClose()
    Check("moving a hotkey with the bulk call releases its old key", failed.Length = 0 && HotkeyText("calc") = "Ctrl+Alt+F8" && !stale)
    HotkeysResetAll()

    failed := HotkeyRebindMany([{id: "calc", key: "!s"}, {id: "snippets", key: "!c"}])
    Check("two hotkeys can swap keys", failed.Length = 0 && HotkeyText("calc") = "Alt+S" && HotkeyText("snippets") = "Alt+C")
    TestSend("!s")
    swapped1 := CalcWin.IsVisible()
    CalcClose()
    TestSend("!c")
    swapped2 := SnipWin != "" && SnipWin.IsVisible()
    if (SnipWin != "")
        SnipWin.Hide()
    Check("after a swap each key runs the other's action", swapped1 && swapped2)
    HotkeysResetAll()
    Check("reset all restores every default and clears the saved choices", HotkeyText("calc") = "Alt+C" && HotkeyText("snippets") = "Alt+S"
        && IniRead(SnowPrefsPath, "hotkeys", "calc", "") = "" && IniRead(SnowPrefsPath, "hotkeys", "snippets", "") = "")
}

Group("hotkeys: labels follow the key", GroupHotkeyLabels)
GroupHotkeyLabels() {
    HotkeyRebind("hud", "^!F5")
    trayNew := true
    try A_TrayMenu.Check("Show HUD (Ctrl+Alt+F5)")
    catch
        trayNew := false
    trayOld := true
    try A_TrayMenu.Check("Show HUD (Alt+Y)")
    catch
        trayOld := false
    HudToggle()
    status := HudWin.pBotStatus.Value
    HudWin.Hide()
    Check("the tray menu and the HUD footer show the new key", trayNew && !trayOld && InStr(status, "ctrl+alt+f5"), status)
    HotkeysResetAll()
    HudToggle()
    status := HudWin.pBotStatus.Value
    HudWin.Hide()
    Check("and the default again after a reset", InStr(status, "alt+y") && !InStr(status, "ctrl+alt+f5"), status)
}

Group("hotkeys: saved choices at start", GroupHotkeyStart)
GroupHotkeyStart() {
    IniWrite("^!F6", SnowPrefsPath, "hotkeys", "tmpa")
    IniWrite("^c", SnowPrefsPath, "hotkeys", "tmpb")
    IniWrite("!s", SnowPrefsPath, "hotkeys", "tmpc")
    RegHotkey("tmpa", "^!F5", "temp a", (*) => 0)
    RegHotkey("tmpb", "^!F4", "temp b", (*) => 0)
    RegHotkey("tmpc", "^!F3", "temp c", (*) => 0)
    Check("a saved key replaces the default", HotkeyText("tmpa") = "Ctrl+Alt+F6")
    Check("a saved key that is invalid or already in use is ignored", HotkeyText("tmpb") = "Ctrl+Alt+F4" && HotkeyText("tmpc") = "Ctrl+Alt+F3")
    for id in ["tmpa", "tmpb", "tmpc"] {
        try Hotkey(SnowHotkeys[id].key, "Off")
        SnowRegistry.RemoveAt(SnowRegistry.Length)
        SnowHotkeys.Delete(id)
        SnowHotkeyOrder.Pop()
        IniDelete(SnowPrefsPath, "hotkeys", id)
    }
    Check("the temporary hotkeys are gone", SnowHotkeys.Count = 8 && SnowHotkeyOrder.Length = 8)
}

Group("hotkeys: capture", GroupHotkeyCapture)
GroupHotkeyCapture() {
    got := "unset"
    HotkeyCaptureStart((k) => got := k)
    Sleep(400)
    SendEvent("^!{F7}")
    TestWaitFor(() => got != "unset")
    Check("a shortcut is captured with its modifiers", got = "^!F7", got)
    Check("the script's hotkeys are active again afterwards", !A_IsSuspended)

    got := "unset"
    HotkeyCaptureStart((k) => got := k)
    Sleep(400)
    SendEvent("!s")
    TestWaitFor(() => got != "unset")
    Check("pressing an existing hotkey captures it instead of running it", got = "!s" && (SnipWin = "" || !SnipWin.IsVisible()), got)

    got := "unset"
    HotkeyCaptureStart((k) => got := k)
    Sleep(400)
    SendEvent("{Esc}")
    TestWaitFor(() => got != "unset")
    Check("Esc on its own cancels", got = "", got)

    got := "unset"
    HotkeyCaptureStart((k) => got := k)
    Sleep(400)
    SendEvent("^{Esc}")
    TestWaitFor(() => got != "unset")
    Check("Esc with a modifier is a shortcut", got = "^Esc", got)

    got := "unset"
    HotkeyCaptureStart((k) => got := k, 1)
    TestWaitFor(() => got != "unset", 3000)
    Check("capture gives up after the timeout", got = "" && !A_IsSuspended, got)
}

Group("hotkeys: window", GroupHotkeyWindow)
GroupHotkeyWindow() {
    HotkeysToggle()
    Check("the hotkeys window lists every hotkey", HkWin.IsVisible() && HkList.GetCount() = 8, HkList.GetCount())
    HkList.Modify(1, "Select Focus Vis")
    HotkeysChange()
    Sleep(400)
    SendEvent("^!{F6}")
    TestWaitFor(() => InStr(HkMsg.Value, "is now"))
    Check("changing a hotkey from the window rebinds it and says so", HotkeyText("calc") = "Ctrl+Alt+F6" && InStr(HkMsg.Value, "Ctrl+Alt+F6"), HkMsg.Value)
    Snap(HkWin, "hotkeys")
    HkList.Modify(2, "Select Focus Vis")
    HotkeysChange()
    Sleep(400)
    SendEvent("!s")
    TestWaitFor(() => InStr(HkMsg.Value, "already used"))
    Check("a clash is explained and nothing changes", HotkeyText("pad") = "Win+N" && InStr(HkMsg.Value, "Snippets"), HkMsg.Value)
    HkList.Modify(1, "Select Focus Vis")
    HotkeysReset()
    Check("reset in the window restores the default", HotkeyText("calc") = "Alt+C")
    HotkeysResetEveryone()
    HotkeysClose()
}

Group("hotkeys: export and import", GroupHotkeyTransfer)
GroupHotkeyTransfer() {
    text := TransferExportText()
    Check("an export lists the hotkeys", InStr(text, "[hotkeys]") && InStr(text, "calc = !c") && InStr(text, "pad = #n"))
    HotkeyRebind("note", "^!F4")
    text := TransferExportText()
    HotkeysResetAll()
    plan := TransferPlan(TransferParse(text))
    r := TransferApply(plan, "merge", false)
    Check("importing an export restores a changed hotkey", plan.hotkeys.Length = 1 && r.ok && HotkeyText("note") = "Ctrl+Alt+F4"
        && InStr(r.message, "1 hotkeys"), r.message)
    HotkeysResetAll()

    p := TransferParse("format = 1`n[hotkeys]`nnope = ^!x`ncalc = ^c`npad = ^!F3`n")
    Check("unknown ids and unusable shortcuts are skipped and listed", p.ok && p.hotkeys.Count = 1 && p.hotkeys["pad"] = "^!F3"
        && p.ignored.Length = 2, p.ignored.Length)

    clash := TransferPlan(TransferParse("format = 1`n[hotkeys]`ncalc = ^!F2`nnote = ^!F2`npad = !s`n"))
    skipped := 0
    for h in clash.hotkeys
        if (h.skip != "")
            skipped++
    Check("moves that would clash are skipped, including onto an unchanged hotkey", clash.hotkeys.Length = 3 && skipped = 3, skipped)
    r := TransferApply(clash, "merge", false)
    Check("applying skips them and changes nothing", HotkeyText("calc") = "Alt+C" && HotkeyText("note") = "Alt+N" && HotkeyText("pad") = "Win+N")

    swap := TransferPlan(TransferParse("format = 1`n[hotkeys]`ncalc = !s`nsnippets = !c`n"))
    Check("a swap in a file is not treated as a clash", swap.hotkeys.Length = 2 && swap.hotkeys[1].skip = "" && swap.hotkeys[2].skip = "")
    Check("the summary shows the hotkey changes", InStr(TransferSummaryText("x.txt", swap), "Snow Calc: time diff (1100-1115) and math: Alt+C -> Alt+S"))
    TransferApply(swap, "merge", false)
    Check("a swap in a file is applied", HotkeyText("calc") = "Alt+S" && HotkeyText("snippets") = "Alt+C")
    HotkeysResetAll()
    SettingsAskConfirm := true
}

Group("hotkeys: reset settings", GroupHotkeyReset)
GroupHotkeyReset() {
    HotkeyRebind("note", "^!F4")
    TestAnswer("Button1")
    SettingsReset()
    Check("reset settings also restores the hotkeys", HotkeyText("note") = "Alt+N" && IniRead(SnowPrefsPath, "hotkeys", "note", "") = "")
}

Group("version", GroupVersion)
GroupVersion() {
    Check("the version is a plain major.minor.patch", RegExMatch(SNOW_VERSION, "^\d+\.\d+\.\d+$"), SNOW_VERSION)
    Check("the banner shows it", InStr(ART_SUBTITLE, "v" SNOW_VERSION), ART_SUBTITLE)
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

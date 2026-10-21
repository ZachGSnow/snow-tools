; ===== SNOW CLIPS =====
; Clipboard history (Ctrl+Alt+V): up to 10,000 text clips and 200 images (see
; lib\clipstore.ahk), searchable, with a preview pane for text and images.
; START/END time blocks are auto-converted to decimal hours (toggle with Ctrl+T).

global ClipUI := ""
global ClipSearch := ""
global ClipList := ""
global ClipPreviewEdit := ""
global ClipPreviewPic := ""
global ClipMeta := ""
global ClipAutoBtn := ""
global ClipItems := []
global ClipBusy := false
global ClipIgnoreUntil := 0
global ClipPrefsPath := A_ScriptDir "\data\prefs.ini"
global ClipAutoDecimal := true
global ClipPaused := false

ClipStoreInit()
try ClipAutoDecimal := (IniRead(ClipPrefsPath, "clips", "autodecimal", "1") = "1")
OnClipboardChange(ClipChanged)

RegHotkey("^!v", "Snow Clips: clipboard history, text + image preview", ClipToggle)
RegHotkey("^!p", "Snow Clips: pause / resume recording", ClipTogglePause)
RegDoc("auto", "clipboard", "START/END time blocks become decimal hours (Ctrl+T in Snow Clips)")
RegDoc("auto", "clipboard", "copies flagged by password managers are never recorded")

; ---------------------------------------------------------------------------
; Capture
; ---------------------------------------------------------------------------
ClipChanged(dataType) {
    global ClipIgnoreUntil, ClipAutoDecimal, ClipPaused
    if (A_TickCount < ClipIgnoreUntil || ClipPaused)
        return
    if ClipIsSensitive()
        return
    if (dataType = 1) {
        try {
            text := A_Clipboard
        } catch {
            return
        }
        if (ClipAutoDecimal && ClipIsOnlyTimeBlock(text)) {
            hours := ClipParseTimeBlock(text)
            if (hours != "") {
                ClipAddText(text)
                ClipSetText(hours)
                ClipToast(GL_ARROW " " hours " h (copied)")
                return
            }
        }
        ClipAddText(text)
    } else if (dataType = 2) {
        try {
            ClipAddImageFromClipboard()
        } catch as err {
            SnowLog("clip image capture failed: " err.Message)
        }
    }
}

; True when the program that set the clipboard asked for it not to be recorded. Password
; managers set "ExcludeClipboardContentFromMonitorProcessing"; Windows' own history honors
; "CanIncludeInClipboardHistory" = 0. If the flag is there but unreadable, play it safe.
ClipIsSensitive() {
    static fmtExclude := DllCall("RegisterClipboardFormat", "Str", "ExcludeClipboardContentFromMonitorProcessing", "UInt")
    static fmtHistory := DllCall("RegisterClipboardFormat", "Str", "CanIncludeInClipboardHistory", "UInt")
    if DllCall("IsClipboardFormatAvailable", "UInt", fmtExclude)
        return true
    if !DllCall("IsClipboardFormatAvailable", "UInt", fmtHistory)
        return false
    sensitive := true
    if DllCall("OpenClipboard", "Ptr", A_ScriptHwnd) {
        h := DllCall("GetClipboardData", "UInt", fmtHistory, "Ptr")
        if h {
            p := DllCall("GlobalLock", "Ptr", h, "Ptr")
            if p {
                sensitive := (NumGet(p, "UInt") = 0)
                DllCall("GlobalUnlock", "Ptr", h)
            }
        }
        DllCall("CloseClipboard")
    }
    return sensitive
}

; Ctrl+Alt+P pauses and resumes recording. Not saved: every start records again.
ClipTogglePause(*) {
    global ClipPaused, ClipUI
    ClipPaused := !ClipPaused
    ClipToast(ClipPaused ? "Clipboard history paused" : "Clipboard history recording")
    if (ClipUI != "" && ClipUI.IsVisible())
        ClipRefresh(Max(1, ClipList.GetNext(0)))
}

; Set the clipboard without the monitor recording the change.
ClipSetText(text) {
    global ClipIgnoreUntil
    ClipIgnoreUntil := A_TickCount + 1500
    A_Clipboard := text
    ClipWait(1)
}

ClipToast(text) {
    ToolTip(text)
    SetTimer(() => ToolTip(), -1800)
}

; ---------------------------------------------------------------------------
; Window
; ---------------------------------------------------------------------------
ClipBuild() {
    global ClipUI, ClipSearch, ClipList, ClipPreviewEdit, ClipPreviewPic, ClipMeta, ClipAutoBtn
    w := SnowWin("SNOW CLIPS", 112, 33)
    ClipUI := w
    w.Put(2, 1, ">>", THEME_ACCENT)
    ClipSearch := w.g.Add("Edit", "x" w.X(5) " y" w.Y(1) " w" w.X(46) " r1 -E0x200 Background" THEME_FIELD " c" THEME_FG_HI)
    ClipSearch.OnEvent("Change", ClipOnSearch)
    ClipAutoBtn := w.Btn(79, 1, ClipAutoLabel(), ClipToggleAuto)
    w.Rule(2, 48, GL_DJ)

    ClipList := w.Add("ListView", 1, 3, 47, 26, "-Hdr -Multi +LV0x10000 -E0x200 Background" THEME_FIELD " c" THEME_FG, ["when", "kind", "clip"])
    ClipList.ModifyCol(1, 9 * w.cw)
    ClipList.ModifyCol(2, 6 * w.cw)
    ClipList.ModifyCol(3, 47 * w.cw - 15 * w.cw - 24)
    DarkScrollbar(ClipList)
    ClipList.OnEvent("ItemSelect", ClipOnSelect)
    ClipList.OnNotify(-12, SnowListDraw)    ; amber selection bar
    ClipList.OnEvent("DoubleClick", ClipPaste)
    w.VLine(48, 3, 28)

    ClipPreviewEdit := w.Add("Edit", 49, 3, 62, 26, "ReadOnly Multi VScroll -E0x200 Background" THEME_FIELD " c" THEME_FG)
    DarkScrollbar(ClipPreviewEdit)
    ClipPreviewPic := w.Add("Picture", 49, 3, 62, 26, "Hidden")

    w.Rule(29, 48, GL_UJ)
    w.Btn(2, 30, "[ENTER paste]", ClipPaste)
    w.Btn(17, 30, "[^P pin]", ClipPinSelected)
    w.Btn(27, 30, "[DEL delete]", ClipDeleteSelected)
    w.Btn(41, 30, "[^D copy hours]", ClipCopyHours)
    ClipMeta := w.Add("Text", 2, 31, 108, 1, "-Wrap 0x80 c" THEME_FG_DIM, "")
}

ClipToggle(*) {
    global ClipUI, ClipSearch, ClipAutoBtn, ClipAutoDecimal
    if (ClipUI = "")
        ClipBuild()
    if ClipUI.IsVisible() {
        ClipUI.Hide()
        return
    }
    ClipSearch.Value := ""
    ClipAutoBtn.Value := ClipAutoLabel()
    ClipRefresh()
    ClipUI.Show()
    ClipSearch.Focus()
}

ClipActive() {
    global ClipUI
    return (ClipUI != "") && ClipUI.IsActive()
}

ClipListFocused() {
    global ClipUI, ClipList
    return ClipActive() && (ClipUI.g.FocusedCtrl = ClipList)
}

ClipOnSearch(*) {
    SetTimer(ClipRefresh, -150)    ; debounce typing
}

ClipPreviewText(text) {
    t := RegExReplace(SubStr(text, 1, 160), "\s+", " ")
    return Trim(t)
}

; Rebuild the list from the store, applying the search filter. keepRow re-selects a row.
ClipRefresh(keepRow := 1) {
    global ClipUI, ClipSearch, ClipList, ClipItems, ClipBusy, ClipTexts, ClipImages, ClipPaused
    if (ClipUI = "")
        return
    ClipBusy := true
    filter := Trim(ClipSearch.Value)
    ClipItems := []
    ClipList.Opt("-Redraw")
    ClipList.Delete()
    for item in ClipMergedItems() {
        e := item.e
        if (item.kind = "txt") {
            if (filter != "" && !InStr(e.text, filter))
                continue
            kind := "TXT"
            label := ClipPreviewText(e.text)
        } else {
            label := e.w "x" e.h " " GL_DOT " " Round(e.size / 1024) " KB"
            if (filter != "" && !InStr("img image " label, filter))
                continue
            kind := "IMG"
        }
        ClipItems.Push(item)
        ClipList.Add(, (e.pin ? "*" : " ") SnowShortTime(e.ts), kind, label)
    }
    ClipList.Opt("+Redraw")
    ClipBusy := false
    ClipUI.SetStatus(ClipTexts.Length " txt " GL_DOT " " ClipImages.Length " img" (filter != "" ? " " GL_DOT " " ClipItems.Length " shown" : "") (ClipPaused ? " " GL_DOT " PAUSED" : ""))
    if (ClipItems.Length > 0)
        ClipList.Modify(Min(keepRow, ClipItems.Length), "Select Focus Vis")
    ClipShowPreview()
}

ClipSelected() {
    global ClipList, ClipItems
    row := ClipList.GetNext(0)
    if (row = 0 || row > ClipItems.Length)
        return ""
    return ClipItems[row]
}

global ClipSelEvents := 0

ClipOnSelect(ctrl, row, selected) {
    global ClipBusy, ClipSelEvents
    ClipSelEvents++
    if (selected && !ClipBusy)
        ClipShowPreview()
}

ClipShowPreview() {
    global ClipUI, ClipPreviewEdit, ClipPreviewPic, ClipMeta
    item := ClipSelected()
    if (item = "") {
        ClipPreviewPic.Visible := false
        ClipPreviewEdit.Visible := true
        ClipPreviewEdit.Value := ""
        ClipMeta.Value := ""
        return
    }
    e := item.e
    stamp := (e.ts != "") ? FormatTime(e.ts, "yyyy-MM-dd HH:mm") : "unknown date"
    if (item.kind = "txt") {
        ClipPreviewPic.Visible := false
        ClipPreviewEdit.Visible := true
        ClipPreviewEdit.Value := (StrLen(e.text) > 20000) ? SubStr(e.text, 1, 20000) "`r`n... (preview truncated)" : e.text
        RegExReplace(e.text, "\n", "", &breaks)
        hours := ClipParseTimeBlock(e.text)
        ClipMeta.Value := "TXT " GL_DOT " " StrLen(e.text) " chars " GL_DOT " " (breaks + 1) " lines " GL_DOT " " stamp
            . (hours != "" ? " " GL_DOT " " hours " h" : "")
    } else {
        ClipPreviewEdit.Visible := false
        pw := 62 * ClipUI.cw
        ph := 26 * ClipUI.ch
        scale := Min(1.0, pw / e.w, ph / e.h)
        nw := Max(1, Floor(e.w * scale))
        nh := Max(1, Floor(e.h * scale))
        ClipPreviewPic.Visible := false
        try ClipPreviewPic.Value := "*w" nw " *h" nh " " ClipImagePath(e)
        ClipPreviewPic.Move(49 * ClipUI.cw + (pw - nw) // 2, 3 * ClipUI.ch + (ph - nh) // 2, nw, nh)
        ClipPreviewPic.Visible := true
        ClipMeta.Value := "IMG " GL_DOT " " e.w "x" e.h " " GL_DOT " " Round(e.size / 1024) " KB " GL_DOT " " stamp
    }
}

; ---------------------------------------------------------------------------
; Actions
; ---------------------------------------------------------------------------
ClipMove(delta) {
    global ClipList, ClipItems
    if (ClipItems.Length = 0)
        return
    row := ClipList.GetNext(0)
    ClipList.Modify(Max(1, Min(ClipItems.Length, row + delta)), "Select Focus Vis")
    ClipShowPreview()
}

ClipPaste(*) {
    global ClipUI, ClipIgnoreUntil
    item := ClipSelected()
    if (item = "")
        return
    ClipUI.Hide()
    ClipIgnoreUntil := A_TickCount + 1500
    if (item.kind = "txt") {
        A_Clipboard := item.e.text
        if !ClipWait(1)
            return
    } else {
        if !GdipPngToClipboard(ClipImagePath(item.e)) {
            ClipToast("Could not load image")
            return
        }
    }
    Sleep(90)    ; let the previous window regain focus
    Send("^v")
    if (item.kind = "txt")
        ClipAddText(item.e.text)
    else
        ClipTouchImage(item.e)
}

ClipPinSelected(*) {
    global ClipList
    item := ClipSelected()
    if (item = "")
        return
    ClipTogglePin(item)
    ClipRefresh(Max(1, ClipList.GetNext(0)))
}

ClipDeleteSelected(*) {
    global ClipList
    item := ClipSelected()
    if (item = "")
        return
    row := ClipList.GetNext(0)
    ClipDeleteItem(item)
    ClipRefresh(row)
}

ClipCopyHours(*) {
    item := ClipSelected()
    if (item = "" || item.kind != "txt")
        return
    hours := ClipParseTimeBlock(item.e.text)
    if (hours != "") {
        ClipSetText(hours)
        ClipToast("copied " hours " h")
    }
}

; Fixed-width label so ON/OFF swap doesn't change the control's size.
ClipAutoLabel() {
    global ClipAutoDecimal
    return "[^T START/END > hours: " (ClipAutoDecimal ? "ON " : "OFF") "]"
}

ClipToggleAuto(*) {
    global ClipAutoDecimal, ClipAutoBtn, ClipPrefsPath
    ClipAutoDecimal := !ClipAutoDecimal
    ClipAutoBtn.Value := ClipAutoLabel()
    try IniWrite(ClipAutoDecimal ? "1" : "0", ClipPrefsPath, "clips", "autodecimal")
}

#HotIf ClipActive()
Up::ClipMove(-1)
Down::ClipMove(1)
PgUp::ClipMove(-12)
PgDn::ClipMove(12)
Enter::ClipPaste()
NumpadEnter::ClipPaste()
^p::ClipPinSelected()
^d::ClipCopyHours()
^t::ClipToggleAuto()
#HotIf ClipListFocused()
Delete::ClipDeleteSelected()
#HotIf

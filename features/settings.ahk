; ===== SETTINGS =====
; Ctrl+Alt+S (or the HUD / tray menu): the clipboard options, and the buttons that delete
; your data. Preferences are stored through lib\settings.ahk. Deleting is a normal file
; delete, not a secure erase.

global SettingsWin := ""
global SettingsChecks := []        ; [{ctrl, label, get}] one per checkbox row
global SettingsSensNote := ""
global SettingsDataInfo := ""
global SettingsAskConfirm := true  ; the self-test turns this off

global WipeWin := ""
global WipeInfo := ""
global WipeEdit := ""
global WipeMsg := ""

RegHotkey("^!s", "Settings: clipboard options, delete data", SettingsToggle)

; ---------------------------------------------------------------------------
; Window
; ---------------------------------------------------------------------------
SettingsBuild() {
    global SettingsWin, SettingsSensNote, SettingsDataInfo
    w := SnowWin("SETTINGS", 84, 23)
    SettingsWin := w
    w.Put(2, 1, "CLIPBOARD", THEME_ACCENT)
    SettingsAddCheck(w, 3, "Skip copies flagged by password managers", () => SnowPrefBool("clips.skipsensitive"), SettingsSetSensitive)
    SettingsSensNote := w.Add("Text", 6, 4, 76, 1, "-Wrap 0x80 c" THEME_FG_DIM, "")
    SettingsAddCheck(w, 6, "Turn START/END time blocks into decimal hours", () => ClipAutoDecimal, ClipSetAutoDecimal)
    w.Put(6, 7, "START: 0905 | END: 0950 puts 0.75 on the clipboard", THEME_FG_DIM)
    SettingsAddCheck(w, 9, "Pause recording  (Ctrl+Alt+P)", () => ClipPaused, SettingsSetPaused)

    w.Rule(11)
    w.Put(2, 12, "DATA", THEME_ACCENT)
    SettingsDataInfo := w.Add("Text", 2, 13, 80, 1, "-Wrap 0x80 c" THEME_FG_DIM, "")
    w.Btn(2, 15, "[clear clipboard history]", SettingsClearHistory)
    w.Put(30, 15, "every clip and image, pinned included", THEME_FG_DIM)
    w.Btn(2, 16, "[delete all data]", SettingsDeleteAll)
    w.Put(30, 16, "clips, images, pad, sticky notes and the log", THEME_FG_DIM)
    w.Btn(2, 17, "[reset settings]", SettingsReset)
    w.Put(30, 17, "preferences and snippets back to the defaults", THEME_FG_DIM)
    w.Btn(2, 18, "[open data folder]", (*) => SnowOpenDataFolder())
    w.Put(2, 20, "Deleting is a normal file delete, not a secure erase.", THEME_FG_DIM)
    w.SetStatus("esc closes")
}

; A clickable "[x] label" row. get() reads the current value, set(on) changes it.
SettingsAddCheck(w, row, label, get, set) {
    global SettingsChecks
    c := w.Btn(2, row, "[x] " label, (*) => SettingsFlip(get, set))
    SettingsChecks.Push({ctrl: c, label: label, get: get})
}

SettingsFlip(get, set) {
    set(!get())
    SettingsRefresh()
}

SettingsRefresh() {
    global SettingsChecks, SettingsSensNote, SettingsDataInfo, ClipTexts, ClipImages
    if (SettingsWin = "")
        return
    for c in SettingsChecks {
        get := c.get    ; a function stored in an object is not called as a method
        c.ctrl.Value := (get() ? "[x] " : "[ ] ") c.label
    }
    if SnowPrefBool("clips.skipsensitive") {
        SettingsSensNote.SetFont("c" THEME_FG_DIM)
        SettingsSensNote.Value := "On (recommended): copies from password managers are never recorded."
    } else {
        SettingsSensNote.SetFont("c" THEME_ALERT)
        SettingsSensNote.Value := "OFF: copies from password managers ARE recorded, in plain text."
    }
    SettingsDataInfo.Value := "clips: " ClipTexts.Length " txt / " ClipImages.Length " img   " GL_DOT "   notes: " NotesSummary()
}

SettingsToggle(*) {
    global SettingsWin
    if (SettingsWin = "")
        SettingsBuild()
    if SettingsWin.IsVisible() {
        SettingsWin.Hide()
        return
    }
    SettingsRefresh()
    SettingsWin.Show()
}

; ---------------------------------------------------------------------------
; Options
; ---------------------------------------------------------------------------
; MsgBox Yes/No, warning icon, default No, always on top.
SettingsConfirm(text) {
    return MsgBox(text, "*  Snow Tools  *", "YesNo Icon! Default2 0x40000") = "Yes"
}

SettingsSetSensitive(on) {
    global SettingsAskConfirm
    if (!on && SettingsAskConfirm && !SettingsConfirm("Turn off password-manager protection?`n`nCopies from password managers will then be recorded in the clipboard history, in plain text."))
        return
    SnowPrefSet("clips.skipsensitive", on)
}

SettingsSetPaused(on) {
    global ClipPaused
    if (on != ClipPaused)
        ClipTogglePause()
}

; ---------------------------------------------------------------------------
; Deleting data
; ---------------------------------------------------------------------------
SettingsClearHistory(*) {
    global ClipTexts, ClipImages, SettingsAskConfirm
    if (SettingsAskConfirm && !SettingsConfirm("Delete " ClipTexts.Length " text clips and " ClipImages.Length " images from the clipboard history?`n`nPinned clips are included. This cannot be undone."))
        return
    ClipClearAll()
    SettingsAfterDelete("Clipboard history deleted")
}

SettingsDeleteAll(*) {
    global SettingsAskConfirm
    if SettingsAskConfirm {
        SettingsWipeDialog()
        return
    }
    SettingsWipeNow()
}

; Everything you typed or copied: clips, images, the pad, sticky notes and the log.
; Snippets and preferences stay.
SettingsWipeNow() {
    ClipClearAll()
    NotesClearAll()
    try FileDelete(SnowLogPath)
    SettingsAfterDelete("All data deleted")
}

SettingsAfterDelete(message) {
    global ClipUI
    if (ClipUI != "")
        ClipRefresh()
    SettingsRefresh()
    ClipToast(message)
}

SettingsReset(*) {
    global SettingsAskConfirm
    if (SettingsAskConfirm && !SettingsConfirm("Reset settings?`n`nPreferences go back to their defaults and your snippets are replaced by the built-in set. Clips and notes are not touched."))
        return
    SnowPrefsReset()
    ClipApplyPrefs()
    SnippetsResetToDefaults()
    SettingsRefresh()
    ClipToast("Settings reset")
}

; ---------------------------------------------------------------------------
; "Delete all data" asks for the word DELETE
; ---------------------------------------------------------------------------
SettingsWipeTypedOk(text) {
    return Trim(text) == "DELETE"
}

WipeBuild() {
    global WipeWin, WipeInfo, WipeEdit, WipeMsg
    w := SnowWin("DELETE ALL DATA", 64, 14)
    WipeWin := w
    WipeInfo := w.Add("Text", 2, 1, 60, 5, "-Wrap 0x80 c" THEME_FG, "")
    w.Put(2, 7, "Snippets and settings are kept. This cannot be undone.", THEME_FG_DIM)
    w.Put(2, 9, "Type DELETE to confirm:", THEME_ACCENT)
    WipeEdit := w.g.Add("Edit", "x" w.X(26) " y" w.Y(9) " w" w.X(16) " r1 -E0x200 Background" THEME_FIELD " c" THEME_FG_HI)
    WipeMsg := w.Add("Text", 2, 10, 60, 1, "-Wrap 0x80 c" THEME_ALERT, "")
    w.Btn(2, 12, "[DELETE EVERYTHING]", SettingsWipeAccept, THEME_ALERT)
    w.Btn(26, 12, "[cancel]", (*) => w.Hide())
}

SettingsWipeDialog() {
    global WipeWin, WipeInfo, WipeEdit, WipeMsg, ClipTexts, ClipImages
    if (WipeWin = "")
        WipeBuild()
    WipeInfo.Value := "This permanently deletes:`n"
        . "  - " ClipTexts.Length " text clips and " ClipImages.Length " images (pinned included)`n"
        . "  - notes: " NotesSummary() "`n"
        . "  - the error log"
    WipeEdit.Value := ""
    WipeMsg.Value := ""
    WipeWin.Show()
    WipeEdit.Focus()
}

SettingsWipeAccept(*) {
    global WipeWin, WipeEdit, WipeMsg
    if !SettingsWipeTypedOk(WipeEdit.Value) {
        WipeMsg.Value := "Type DELETE exactly, in capital letters."
        return
    }
    WipeWin.Hide()
    SettingsWipeNow()
}

WipeActive() {
    global WipeWin
    return (WipeWin != "") && WipeWin.IsActive()
}

#HotIf WipeActive()
Enter::SettingsWipeAccept()
NumpadEnter::SettingsWipeAccept()
#HotIf

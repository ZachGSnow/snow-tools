; ===== NOTES: SNOW PAD + STICKY NOTES =====

; ---------------------------------------------------------------------------
; SNOW PAD - one persistent scratch pad (Win+N). Auto-saves every 5 seconds.
; ---------------------------------------------------------------------------
global PadWin := ""
global PadEdit := ""
global PadSearch := ""
global PadFindBtn := ""
global PadSearchOn := false
global PadSearchPos := 1
global PadLastSaved := ""
global PadPath := SnowDataDir "\quicknotes.txt"
global PadPosPath := SnowDataDir "\quicknotes_pos.txt"

RegHotkey("#n", "Snow Pad: scratch notes, auto-saves (Ctrl+F finds)", PadToggle)

PadBuild() {
    global PadWin, PadEdit, PadSearch, PadFindBtn
    PadWin := SnowWin("SNOW PAD", 60, 24, "+Resize +MinSize330x210")
    PadSearch := PadWin.g.Add("Edit", "x" PadWin.X(2) " y" PadWin.Y(1) " w" PadWin.X(40) " r1 -E0x200 Hidden Background" THEME_FIELD " c" THEME_FG_HI)
    PadFindBtn := PadWin.Btn(44, 1, "[find]", PadFindNext)
    PadFindBtn.Visible := false
    PadEdit := PadWin.g.Add("Edit", "x" PadWin.X(1) " y" PadWin.Y(1) " w" PadWin.X(58) " h" PadWin.Y(20) " Multi WantTab VScroll -E0x200 Background" THEME_FIELD " c" THEME_FG)
    DarkScrollbar(PadEdit)
    PadWin.onLayout := PadLayout
    PadWin.onClose := PadClose
}

PadLayout(cols, rows) {
    global PadWin, PadEdit, PadSearch, PadFindBtn, PadSearchOn
    top := PadSearchOn ? 2 : 1
    PadSearch.Move(PadWin.X(2), PadWin.Y(1), PadWin.X(cols - 12))
    PadFindBtn.Move(PadWin.X(cols - 9), PadWin.Y(1))
    PadEdit.Move(PadWin.X(1), PadWin.Y(top), PadWin.X(cols - 2), PadWin.Y(rows - top - 1))
}

PadToggle(*) {
    global PadWin, PadEdit, PadLastSaved, PadPath, PadPosPath
    if (PadWin = "")
        PadBuild()
    if PadWin.IsVisible() {
        PadClose()
        return
    }
    try {
        if FileExist(PadPath)
            PadEdit.Value := FileRead(PadPath, "UTF-8")
    }
    PadLastSaved := PadEdit.Value
    pos := "x" (A_ScreenWidth - PadWin.X(60) - 40) " y80"
    try {
        if FileExist(PadPosPath) {
            parts := StrSplit(Trim(FileRead(PadPosPath), " `r`n"), ",")
            if (parts.Length >= 4) {
                px := Integer(parts[1])
                py := Integer(parts[2])
                pw := Max(330, Integer(parts[3]))
                ph := Max(210, Integer(parts[4]))
                ClampToScreen(&px, &py, pw, ph)    ; saved monitor may be gone
                pos := "x" px " y" py " w" pw " h" ph
            }
        }
    } catch as err {
        SnowLog("snow pad position load failed: " err.Message)
    }
    ; Resizable: the saved size wins over the cell-grid default size.
    if InStr(pos, " w")
        PadWin.g.Show(pos)
    else
        PadWin.Show(pos)
    PadEdit.Focus()
    PadUpdateStatus()
    SetTimer(PadAutoSave, 5000)
}

PadClose(*) {
    global PadWin
    PadSave(true)
    SetTimer(PadAutoSave, 0)
    PadWin.Hide()
}

PadAutoSave() {
    global PadWin
    if (PadWin = "" || !PadWin.IsVisible()) {
        SetTimer(PadAutoSave, 0)
        return
    }
    PadSave()
}

PadSave(force := false) {
    global PadWin, PadEdit, PadLastSaved, PadPath, PadPosPath
    try {
        DirCreate(SnowDataDir)
        content := PadEdit.Value
        if (content != PadLastSaved || force) {
            f := FileOpen(PadPath, "w", "UTF-8")
            f.Write(content)
            f.Close()
            PadLastSaved := content
        }
        WinGetPos(&px, &py, , , PadWin.g)
        WinGetClientPos(, , &pw, &ph, PadWin.g)
        f := FileOpen(PadPosPath, "w", "UTF-8")
        f.Write(px "," py "," pw "," ph)
        f.Close()
    } catch as err {
        SnowLog("snow pad save failed: " err.Message)
    }
    PadUpdateStatus()
}

PadUpdateStatus() {
    global PadWin, PadEdit
    content := PadEdit.Value
    RegExReplace(content, "\S+", "", &words)
    RegExReplace(content, "\n", "", &breaks)
    PadWin.SetStatus(StrLen(content) " chars " GL_DOT " " words " words " GL_DOT " " (breaks + 1) " lines " GL_DOT " autosave")
}

PadActive() {
    global PadWin
    return (PadWin != "") && PadWin.IsActive()
}

PadSearchFocused() {
    global PadWin, PadSearch
    return PadActive() && (PadWin.g.FocusedCtrl = PadSearch)
}

PadToggleSearch() {
    global PadWin, PadSearch, PadFindBtn, PadSearchOn, PadSearchPos
    PadSearchOn := !PadSearchOn
    PadSearch.Visible := PadSearchOn
    PadFindBtn.Visible := PadSearchOn
    PadLayout(PadWin.cols, PadWin.rows)
    if PadSearchOn {
        PadSearch.Focus()
        PadSearchPos := 1
    }
}

PadFindNext(*) {
    global PadEdit, PadSearch, PadSearchPos
    needle := PadSearch.Value
    if (needle = "")
        return
    haystack := PadEdit.Value
    pos := InStr(haystack, needle, false, PadSearchPos)
    if (pos = 0) {
        PadSearchPos := 1
        pos := InStr(haystack, needle, false, 1)
    }
    if (pos > 0) {
        SendMessage(0xB1, pos - 1, pos - 1 + StrLen(needle), PadEdit.Hwnd)   ; EM_SETSEL
        SendMessage(0xB7, 0, 0, PadEdit.Hwnd)                                 ; EM_SCROLLCARET
        PadSearchPos := pos + 1
    }
}

#HotIf PadActive()
^f::PadToggleSearch()
#HotIf PadSearchFocused()
Enter::PadFindNext()
#HotIf

; ---------------------------------------------------------------------------
; STICKY NOTES - any number of small always-on-top notes (Alt+N makes a new one).
; Each note is one file in stickies\: first line "x,y,w,h", then the text.
; ---------------------------------------------------------------------------
global StickyNotes := Map()
global StickyNextId := 1
global StickyDir := SnowDataDir "\stickies\"

RegHotkey("!n", "Snow Note: new sticky note", StickyNew)

StickyCreate(id, x, y, content := "", w := 270, h := 210) {
    global StickyNotes, StickyDir
    m := SnowMeasure()
    win := SnowWin("NOTE", Max(22, w // m.cw), Max(8, h // m.ch), "+Resize +MinSize165x120")
    ed := win.g.Add("Edit", "x" win.X(1) " y" win.Y(1) " w" win.X(win.cols - 2) " h" win.Y(win.rows - 2)
        . " Multi WantTab VScroll -E0x200 Background" THEME_FIELD " c" THEME_FG, content)
    DarkScrollbar(ed)
    win.onLayout := (cols, rows) => ed.Move(win.X(1), win.Y(1), win.X(cols - 2), win.Y(rows - 2))
    win.onClose := (*) => StickyClose(id)
    ClampToScreen(&x, &y, win.cols * win.cw, win.rows * win.ch)    ; saved monitor may be gone
    win.Show("x" x " y" y " NoActivate")
    StickyNotes[id] := {win: win, edit: ed, path: StickyDir id ".txt", last: ""}
}

StickyNew(*) {
    global StickyNextId, StickyNotes
    offset := StickyNotes.Count * 30
    StickyCreate(StickyNextId, (A_ScreenWidth // 2 - 125) + offset, (A_ScreenHeight // 2 - 100) + offset)
    StickyNextId++
}

StickyClose(id) {
    global StickyNotes
    if !StickyNotes.Has(id)
        return
    note := StickyNotes[id]
    if (note.edit.Value != "") {
        if (MsgBox("Delete this Snow Note?", "*  Snow Tools  *", "YesNo 0x40000 T10") != "Yes")
            return
    }
    try note.win.g.Destroy()
    try FileDelete(note.path)
    StickyNotes.Delete(id)
}

StickySaveAll() {
    global StickyNotes, StickyDir
    for id, note in StickyNotes {
        try {
            WinGetPos(&sx, &sy, , , note.win.g)
            WinGetClientPos(, , &sw, &sh, note.win.g)
            data := sx "," sy "," sw "," sh "`n" note.edit.Value
            if (data = note.last)
                continue
            if !DirExist(StickyDir)
                DirCreate(StickyDir)
            f := FileOpen(note.path, "w", "UTF-8")
            f.Write(data)
            f.Close()
            note.last := data
        } catch as err {
            SnowLog("sticky save failed (" id "): " err.Message)
        }
    }
}

StickyLoadAll() {
    global StickyDir, StickyNextId
    if !DirExist(StickyDir)
        return
    Loop Files StickyDir "*.txt" {
        try {
            raw := FileRead(A_LoopFileFullPath, "UTF-8")
            firstNL := InStr(raw, "`n")
            if (!firstNL)
                continue
            parts := StrSplit(Trim(SubStr(raw, 1, firstNL - 1), " `r`n"), ",")
            id := StrReplace(A_LoopFileName, ".txt")
            StickyCreate(id, Integer(parts[1]), Integer(parts[2]), SubStr(raw, firstNL + 1)
                , parts.Length >= 3 ? Integer(parts[3]) : 270, parts.Length >= 4 ? Integer(parts[4]) : 210)
            if (IsInteger(id) && Integer(id) >= StickyNextId)
                StickyNextId := Integer(id) + 1
        }
    }
}

; Delete the pad text, its saved position and every sticky note, open or saved. Used by
; "Delete all data" in Settings; no confirmation here.
NotesClearAll() {
    global PadWin, PadEdit, PadLastSaved, PadPath, PadPosPath, StickyNotes, StickyDir
    SetTimer(PadAutoSave, 0)
    if (PadWin != "") {
        PadEdit.Value := ""
        PadLastSaved := ""
        PadWin.Hide()
    }
    for id, note in StickyNotes
        try note.win.g.Destroy()
    StickyNotes.Clear()
    try DirDelete(StickyDir, true)
    try FileDelete(PadPath)
    try FileDelete(PadPosPath)
}

; Short description of what the notes hold, for the Settings window: "pad + 2 sticky".
NotesSummary() {
    global PadPath, StickyNotes
    pad := FileExist(PadPath) && FileGetSize(PadPath) > 0
    return (pad ? "pad" : "empty pad") " + " StickyNotes.Count " sticky"
}

StickyLoadAll()
SetTimer(StickySaveAll, 5000)

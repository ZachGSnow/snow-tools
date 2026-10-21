; ===== SNIPPETS =====
; Text expansions managed in an editor (Alt+S) and stored in data\snippets.txt:
;     trigger = text
; In the file, "\n" is a new line, "\t" a tab and "\\" a backslash. Lines starting with #
; are comments. Text may contain tokens that are filled in when you type the trigger:
;     {date}  {tomorrow}  {time}  {cursor} (where the caret ends up)
; Triggers fire as soon as they're typed (no end character) and ignore case. Saving in
; the editor re-registers everything immediately; no reload needed.

global SnipPath := SnowDataDir "\snippets.txt"
global Snippets := []          ; [{trigger, text}]
global SnipLive := Map()       ; lower-case trigger -> registered hotstring name
global SnipReserved := []      ; triggers of hotstrings defined elsewhere; the editor warns on a clash

global SnipWin := ""
global SnipList := ""
global SnipTrigger := ""
global SnipText := ""
global SnipWarn := ""
global SnipSelected := 0       ; index into Snippets being edited (0 = a new snippet)
global SnipBusy := false
global SnipAskConfirm := true  ; the self-test turns this off

RegHotkey("!s", "Snippets: add / edit / delete text expansions", SnippetsToggle)

SnippetsLoad()
SnippetsApply()

; ---------------------------------------------------------------------------
; File format
; ---------------------------------------------------------------------------
SnipDefaultFile() {
    return "# Snow Tools snippets - edit here or with Alt+S`n"
        . "# trigger = text      \n = new line   \t = tab   \\ = backslash`n"
        . "# tokens: {date} {tomorrow} {time} {cursor}`n"
        . "zem = you@example.com`n"
        . "zph = 555-0100`n"
        . ":ty = Thanks for reaching out.`n"
        . "cdate = {date}`n"
        . "tdate = {tomorrow}`n"
        . "ctime = {time}`n"
        . "callnote = CALL: {cursor}\nCLIENT:\nSTART:  | END:  | TOTAL:\nSUMMARY:\nACTIONS:\n -\nNEXT:\nSTATUS: PENDING\n---`n"
}

SnipValidTrigger(t) {
    return RegExMatch(t, "^[^\s=]{1,40}$") && !InStr(t, "::")
}

SnipDecode(s) {
    out := ""
    i := 1
    n := StrLen(s)
    while (i <= n) {
        c := SubStr(s, i, 1)
        if (c = "\" && i < n) {
            d := SubStr(s, i + 1, 1)
            if (d = "n") {
                out .= "`n"
                i += 2
                continue
            }
            if (d = "t") {
                out .= "`t"
                i += 2
                continue
            }
            if (d = "\") {
                out .= "\"
                i += 2
                continue
            }
        }
        out .= c
        i++
    }
    return out
}

SnipEncode(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, "`r`n", "\n")
    s := StrReplace(s, "`n", "\n")
    return StrReplace(s, "`t", "\t")
}

SnippetsLoad() {
    global Snippets, SnipPath
    Snippets := []
    if !FileExist(SnipPath) {
        DirCreate(SnowDataDir)
        FileAppend(SnipDefaultFile(), SnipPath, "UTF-8")
    }
    for line in StrSplit(FileRead(SnipPath, "UTF-8"), "`n", "`r") {
        sn := SnipParseLine(line)
        if (sn != "")
            Snippets.Push(sn)
    }
}

; One "trigger = text" line (text still in file encoding) -> {trigger, text}, or "" for a
; blank line, a comment or a line that is not a valid snippet.
SnipParseLine(line) {
    line := LTrim(line)
    if (line = "" || SubStr(line, 1, 1) = "#")
        return ""
    eq := InStr(line, "=")
    if (eq < 2)
        return ""
    trig := Trim(SubStr(line, 1, eq - 1))
    txt := SubStr(line, eq + 1)
    if (SubStr(txt, 1, 1) = " ")
        txt := SubStr(txt, 2)
    if !SnipValidTrigger(trig)
        return ""
    return {trigger: trig, text: SnipDecode(txt)}
}

SnippetsSave() {
    global Snippets, SnipPath
    s := "# Snow Tools snippets - edit here or with Alt+S`n"
        . "# trigger = text      \n = new line   \t = tab   \\ = backslash`n"
        . "# tokens: {date} {tomorrow} {time} {cursor}`n"
    for sn in Snippets
        s .= sn.trigger " = " SnipEncode(sn.text) "`n"
    f := FileOpen(SnipPath, "w", "UTF-8")
    f.Write(s)
    f.Close()
}

; Replace the snippets file with the built-in defaults and apply them immediately.
SnippetsResetToDefaults() {
    global SnipPath, SnipSelected, SnipWin
    try FileDelete(SnipPath)
    SnippetsLoad()
    SnippetsApply()
    SnipSelected := 0
    if (SnipWin != "")
        SnipRefreshList(0)
}

; ---------------------------------------------------------------------------
; Registration
; ---------------------------------------------------------------------------
SnipPreview(text) {
    return RegExReplace(SubStr(text, 1, 70), "\R", " / ")
}

; Types the text, filling in tokens and placing the caret at {cursor}.
SnipExpand(text, *) {
    text := StrReplace(text, "{date}", FormatTime(, "yyyy-MM-dd"))
    text := StrReplace(text, "{tomorrow}", FormatTime(DateAdd(A_Now, 1, "days"), "yyyy-MM-dd"))
    text := StrReplace(text, "{time}", FormatTime(, "HH:mm"))
    pos := InStr(text, "{cursor}")
    if !pos {
        SendText(text)
        return
    }
    before := SubStr(text, 1, pos - 1)
    after := StrReplace(SubStr(text, pos + 8), "{cursor}", "")
    SendText(before after)
    RegExReplace(after, "\n", "", &ups)
    if (ups > 0) {
        lastNL := InStr(before, "`n", , -1)
        col := StrLen(before) - lastNL
        Send("{Up " ups "}{Home}" (col > 0 ? "{Right " col "}" : ""))
    } else if (StrLen(after) > 0) {
        Send("{Left " StrLen(after) "}")
    }
}

; (Re)register every snippet as a hotstring and refresh the HUD's list.
SnippetsApply() {
    global Snippets, SnipLive, SnowRegistry
    i := SnowRegistry.Length
    while (i >= 1) {
        if SnowRegistry[i].HasOwnProp("snippet")
            SnowRegistry.RemoveAt(i)
        i--
    }
    newLive := Map()
    for sn in Snippets {
        key := StrLower(sn.trigger)
        if newLive.Has(key)
            continue                      ; duplicate in the file: the first one wins
        needsFn := InStr(sn.text, "`n") || RegExMatch(sn.text, "\{(date|tomorrow|time|cursor)\}")
        name := ":" (needsFn ? "*C1" : "*C1T") ":" sn.trigger
        try {
            if needsFn
                Hotstring(name, SnipExpand.Bind(sn.text), "On")
            else
                Hotstring(name, sn.text, "On")
            newLive[key] := name
            SnowRegistry.Push({kind: "hotstring", key: sn.trigger, desc: SnipPreview(sn.text), snippet: true})
        } catch as err {
            SnowLog("snippet '" sn.trigger "' could not be registered: " err.Message)
        }
    }
    for key, name in SnipLive {
        if (!newLive.Has(key) || newLive[key] != name) {
            try Hotstring(name, , "Off")
        }
    }
    SnipLive := newLive
    SnipHudInvalidate()
}

; The HUD is built from the registry, so drop it; it rebuilds the next time it's shown.
SnipHudInvalidate() {
    global HudWin
    if (IsSet(HudWin) && HudWin != "") {
        try HudWin.g.Destroy()
        HudWin := ""
    }
}

; Warning text if this trigger would clash with another snippet or a built-in, else "".
SnipConflict(trig, skipIndex) {
    global Snippets, SnipReserved
    a := StrLower(trig)
    if (a = "")
        return ""
    for r in SnipReserved {
        if (StrLower(r) = a)
            return "'" r "' is already used by a built-in hotstring."
    }
    for i, sn in Snippets {
        if (i = skipIndex)
            continue
        b := StrLower(sn.trigger)
        if (a != b && InStr(b, a) = 1)
            return "'" trig "' is the start of '" sn.trigger "' - that one could never fire."
        if (a != b && InStr(a, b) = 1)
            return "'" sn.trigger "' fires first while you type '" trig "'."
    }
    return ""
}

; ---------------------------------------------------------------------------
; Editor window
; ---------------------------------------------------------------------------
SnipBuild() {
    global SnipWin, SnipList, SnipTrigger, SnipText, SnipWarn
    w := SnowWin("SNIPPETS", 96, 27)
    SnipWin := w
    w.Put(2, 1, "TRIGGERS", THEME_ACCENT)
    w.Put(35, 1, "EDITOR", THEME_ACCENT)
    w.Rule(2, 33, GL_DJ)

    SnipList := w.Add("ListView", 1, 3, 32, 21, "-Hdr -Multi +LV0x10000 -E0x200 Background" THEME_FIELD " c" THEME_FG, ["trigger", "text"])
    SnipList.ModifyCol(1, 11 * w.cw)
    SnipList.ModifyCol(2, 32 * w.cw - 11 * w.cw - 24)
    DarkScrollbar(SnipList)
    SnipList.OnEvent("ItemSelect", SnipOnSelect)
    SnipList.OnNotify(-12, SnowListDraw)
    w.VLine(33, 3, 23)

    w.Put(35, 3, "trigger (what you type)", THEME_FG_DIM)
    SnipTrigger := w.g.Add("Edit", "x" w.X(35) " y" w.Y(4) " w" w.X(40) " r1 -E0x200 Background" THEME_FIELD " c" THEME_FG_HI)
    SnipTrigger.OnEvent("Change", SnipOnTriggerChange)
    w.Put(35, 6, "text  ({date} {tomorrow} {time} {cursor})", THEME_FG_DIM)
    SnipText := w.Add("Edit", 35, 7, 59, 13, "Multi WantReturn WantTab VScroll -E0x200 Background" THEME_FIELD " c" THEME_FG)
    DarkScrollbar(SnipText)
    SnipWarn := w.Add("Text", 35, 20, 59, 3, "0x80 c" THEME_ALERT, "")

    w.Rule(24, 33, GL_UJ)
    w.Btn(2, 25, "[NEW]", SnipNew)
    w.Btn(10, 25, "[SAVE ^S]", SnipSave)
    w.Btn(22, 25, "[DELETE]", SnipDelete)
    w.Btn(33, 25, "[OPEN FILE]", SnipOpenFile)
}

SnippetsToggle(*) {
    global SnipWin, SnipList
    if (SnipWin = "")
        SnipBuild()
    if SnipWin.IsVisible() {
        SnipWin.Hide()
        return
    }
    SnipRefreshList(SnipSelected)
    SnipWin.Show()
    SnipList.Focus()
}

SnipActive() {
    global SnipWin
    return (SnipWin != "") && SnipWin.IsActive()
}

SnipRefreshList(select := 0) {
    global SnipWin, SnipList, Snippets, SnipBusy
    SnipBusy := true
    SnipList.Opt("-Redraw")
    SnipList.Delete()
    for sn in Snippets
        SnipList.Add(, sn.trigger, SnipPreview(sn.text))
    SnipList.Opt("+Redraw")
    SnipBusy := false
    if (select >= 1 && select <= Snippets.Length) {
        SnipList.Modify(select, "Select Focus Vis")
        SnipLoadFields(select)
    } else {
        SnipLoadFields(0)
    }
    SnipWin.SetStatus(Snippets.Length " snippets")
}

SnipLoadFields(i) {
    global Snippets, SnipSelected, SnipTrigger, SnipText, SnipWarn
    SnipSelected := i
    if (i >= 1 && i <= Snippets.Length) {
        SnipTrigger.Value := Snippets[i].trigger
        SnipText.Value := StrReplace(Snippets[i].text, "`n", "`r`n")
    } else {
        SnipTrigger.Value := ""
        SnipText.Value := ""
    }
    SnipWarn.Value := ""
}

SnipOnSelect(ctrl, row, selected) {
    global SnipBusy
    if (selected && !SnipBusy)
        SnipLoadFields(row)
}

SnipOnTriggerChange(*) {
    global SnipTrigger, SnipSelected, SnipWarn
    SnipWarn.Value := SnipConflict(Trim(SnipTrigger.Value), SnipSelected)
}

SnipNew(*) {
    global SnipList, SnipTrigger
    SnipList.Modify(0, "-Select")
    SnipLoadFields(0)
    SnipTrigger.Focus()
}

; Validates and stores the editor's contents. Returns true if saved.
SnipSave(*) {
    global Snippets, SnipSelected, SnipTrigger, SnipText, SnipWarn, SnipWin
    trig := Trim(SnipTrigger.Value)
    txt := StrReplace(SnipText.Value, "`r`n", "`n")
    if !SnipValidTrigger(trig) {
        SnipWarn.Value := "Trigger can't be empty or contain spaces, '=' or '::'."
        return false
    }
    if (txt = "") {
        SnipWarn.Value := "Text can't be empty."
        return false
    }
    for i, sn in Snippets {
        if (i != SnipSelected && StrLower(sn.trigger) = StrLower(trig)) {
            SnipWarn.Value := "'" sn.trigger "' already exists - select it in the list to edit it."
            return false
        }
    }
    conflict := SnipConflict(trig, SnipSelected)
    entry := {trigger: trig, text: txt}
    if (SnipSelected >= 1 && SnipSelected <= Snippets.Length)
        Snippets[SnipSelected] := entry
    else {
        Snippets.Push(entry)
        SnipSelected := Snippets.Length
    }
    SnippetsSave()
    SnippetsApply()
    SnipRefreshList(SnipSelected)
    SnipWarn.Value := (conflict != "") ? "Saved. Note: " conflict : ""
    return true
}

SnipDelete(*) {
    global Snippets, SnipSelected, SnipAskConfirm
    if (SnipSelected < 1 || SnipSelected > Snippets.Length)
        return
    if (SnipAskConfirm && MsgBox("Delete snippet '" Snippets[SnipSelected].trigger "'?", "*  Snow Tools  *", "YesNo 0x40000") != "Yes")
        return
    Snippets.RemoveAt(SnipSelected)
    SnipSelected := 0
    SnippetsSave()
    SnippetsApply()
    SnipRefreshList(0)
}

SnipOpenFile(*) {
    global SnipPath
    Run('notepad "' SnipPath '"')
}

#HotIf SnipActive()
^s::SnipSave()
#HotIf

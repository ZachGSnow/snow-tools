; ===== SETTINGS EXPORT AND IMPORT =====
; One plain-text file holds your preferences and snippets so they can move to another
; machine or be restored. The file is untrusted input when imported: it is parsed strictly
; (known preferences only, valid triggers only, size limits), summarized first, and your
; current settings are backed up before anything changes. Clips and notes are data, not
; settings, and are never exported.
;
;     # comments
;     format = 1
;     [prefs]
;     clips.skipsensitive = 1
;     [snippets]
;     trigger = text            (same encoding as data\snippets.txt)

global TRANSFER_FORMAT := 1
global TRANSFER_MAX_BYTES := 1048576
global TRANSFER_MAX_SNIPPETS := 2000
global TRANSFER_MAX_TEXT := 20000
global TRANSFER_KEEP_BACKUPS := 10
global TransferBackupDir := SnowDataDir "\backup"

; ---------------------------------------------------------------------------
; Export
; ---------------------------------------------------------------------------
TransferExportText() {
    global Snippets, SnowPrefDefaults, TRANSFER_FORMAT
    s := "# Snow Tools settings`n"
        . "# Plain text. Review it before sharing: snippets may contain private text.`n"
        . "format = " TRANSFER_FORMAT "`n"
        . "exported = " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n`n"
        . "[prefs]`n"
    for name, def in SnowPrefDefaults
        s .= name " = " SnowPrefGet(name) "`n"
    s .= "`n[snippets]`n"
    for sn in Snippets
        s .= sn.trigger " = " SnipEncode(sn.text) "`n"
    return s
}

TransferExportFile(path) {
    f := FileOpen(path, "w", "UTF-8")
    if !IsObject(f)
        throw Error("Could not open the file for writing")
    f.Write(TransferExportText())
    f.Close()
}

; ---------------------------------------------------------------------------
; Parse (pure: reads text, changes nothing)
; ---------------------------------------------------------------------------
; Returns {ok, error, format, prefs: Map name->"0"/"1", snippets: [{trigger, text}],
; ignored: [reasons]}. Anything it does not recognise is skipped and listed, never applied.
TransferParse(text) {
    global SnowPrefDefaults, TRANSFER_FORMAT, TRANSFER_MAX_BYTES, TRANSFER_MAX_SNIPPETS, TRANSFER_MAX_TEXT
    res := {ok: false, error: "", format: 0, prefs: Map(), snippets: [], ignored: []}
    if (StrLen(text) > TRANSFER_MAX_BYTES) {
        res.error := "The file is larger than 1 MB, so it is not a settings export."
        return res
    }
    Ignore(reason) {
        if (res.ignored.Length < 200)
            res.ignored.Push(reason)
    }
    section := ""
    seen := Map()
    for line in StrSplit(text, "`n", "`r") {
        t := Trim(line)
        if (t = "" || SubStr(t, 1, 1) = "#")
            continue
        if RegExMatch(t, "^\[([^\]=]+)\]$", &m) {
            section := StrLower(Trim(m[1]))
            if (section != "prefs" && section != "snippets")
                Ignore("section [" section "] is not supported by this version")
            continue
        }
        if (section = "") {
            if RegExMatch(t, "i)^format\s*=\s*(\d+)\s*$", &fm)
                res.format := Integer(fm[1])
            continue    ; other header lines (exported = ...) are informational
        }
        if (section = "prefs") {
            eq := InStr(t, "=")
            if (eq < 2) {
                Ignore("unreadable preference line")
                continue
            }
            name := Trim(SubStr(t, 1, eq - 1))
            value := Trim(SubStr(t, eq + 1))
            if !SnowPrefDefaults.Has(name) {
                Ignore("unknown preference " name)
            } else if !RegExMatch(value, "^[01]$") {
                Ignore("bad value for " name)
            } else {
                res.prefs[name] := value
            }
        } else if (section = "snippets") {
            sn := SnipParseLine(line)
            if (sn = "") {
                Ignore("invalid snippet line")
                continue
            }
            key := StrLower(sn.trigger)
            if seen.Has(key) {
                Ignore("duplicate trigger " sn.trigger)
            } else if (StrLen(sn.text) > TRANSFER_MAX_TEXT) {
                Ignore("snippet " sn.trigger " is too long")
            } else if (res.snippets.Length >= TRANSFER_MAX_SNIPPETS) {
                Ignore("too many snippets (limit " TRANSFER_MAX_SNIPPETS ")")
            } else {
                seen[key] := true
                res.snippets.Push(sn)
            }
        }
    }
    if (res.format = 0) {
        res.error := "This does not look like a Snow Tools settings file (no format line)."
    } else if (res.format > TRANSFER_FORMAT) {
        res.error := "This file was made by a newer version of Snow Tools (format " res.format "). Update first."
    } else {
        res.ok := true
    }
    return res
}

; ---------------------------------------------------------------------------
; Plan (pure: compares a parsed file with the current state)
; ---------------------------------------------------------------------------
TransferPlan(parsed) {
    global Snippets, SnowPrefLabels, SnowPrefRisky
    prefs := []
    for name, value in parsed.prefs {
        current := SnowPrefGet(name)
        if (current = value)
            continue
        risky := SnowPrefRisky.Has(name) && SnowPrefRisky[name] = value
        prefs.Push({name: name, label: SnowPrefLabels[name], from: current, to: value, risky: risky})
    }
    mine := Map()
    for sn in Snippets
        mine[StrLower(sn.trigger)] := sn.text
    theirs := Map()
    added := 0
    changed := 0
    same := 0
    for sn in parsed.snippets {
        key := StrLower(sn.trigger)
        theirs[key] := true
        if !mine.Has(key)
            added++
        else if (mine[key] == sn.text)
            same++
        else
            changed++
    }
    removed := 0
    for key, text in mine
        if !theirs.Has(key)
            removed++
    return {prefs: prefs, snippets: parsed.snippets, added: added, changed: changed, same: same
        , removed: removed, ignored: parsed.ignored}
}

; ---------------------------------------------------------------------------
; Backup and apply
; ---------------------------------------------------------------------------
; Writes the current settings to data\backup\ (newest 10 kept) and returns the path.
TransferBackup() {
    global TransferBackupDir, TRANSFER_KEEP_BACKUPS
    DirCreate(TransferBackupDir)
    base := TransferBackupDir "\settings-" A_Now
    n := 1
    path := base "-01.txt"
    while FileExist(path)
        path := base "-" Format("{:02}", ++n) ".txt"
    TransferExportFile(path)
    names := []
    Loop Files TransferBackupDir "\settings-*.txt"
        names.Push(A_LoopFileName)
    if (names.Length > TRANSFER_KEEP_BACKUPS) {
        sorted := ""
        for nm in names
            sorted .= nm "`n"
        sorted := Sort(RTrim(sorted, "`n"))    ; the timestamps sort oldest first
        list := StrSplit(sorted, "`n")
        Loop list.Length - TRANSFER_KEEP_BACKUPS
            try FileDelete(TransferBackupDir "\" list[A_Index])
    }
    return path
}

; Apply a plan. mode: "merge" (add new snippets, update changed ones, keep the rest) or
; "replace" (the snippets become exactly the file's). Preferences that lower your privacy are
; only applied when allowRisky is true. Returns {ok, message}.
TransferApply(plan, mode, allowRisky := false) {
    global Snippets, SnipWin
    if (mode != "merge" && mode != "replace")
        throw Error("Unknown import mode")
    if (mode = "replace" && plan.snippets.Length = 0)
        return {ok: false, message: "The file has no snippets, so replacing would delete all of yours."}
    TransferBackup()
    applied := 0
    heldBack := 0
    for p in plan.prefs {
        if (p.risky && !allowRisky) {
            heldBack++
            continue
        }
        SnowPrefSet(p.name, p.to)
        applied++
    }
    ClipApplyPrefs()
    if (mode = "replace") {
        Snippets := []
        for sn in plan.snippets
            Snippets.Push({trigger: sn.trigger, text: sn.text})
    } else {
        for sn in plan.snippets {
            found := 0
            for i, mine in Snippets {
                if (StrLower(mine.trigger) = StrLower(sn.trigger)) {
                    found := i
                    break
                }
            }
            if found
                Snippets[found].text := sn.text
            else
                Snippets.Push({trigger: sn.trigger, text: sn.text})
        }
    }
    SnippetsSave()
    SnippetsApply()
    if (SnipWin != "")
        SnipRefreshList(0)
    overlaps := 0
    for i, sn in Snippets
        if (SnipConflict(sn.trigger, i) != "")
            overlaps++
    msg := "Imported: " applied " preferences, " plan.added " snippets added, " plan.changed " updated"
        . (mode = "replace" ? ", " plan.removed " removed" : "") "."
    if heldBack
        msg .= " " heldBack " privacy-lowering setting skipped."
    if overlaps
        msg .= " " overlaps " triggers overlap; check the snippets editor."
    return {ok: true, message: msg}
}

; ---------------------------------------------------------------------------
; Import dialog
; ---------------------------------------------------------------------------
global TransferWin := ""
global TransferInfo := ""
global TransferRiskyBtn := ""
global TransferPlanNow := ""
global TransferAllowRisky := false
global TransferFilePath := ""

TransferError(message) {
    MsgBox(message, "*  Snow Tools  *", "Iconx 0x40000")
}

; Read, parse and summarize a file, then open the dialog. Nothing changes until a button
; in the dialog is pressed.
TransferImportStart(path) {
    global TRANSFER_MAX_BYTES
    try {
        if (FileGetSize(path) > TRANSFER_MAX_BYTES) {
            TransferError("The file is larger than 1 MB, so it is not a settings export.")
            return
        }
        text := FileRead(path, "UTF-8")
    } catch as err {
        TransferError("Could not read the file: " err.Message)
        return
    }
    parsed := TransferParse(text)
    if !parsed.ok {
        TransferError(parsed.error)
        return
    }
    TransferDialog(path, TransferPlan(parsed))
}

TransferSummaryText(path, plan) {
    SplitPath(path, &name)
    s := "File: " name "`n`nPREFERENCES`n"
    if (plan.prefs.Length = 0) {
        s .= "  no changes`n"
    } else {
        for p in plan.prefs
            s .= "  " p.label ": " (p.from = "1" ? "on" : "off") " -> "
                . (p.to = "1" ? "on" : (p.risky ? "OFF  (lowers your privacy)" : "off")) "`n"
    }
    s .= "`nSNIPPETS  (" plan.snippets.Length " in the file)`n"
        . "  " plan.added " new, " plan.changed " changed, " plan.same " identical`n"
        . "  Replace would also remove " plan.removed " of yours that are not in the file.`n"
    if (plan.ignored.Length > 0) {
        s .= "`nSKIPPED  (" plan.ignored.Length " entries not understood)`n"
        Loop Min(3, plan.ignored.Length)
            s .= "  " plan.ignored[A_Index] "`n"
    }
    return RTrim(s, "`n")
}

TransferDialog(path, plan) {
    global TransferWin, TransferInfo, TransferRiskyBtn, TransferPlanNow, TransferAllowRisky, TransferFilePath
    if (TransferWin = "")
        TransferBuild()
    TransferPlanNow := plan
    TransferFilePath := path
    TransferAllowRisky := false
    TransferInfo.Value := TransferSummaryText(path, plan)
    risky := false
    for p in plan.prefs
        if p.risky
            risky := true
    TransferRiskyBtn.Visible := risky
    TransferRefreshRisky()
    TransferWin.Show()
}

TransferBuild() {
    global TransferWin, TransferInfo, TransferRiskyBtn
    w := SnowWin("IMPORT SETTINGS", 80, 22)
    TransferWin := w
    TransferInfo := w.Add("Text", 2, 1, 76, 14, "-Wrap 0x80 c" THEME_FG, "")
    TransferRiskyBtn := w.Btn(2, 15, "[ ] Also apply the settings that lower your privacy (not recommended)", TransferToggleRisky, THEME_ALERT)
    w.Btn(2, 17, "[MERGE snippets]", (*) => TransferChoose("merge"))
    w.Put(21, 17, "add new ones, update changed ones, keep the rest", THEME_FG_DIM)
    w.Btn(2, 18, "[REPLACE snippets]", (*) => TransferChoose("replace"))
    w.Put(21, 18, "your snippets become exactly the file's", THEME_FG_DIM)
    w.Btn(2, 19, "[cancel]", (*) => w.Hide())
    w.Put(2, 20, "A backup of your current settings is saved first (data\backup).", THEME_FG_DIM)
}

TransferToggleRisky(*) {
    global TransferAllowRisky
    TransferAllowRisky := !TransferAllowRisky
    TransferRefreshRisky()
}

TransferRefreshRisky() {
    global TransferRiskyBtn, TransferAllowRisky
    TransferRiskyBtn.Value := (TransferAllowRisky ? "[x]" : "[ ]") " Also apply the settings that lower your privacy (not recommended)"
}

TransferChoose(mode) {
    global TransferWin, TransferPlanNow, TransferAllowRisky
    result := TransferApply(TransferPlanNow, mode, TransferAllowRisky)
    if !result.ok {
        TransferError(result.message)
        return
    }
    TransferWin.Hide()
    SettingsRefresh()
    ClipToast(result.message)
}

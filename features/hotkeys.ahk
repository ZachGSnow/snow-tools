; ===== HOTKEYS =====
; The window for changing the global shortcuts (open it from Settings), and the key capture
; behind it. The rules and the binding live in lib\registry.ahk; this file only asks the
; person for a shortcut and reports what happened.

global HkWin := ""
global HkList := ""
global HkMsg := ""

global CaptureHook := ""
global CaptureMods := ""
global CaptureResult := ""

; ---------------------------------------------------------------------------
; Key capture
; ---------------------------------------------------------------------------
; "^!" and "F9" -> "^!F9". Letters are stored in lower case and "Escape" as "Esc".
HotkeyBuild(mods, keyName) {
    ordered := ""
    for c in ["^", "!", "+", "#"]
        if InStr(mods, c)
            ordered .= c
    if (keyName = "Escape")
        keyName := "Esc"
    if (StrLen(keyName) = 1)
        keyName := StrLower(keyName)
    return ordered keyName
}

; The modifier a virtual-key code stands for ("^", "!", "+", "#"), or "" for any other key.
HotkeyModOf(vk) {
    if (vk = 0x10 || vk = 0xA0 || vk = 0xA1)
        return "+"
    if (vk = 0x11 || vk = 0xA2 || vk = 0xA3)
        return "^"
    if (vk = 0x12 || vk = 0xA4 || vk = 0xA5)
        return "!"
    if (vk = 0x5B || vk = 0x5C)
        return "#"
    return ""
}

; Listen for one shortcut. done(key) is called with text such as "^!F9", or "" when the
; person pressed Esc on its own or nothing happened in time. Every key is swallowed so
; nothing else reacts, and the script's own hotkeys are suspended meanwhile (as a safeguard,
; so that pressing one is captured rather than run). The capture always ends through
; HotkeyCaptureEnd, which resumes them.
HotkeyCaptureStart(done, seconds := 10) {
    global CaptureHook, CaptureMods, CaptureResult
    HotkeyCaptureStop()
    CaptureMods := ""
    CaptureResult := ""
    Suspend(true)
    try {
        ih := InputHook("T" seconds)
        ih.KeyOpt("{All}", "NS")
        ih.OnKeyDown := HotkeyCaptureDown
        ih.OnKeyUp := HotkeyCaptureUp
        ih.OnEnd := HotkeyCaptureEnd.Bind(done)
        CaptureHook := ih
        ih.Start()
    } catch as err {
        Suspend(false)
        CaptureHook := ""
        throw err
    }
}

HotkeyCaptureStop() {
    global CaptureHook
    if (CaptureHook != "")
        try CaptureHook.Stop()
}

HotkeyCaptureDown(ih, vk, sc) {
    global CaptureMods, CaptureResult
    mod := HotkeyModOf(vk)
    if (mod != "") {
        if !InStr(CaptureMods, mod)
            CaptureMods .= mod
        return
    }
    name := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    CaptureResult := (name = "Escape" && CaptureMods = "") ? "" : HotkeyBuild(CaptureMods, name)
    ih.Stop()
}

HotkeyCaptureUp(ih, vk, sc) {
    global CaptureMods
    mod := HotkeyModOf(vk)
    if (mod != "")
        CaptureMods := StrReplace(CaptureMods, mod)
}

HotkeyCaptureEnd(done, ih) {
    global CaptureHook, CaptureResult
    Suspend(false)
    CaptureHook := ""
    done(CaptureResult)
}

; ---------------------------------------------------------------------------
; Window
; ---------------------------------------------------------------------------
HotkeysBuild() {
    global HkWin, HkList, HkMsg
    w := SnowWin("HOTKEYS", 90, 20)
    HkWin := w
    w.onClose := HotkeysClose
    w.Put(2, 1, "Pick one, press CHANGE, then press the new shortcut. Changes apply at once.", THEME_FG_DIM)
    w.Put(3, 3, "shortcut for", THEME_ACCENT)
    w.Put(56, 3, "now", THEME_ACCENT)
    w.Put(74, 3, "default", THEME_ACCENT)
    HkList := w.Add("ListView", 1, 4, 88, 10, "-Hdr -Multi +LV0x10000 -E0x200 Background" THEME_FIELD " c" THEME_FG, ["what", "now", "default"])
    HkList.ModifyCol(1, 54 * w.cw)
    HkList.ModifyCol(2, 18 * w.cw)
    HkList.ModifyCol(3, 16 * w.cw - 24)
    DarkScrollbar(HkList)
    HkList.OnNotify(-12, SnowListDraw)
    HkList.OnEvent("DoubleClick", (*) => HotkeysChange())
    w.Rule(14)
    HkMsg := w.Add("Text", 2, 15, 86, 2, "0x80 c" THEME_FG_DIM, "")
    w.Btn(2, 18, "[CHANGE]", HotkeysChange)
    w.Btn(13, 18, "[RESET]", HotkeysReset)
    w.Btn(23, 18, "[RESET ALL]", (*) => HotkeysResetEveryone())
    w.SetStatus("esc closes")
}

HotkeysToggle(*) {
    global HkWin
    if (HkWin = "")
        HotkeysBuild()
    if HkWin.IsVisible() {
        HotkeysClose()
        return
    }
    HotkeysSay("")
    HotkeysRefresh(1)
    HkWin.Show()
    HkList.Focus()
}

HotkeysClose(*) {
    global HkWin
    HotkeyCaptureStop()
    HkWin.Hide()
}

HotkeysSay(text, bad := false) {
    global HkMsg
    HkMsg.SetFont("c" (bad ? THEME_ALERT : THEME_FG))
    HkMsg.Value := text
}

HotkeysRefresh(select := 0) {
    global HkList, SnowHotkeys, SnowHotkeyOrder
    HkList.Opt("-Redraw")
    HkList.Delete()
    for id in SnowHotkeyOrder {
        hk := SnowHotkeys[id]
        changed := HotkeyNormalize(hk.key) != HotkeyNormalize(hk.default)
        HkList.Add(, hk.desc, HotkeyLabel(hk.key) (changed ? " *" : ""), HotkeyLabel(hk.default))
    }
    HkList.Opt("+Redraw")
    if (select >= 1 && select <= SnowHotkeyOrder.Length)
        HkList.Modify(select, "Select Focus Vis")
}

; The id of the selected row, or "".
HotkeysSelected() {
    global HkList, SnowHotkeyOrder
    row := HkList.GetNext(0)
    return (row >= 1 && row <= SnowHotkeyOrder.Length) ? SnowHotkeyOrder[row] : ""
}

HotkeysChange(*) {
    global SnowHotkeys, CaptureHook
    id := HotkeysSelected()
    if (id = "" || CaptureHook != "")
        return
    HotkeysSay("Press the new shortcut for: " SnowHotkeys[id].desc "`n(Esc on its own cancels)")
    HotkeyCaptureStart(HotkeysCaptured.Bind(id))
}

HotkeysCaptured(id, key) {
    global SnowHotkeys, HkList
    row := HkList.GetNext(0)
    if (key = "") {
        HotkeysSay("Cancelled. Nothing changed.")
    } else {
        result := HotkeyRebind(id, key)
        if result.ok
            HotkeysSay(SnowHotkeys[id].desc " is now " HotkeyLabel(SnowHotkeys[id].key) ".")
        else
            HotkeysSay(result.error, true)
    }
    HotkeysRefresh(Max(1, row))
}

HotkeysReset(*) {
    global SnowHotkeys, HkList
    id := HotkeysSelected()
    if (id = "")
        return
    row := HkList.GetNext(0)
    result := HotkeyReset(id)
    if result.ok
        HotkeysSay(SnowHotkeys[id].desc " is back to " HotkeyLabel(SnowHotkeys[id].default) ".")
    else
        HotkeysSay(result.error, true)
    HotkeysRefresh(row)
}

HotkeysResetEveryone() {
    HotkeysResetAll()
    HotkeysSay("Every shortcut is back to its default.")
    HotkeysRefresh(1)
}

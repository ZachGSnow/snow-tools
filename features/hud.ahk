; ===== HUD =====
; Alt+Y: an overlay listing every hotkey, hotstring and automatic behavior, built from
; the registry (lib\registry.ahk). Closes on Esc, Alt+Y or when it loses focus.

global HudWin := ""
global HudStatus := ""

RegHotkey("hud", "!y", "This overlay: every hotkey and hotstring", HudToggle)
OnMessage(0x0006, HudOnActivate)    ; WM_ACTIVATE

HudToggle(*) {
    global HudWin, HudStatus
    if (HudWin = "")
        HudBuild()
    if HudWin.IsVisible() {
        HudWin.Hide()
        return
    }
    HudStatus.Value := "clips: " ClipTexts.Length " txt / " ClipImages.Length " img   " GL_DOT "   notes: " StickyNotes.Count " sticky"
    HudWin.Show()
}

HudOnActivate(wParam, lParam, msg, hwnd) {
    global HudWin
    if (HudWin != "" && hwnd = HudWin.g.Hwnd && (wParam & 0xFFFF) = 0 && HudWin.IsVisible())
        HudWin.Hide()
}

HudBuild() {
    global HudWin, HudStatus, SnowRegistry
    groups := [
        {kind: "hotkey", title: "HOTKEYS", items: []},
        {kind: "hotstring", title: "HOTSTRINGS", items: []},
        {kind: "auto", title: "AUTOMATIC", items: []}
    ]
    keyW := 8
    for r in SnowRegistry {
        for g in groups {
            if (g.kind = r.kind) {
                g.items.Push(r)
                keyW := Max(keyW, StrLen(r.key))
            }
        }
    }
    keyW += 3

    ; Rows: top border, logo block, rule, then each group (title + items + blank), status.
    rows := 13
    for g in groups
        rows += g.items.Length + 2
    rows += 4    ; rule, actions, status, bottom border
    cols := 96

    w := SnowWin("SNOW TOOLS", cols, rows)
    HudWin := w
    w.Banner((cols - StrLen(ART_LOGO[1])) // 2, 2, ART_LOGO, ART_LOGO_COLORS)
    row := 2 + ART_LOGO.Length
    w.PutCentered(row + 1, ART_SUBTITLE, THEME_ACCENT)
    w.PutCentered(row + 2, ART_CREDIT, THEME_FG_DIM)
    row += 4
    w.Rule(row)
    row += 1
    for g in groups {
        if (g.items.Length = 0)
            continue
        w.Put(2, row, g.title, THEME_ACCENT)
        row += 1
        keys := ""
        descs := ""
        for r in g.items {
            keys .= r.key "`n"
            descs .= r.desc "`n"
        }
        keys := RTrim(keys, "`n")
        descs := RTrim(descs, "`n")
        w.Put(3, row, keys, THEME_FG_HI)
        w.Put(3 + keyW, row, descs, THEME_FG)
        row += g.items.Length + 1
    }
    w.Rule(rows - 4)
    col := 2
    for b in [["[snippets  " HotkeyText("snippets") "]", SnippetsToggle]
            , ["[error log]", SnowOpenLog]
            , ["[data folder]", SnowOpenDataFolder]
            , ["[reload script]", (*) => Reload()]
            , ["[settings  " HotkeyText("settings") "]", SettingsToggle]] {
        w.Btn(col, rows - 3, b[1], HudAction.Bind(b[2]))
        col += StrLen(b[1]) + 2
    }
    HudStatus := w.Add("Text", 2, rows - 2, cols - 4, 1, "-Wrap 0x80 c" THEME_FG_DIM, "")
    w.SetStatus("esc or " StrLower(HotkeyText("hud")) " closes")
}

; Footer actions: close the HUD first, then run the action.
HudAction(fn, *) {
    global HudWin
    HudWin.Hide()
    fn()
}

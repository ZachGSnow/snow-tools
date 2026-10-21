; ===== REGISTRY =====
; One list of every hotkey and hotstring, shown by the HUD (Alt+Y). Features register
; through these helpers so the overlay can never drift out of date.

global SnowRegistry := []

; "^!v" -> "Ctrl+Alt+V"
HotkeyLabel(key) {
    mods := ""
    while (key != "") {
        c := SubStr(key, 1, 1)
        if (c = "^")
            mods .= "Ctrl+"
        else if (c = "!")
            mods .= "Alt+"
        else if (c = "+")
            mods .= "Shift+"
        else if (c = "#")
            mods .= "Win+"
        else
            break
        key := SubStr(key, 2)
    }
    return mods StrUpper(SubStr(key, 1, 1)) SubStr(key, 2)
}

; Define a global hotkey and list it in the HUD.
RegHotkey(key, desc, fn) {
    Hotkey(key, fn)
    SnowRegistry.Push({kind: "hotkey", key: HotkeyLabel(key), desc: desc})
}

; List something defined elsewhere (static hotkeys/hotstrings, context-sensitive ones).
RegDoc(kind, key, desc) {
    SnowRegistry.Push({kind: kind, key: key, desc: desc})
}

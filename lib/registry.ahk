; ===== REGISTRY =====
; One list of every hotkey and hotstring, shown by the HUD (Alt+Y). Features register
; through these helpers so the overlay can never drift out of date.
;
; Global hotkeys have an id and a default key. A key you change is stored in
; data\prefs.ini under [hotkeys] and wins over the default at the next start; rebinding
; takes effect immediately.

global SnowRegistry := []
global SnowHotkeys := Map()       ; id -> {id, default, key, desc, fn, entry}
global SnowHotkeyOrder := []      ; ids in registration order (a Map iterates sorted)

; Shortcuts that must keep their normal meaning (see HotkeyNormalize for the notation).
global SnowHotkeyReserved := Map(
    "^c", 1, "^v", 1, "^x", 1, "^z", 1, "^y", 1, "^a", 1,
    "!f4", 1, "!tab", 1, "#tab", 1, "#l", 1, "#d", 1, "#e", 1, "#r", 1,
    "^!delete", 1, "^+esc", 1, "^esc", 1, "!esc", 1
)

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

; One spelling per shortcut, for comparing: modifiers in the order ^ ! + #, key in lower
; case, "Escape" as "esc". Returns "" if the text is not modifiers followed by a key.
HotkeyNormalize(key) {
    if !RegExMatch(key, "^([#!^+]*)(.+)$", &m)
        return ""
    mods := ""
    for c in ["^", "!", "+", "#"]
        if InStr(m[1], c)
            mods .= c
    k := StrLower(m[2])
    return mods (k = "escape" ? "esc" : k)
}

; "" if the shortcut can be used, else a sentence saying why not.
HotkeyCheck(key) {
    global SnowHotkeyReserved
    if !RegExMatch(key, "i)^([#!^+]*)([a-z0-9]|F(?:[1-9]|1\d|2[0-4])|Space|Enter|Tab|Esc|Escape|Backspace|Delete|Insert|Home|End|PgUp|PgDn|Up|Down|Left|Right)$", &m)
        return "That key is not supported. Use a letter, a digit, F1-F24, or a named key such as Space, Enter or Home."
    mods := m[1]
    for c in ["^", "!", "+", "#"]
        if (StrLen(mods) - StrLen(StrReplace(mods, c)) > 1)
            return "Each modifier can only be used once."
    if (!RegExMatch(m[2], "i)^F\d+$") && !RegExMatch(mods, "[\^!#]"))
        return "Add Ctrl, Alt or Win: a shortcut on a plain key would break typing."
    if SnowHotkeyReserved.Has(HotkeyNormalize(key))
        return HotkeyLabel(key) " is reserved by Windows or standard editing."
    return ""
}

; The id of the registered hotkey that uses this shortcut (other than exceptId), or "".
HotkeyOwner(normKey, exceptId := "") {
    global SnowHotkeys
    for id, hk in SnowHotkeys
        if (id != exceptId && HotkeyNormalize(hk.key) = normKey)
            return id
    return ""
}

HotkeyText(id) {
    global SnowHotkeys
    return SnowHotkeys.Has(id) ? HotkeyLabel(SnowHotkeys[id].key) : ""
}

; Define a global hotkey and list it in the HUD. id is a short stable name ("pad"), key the
; default. A saved choice for this id replaces the default when it is still valid.
RegHotkey(id, defaultKey, desc, fn) {
    global SnowHotkeys, SnowHotkeyOrder, SnowRegistry
    key := defaultKey
    stored := HotkeyStored(id)
    if (stored != "") {
        problem := HotkeyCheck(stored)
        if (problem = "" && HotkeyOwner(HotkeyNormalize(stored), id) = "")
            key := stored
        else
            SnowLog("saved hotkey for " id " ignored: " (problem != "" ? problem : "already in use"))
    }
    Hotkey(key, fn)
    entry := {kind: "hotkey", key: HotkeyLabel(key), desc: desc, id: id}
    SnowRegistry.Push(entry)
    SnowHotkeys[id] := {id: id, default: defaultKey, key: key, desc: desc, fn: fn, entry: entry}
    SnowHotkeyOrder.Push(id)
}

; Move a registered hotkey to a new shortcut, live. Returns {ok, error}.
HotkeyRebind(id, newKey) {
    global SnowHotkeys
    if !SnowHotkeys.Has(id)
        throw Error("Unknown hotkey id: " id)
    hk := SnowHotkeys[id]
    problem := HotkeyCheck(newKey)
    if (problem != "")
        return {ok: false, error: problem}
    norm := HotkeyNormalize(newKey)
    if (norm = HotkeyNormalize(hk.key))
        return {ok: true, error: ""}
    owner := HotkeyOwner(norm, id)
    if (owner != "")
        return {ok: false, error: HotkeyLabel(newKey) " is already used by: " SnowHotkeys[owner].desc}
    try {
        Hotkey(newKey, hk.fn, "On")
    } catch as err {
        return {ok: false, error: "Windows would not accept that shortcut: " err.Message}
    }
    try Hotkey(hk.key, "Off")
    hk.key := newKey
    hk.entry.key := HotkeyLabel(newKey)
    HotkeyStore(id)
    HotkeyRefreshUI()
    return {ok: true, error: ""}
}

; Move several hotkeys at once, e.g. [{id, key}, ...]. All old shortcuts are released before
; any new one is bound, so two hotkeys can swap keys. The caller has already checked the
; shortcuts (HotkeyCheck) and that no two end up the same. Returns the ids that could not
; be moved; those keep their old shortcut.
HotkeyRebindMany(moves) {
    global SnowHotkeys
    failed := []
    for m in moves
        try Hotkey(SnowHotkeys[m.id].key, "Off")
    for m in moves {
        hk := SnowHotkeys[m.id]
        try {
            Hotkey(m.key, hk.fn, "On")
            hk.key := m.key
            hk.entry.key := HotkeyLabel(m.key)
            HotkeyStore(m.id)
        } catch {
            failed.Push(m.id)
            try Hotkey(hk.key, hk.fn, "On")
        }
    }
    HotkeyRefreshUI()
    return failed
}

HotkeyReset(id) {
    global SnowHotkeys
    return HotkeyRebind(id, SnowHotkeys[id].default)
}

; Every hotkey back to its default. Swaps are safe: all old keys are released first.
HotkeysResetAll() {
    global SnowHotkeys, SnowHotkeyOrder
    for id in SnowHotkeyOrder
        try Hotkey(SnowHotkeys[id].key, "Off")
    for id in SnowHotkeyOrder {
        hk := SnowHotkeys[id]
        Hotkey(hk.default, hk.fn, "On")
        hk.key := hk.default
        hk.entry.key := HotkeyLabel(hk.default)
        HotkeyStore(id)
    }
    HotkeyRefreshUI()
}

; Saved choices live in prefs.ini; a hotkey on its default key has no entry.
HotkeyStored(id) {
    global SnowPrefsPath
    value := ""
    try value := IniRead(SnowPrefsPath, "hotkeys", id, "")
    return value
}

HotkeyStore(id) {
    global SnowHotkeys, SnowPrefsPath
    hk := SnowHotkeys[id]
    try {
        if (HotkeyNormalize(hk.key) = HotkeyNormalize(hk.default)) {
            IniDelete(SnowPrefsPath, "hotkeys", id)
        } else {
            DirCreate(SnowDataDir)
            IniWrite(hk.key, SnowPrefsPath, "hotkeys", id)
        }
    }
}

; Places that print a shortcut are rebuilt: the HUD the next time it opens, the tray now.
HotkeyRefreshUI() {
    try SnipHudInvalidate()
    try SnowTrayInit()
}

; List something defined elsewhere (static hotkeys/hotstrings, context-sensitive ones).
RegDoc(kind, key, desc) {
    SnowRegistry.Push({kind: kind, key: key, desc: desc})
}

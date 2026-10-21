; ===== SETTINGS =====
; Preferences live in data\prefs.ini. Every preference is named "section.key" and must have
; a default below, so a typo in a name fails loudly instead of silently reading nothing.
; Values are cached; SnowPrefSet keeps the cache and the file in step.

global SnowPrefsPath := SnowDataDir "\prefs.ini"
global SnowPrefCache := Map()
global SnowPrefDefaults := Map(
    "clips.autodecimal", "1",       ; START/END time blocks become decimal hours
    "clips.skipsensitive", "1"      ; never record copies flagged by password managers
)

SnowPrefGet(name) {
    global SnowPrefDefaults, SnowPrefCache, SnowPrefsPath
    if SnowPrefCache.Has(name)
        return SnowPrefCache[name]
    def := SnowPrefDefaults[name]
    parts := StrSplit(name, ".")
    value := def
    try value := IniRead(SnowPrefsPath, parts[1], parts[2], def)
    SnowPrefCache[name] := value
    return value
}

SnowPrefBool(name) {
    return SnowPrefGet(name) = "1"
}

SnowPrefSet(name, value) {
    global SnowPrefDefaults, SnowPrefCache, SnowPrefsPath
    if !SnowPrefDefaults.Has(name)
        throw Error("Unknown preference: " name)
    if IsObject(value)
        throw Error("Preference values are strings")
    if (value = true || value = false)
        value := value ? "1" : "0"
    parts := StrSplit(name, ".")
    DirCreate(SnowDataDir)
    IniWrite(value, SnowPrefsPath, parts[1], parts[2])
    SnowPrefCache[name] := String(value)
}

; Forget every saved preference; the defaults apply again.
SnowPrefsReset() {
    global SnowPrefCache, SnowPrefsPath
    try FileDelete(SnowPrefsPath)
    SnowPrefCache := Map()
}

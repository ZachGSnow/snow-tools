; ===== LOG =====
; data\snowtools.log: timestamped errors and notable failures. Capped at ~1 MB (the
; newest half is kept when it fills). Uncaught errors are logged and shown as a tray tip
; instead of a modal dialog, so a hiccup never blocks you mid-call.

global SnowDataDir := A_ScriptDir "\data"
global SnowLogPath := SnowDataDir "\snowtools.log"
global SNOW_LOG_MAX := 1048576

SnowLog(msg) {
    try {
        DirCreate(SnowDataDir)
        if (FileExist(SnowLogPath) && FileGetSize(SnowLogPath) > SNOW_LOG_MAX)
            SnowLogTrim()
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " msg "`n", SnowLogPath, "UTF-8")
    }
}

SnowLogTrim() {
    text := FileRead(SnowLogPath, "UTF-8")
    keep := SubStr(text, -(SNOW_LOG_MAX // 2))
    nl := InStr(keep, "`n")
    if (nl)
        keep := SubStr(keep, nl + 1)       ; drop the partial first line
    f := FileOpen(SnowLogPath, "w", "UTF-8")
    f.Write(keep)
    f.Close()
}

; Global handler for uncaught runtime errors. Returning 1 suppresses AutoHotkey's
; error dialog; the thread that hit the error stops and the script keeps running.
SnowOnError(err, mode) {
    SnowLog("ERROR (" mode ") " err.Message " | " err.What " | " err.File ":" err.Line)
    try TrayTip(SubStr(err.Message, 1, 120), "Snow Tools: error logged", "Iconx")
    return 1
}

OnError(SnowOnError)

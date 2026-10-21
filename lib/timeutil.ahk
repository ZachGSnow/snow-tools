; ===== TIME HELPERS =====
; Shared by Snow Calc and the clipboard manager's START/END time-block conversion.

; Hours between two clock times as a 2-decimal string ("1.25"). Wraps past midnight.
; Throws on out-of-range values.
TimeDiffHours(startH, startM, endH, endM) {
    startH := Integer(startH), startM := Integer(startM)
    endH := Integer(endH), endM := Integer(endM)
    if (startH > 23 || endH > 23 || startM > 59 || endM > 59)
        throw Error("Invalid time value")
    diff := (endH * 60 + endM) - (startH * 60 + startM)
    if (diff < 0)
        diff += 1440
    return Format("{:.2f}", diff / 60)
}

; Same, for compact "HMM" / "HHMM" strings such as 930 or 1415.
TimeDiffCompact(startStr, endStr) {
    return TimeDiffHours(SubStr(startStr, 1, StrLen(startStr) - 2), SubStr(startStr, -2)
        , SubStr(endStr, 1, StrLen(endStr) - 2), SubStr(endStr, -2))
}

; True if the text is essentially only a "START: 1302 | END: 1345" line.
ClipIsOnlyTimeBlock(text) {
    trimmed := Trim(text, " `t`r`n")
    if !RegExMatch(trimmed, "i)START:\s*\d{3,4}\s*\|[^|]*END:\s*\d{3,4}")
        return false
    remainder := RegExReplace(trimmed, "im)^[^\r\n]*START:\s*\d{3,4}[^\r\n]*$", "")
    remainder := Trim(remainder, " `t`r`n|:-")
    return (remainder = "")
}

; Decimal hours from the first START/END block in the text, or "" if none/invalid.
ClipParseTimeBlock(text) {
    try {
        if !RegExMatch(text, "i)START:\s*(\d{3,4})\s*\|[^|]*END:\s*(\d{3,4})", &m)
            return ""
        return TimeDiffCompact(m[1], m[2])
    } catch {
        return ""
    }
}

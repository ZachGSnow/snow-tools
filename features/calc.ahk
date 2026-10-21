; ===== SNOW CALC =====
; Time difference in decimal hours (1100-1115, 9:30-17:05) or plain arithmetic (25-2*3).
; Esc or [x] copies the result and closes.

global CalcWin := ""
global CalcInput := ""
global CalcResult := ""

RegHotkey("!c", "Snow Calc: time diff (1100-1115) and math", CalcToggle)

CalcBuild() {
    global CalcWin, CalcInput, CalcResult
    CalcWin := SnowWin("SNOW CALC", 54, 9)
    CalcWin.onClose := CalcClose
    CalcWin.Put(2, 1, "time: 1100-1115 " GL_DOT " 9:30-17:05      math: 25-2*3", THEME_FG_DIM)
    CalcInput := CalcWin.g.Add("Edit", "x" CalcWin.X(2) " y" CalcWin.Y(2) " w" CalcWin.X(50) " r1 -E0x200 Background" THEME_FIELD " c" THEME_FG_HI)
    CalcInput.OnEvent("Change", (*) => SetTimer(CalcRun, -350))   ; debounce while typing
    CalcWin.Put(2, 5, "=", THEME_ACCENT)
    CalcResult := CalcWin.Add("Text", 4, 5, 48, 1, "-Wrap 0x80 c" THEME_ACCENT, "")
    CalcWin.Btn(2, 7, "[ENTER copy]", CalcCopy)
    CalcWin.Btn(16, 7, "[ESC copy & close]", CalcClose)
}

CalcToggle(*) {
    global CalcWin, CalcInput
    if (CalcWin = "")
        CalcBuild()
    if CalcWin.IsVisible() {
        CalcClose()
        return
    }
    CalcWin.Show()
    CalcInput.Focus()
}

CalcActive() {
    global CalcWin
    return (CalcWin != "") && CalcWin.IsActive()
}

CalcCopy(*) {
    global CalcResult
    text := CalcResult.Value
    if (text != "" && !InStr(text, "Error"))
        A_Clipboard := text
}

CalcClose(*) {
    global CalcWin, CalcInput, CalcResult
    SetTimer(CalcRun, 0)
    CalcCopy()
    CalcInput.Value := ""
    CalcResult.Value := ""
    CalcWin.Hide()
}

CalcRun(*) {
    global CalcInput, CalcResult
    try {
        input := Trim(CalcInput.Value)
        if (input = "" || RegExMatch(input, "[+\-*/(]$")) {
            ; empty, or an expression still ending in an operator - wait for more input
            CalcResult.Value := ""
            return
        }
        if RegExMatch(input, "^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$", &m) {
            CalcResult.Value := TimeDiffHours(m[1], m[2], m[3], m[4])
        } else if RegExMatch(input, "^(\d{3,4})-(\d{3,4})$", &m) {
            CalcResult.Value := TimeDiffCompact(m[1], m[2])
        } else {
            CalcResult.Value := CalcFormatResult(CalcMathEval(input))
        }
    } catch as err {
        CalcResult.Value := "Error: " err.Message
    }
}

#HotIf CalcActive()
Enter::CalcCopy()
NumpadEnter::CalcCopy()
#HotIf

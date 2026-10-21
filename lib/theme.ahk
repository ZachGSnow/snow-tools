; ===== SNOW THEME =====
; Text-mode "keygen" look. Every window is drawn on a monospace character grid:
; frames, titles and labels are Text controls placed at (column, row) cell coordinates,
; so box-drawing characters always line up. Real controls (Edit, ListView, Picture) are
; placed on the same grid with Cell helpers.

; Frame and separator glyphs. Built with Chr() so the source stays plain ASCII.
global GL_H     := Chr(0x2550)    ; horizontal rule
global GL_V     := Chr(0x2551)    ; vertical rule
global GL_TL    := Chr(0x2554)    ; top-left corner
global GL_TR    := Chr(0x2557)    ; top-right corner
global GL_BL    := Chr(0x255A)    ; bottom-left corner
global GL_BR    := Chr(0x255D)    ; bottom-right corner
global GL_LJ    := Chr(0x2560)    ; left junction
global GL_RJ    := Chr(0x2563)    ; right junction
global GL_DJ    := Chr(0x2566)    ; junction pointing down
global GL_UJ    := Chr(0x2569)    ; junction pointing up
global GL_DOT   := Chr(0x00B7)    ; middle dot separator
global GL_ARROW := Chr(0x2192)    ; right arrow

global THEME_BG        := "0d1117"
global THEME_FIELD     := "131c28"
global THEME_FG        := "00c4a7"
global THEME_FG_HI     := "5ff5dc"
global THEME_FG_DIM    := "2a7a72"
global THEME_ACCENT    := "e8a020"
global THEME_ALERT     := "c85a1e"
global THEME_FONT      := "Consolas"
global THEME_FONT_BASE := "s10"

; Enable Windows dark mode for the process (dark scrollbars, menus, etc.)
try {
    uxtheme := DllCall("GetModuleHandle", "Str", "uxtheme", "Ptr")
    SetPreferredAppMode := DllCall("GetProcAddress", "Ptr", uxtheme, "Ptr", 135, "Ptr")
    DllCall(SetPreferredAppMode, "Int", 1)
}

DarkScrollbar(ctrl) {
    DllCall("uxtheme\SetWindowTheme", "Ptr", ctrl.Hwnd, "Str", "DarkMode_Explorer", "Ptr", 0)
}

CreateThemedGui(extraOpts := "") {
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +LastFound " extraOpts)
    g.BackColor := THEME_BG
    g.SetFont(THEME_FONT_BASE " c" THEME_FG, THEME_FONT)
    return g
}

; Width/height in pixels of one character cell for the theme font (measured once).
SnowMeasure() {
    static cw := 0, ch := 0
    if (cw = 0) {
        g := Gui("-Caption +ToolWindow")
        g.SetFont(THEME_FONT_BASE, THEME_FONT)
        probe := g.Add("Text", "x0 y0 -Wrap 0x80", "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM")
        probe.GetPos(, , &w, &h)
        cw := Round(w / 40)
        ch := h
        g.Destroy()
    }
    return {cw: cw, ch: ch}
}

SnowRepeat(str, n) {
    out := ""
    Loop Max(0, n)
        out .= str
    return out
}

; Format an A_Now-style timestamp for list display: HH:mm for today, MM-dd otherwise.
SnowShortTime(ts) {
    if (ts = "")
        return "  --  "
    if (SubStr(ts, 1, 8) = SubStr(A_Now, 1, 8))
        return SubStr(ts, 9, 2) ":" SubStr(ts, 11, 2)
    return SubStr(ts, 5, 2) "-" SubStr(ts, 7, 2)
}

class SnowWin {
    ; title:  text embedded in the top border
    ; cols/rows: initial size in character cells
    ; opts:  extra Gui options ("+Resize +MinSize200x150" makes the frame stretch)
    __New(title, cols, rows, opts := "") {
        m := SnowMeasure()
        this.cw := m.cw
        this.ch := m.ch
        this.title := title
        this.cols := cols
        this.rows := rows
        this.resizable := InStr(opts, "+Resize") ? true : false
        this.onClose := ""
        this.onLayout := ""
        this.statusLen := 0
        this.g := CreateThemedGui(opts)
        this.g.SetFont(THEME_FONT_BASE " c" THEME_FG " Norm", THEME_FONT)
        ; Let the ASCII frame be the only border: no DWM accent border, square corners.
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.g.Hwnd, "UInt", 34, "UInt*", 0xFFFFFFFE, "UInt", 4)
        try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", this.g.Hwnd, "UInt", 33, "UInt*", 1, "UInt", 4)
        this.BuildFrame()
        this.g.OnEvent("Escape", (*) => this.Close())
        if this.resizable
            this.g.OnEvent("Size", (gui, mm, w, h) => this.OnSize(mm, w, h))
    }

    ; ---- grid helpers -------------------------------------------------
    X(col) => col * this.cw
    Y(row) => row * this.ch

    ; Text label at a cell position. Width/height are exact so nothing overlaps.
    Put(col, row, text, color := "", extra := "") {
        lines := StrSplit(text, "`n")
        maxLen := 1
        for l in lines
            maxLen := Max(maxLen, StrLen(l))
        opts := "x" col * this.cw " y" row * this.ch
            . " w" maxLen * this.cw " h" lines.Length * this.ch " -Wrap 0x80"
        if (color != "")
            opts .= " c" color
        return this.g.Add("Text", opts " " extra, text)
    }

    PutCentered(row, text, color := "") {
        return this.Put((this.cols - StrLen(text)) // 2, row, text, color)
    }

    ; Clickable label.
    Btn(col, row, text, fn, color := "") {
        t := this.Put(col, row, text, color != "" ? color : THEME_ACCENT)
        t.OnEvent("Click", (*) => fn())
        return t
    }

    ; Place any control (Edit/ListView/Picture/...) on the grid.
    Add(type, col, row, cols, rows, opts := "", text := "") {
        pos := "x" col * this.cw " y" row * this.ch " w" cols * this.cw " h" rows * this.ch
        return this.g.Add(type, pos " " opts, text)
    }

    ; Move an existing control to a cell rectangle.
    Place(ctrl, col, row, cols, rows) {
        ctrl.Move(col * this.cw, row * this.ch, cols * this.cw, rows * this.ch)
    }

    ; Horizontal divider across a fixed window. jcol/jchar add a junction (e.g. GL_DJ).
    Rule(row, jcol := -1, jchar := "") {
        s := GL_LJ SnowRepeat(GL_H, this.cols - 2) GL_RJ
        if (jcol >= 0)
            s := SubStr(s, 1, jcol) jchar SubStr(s, jcol + 2)
        return this.Put(0, row, s, THEME_FG_DIM)
    }

    ; Vertical divider between two rows (inclusive).
    VLine(col, row1, row2) {
        return this.Put(col, row1, SnowRepeat(GL_V "`n", row2 - row1) GL_V, THEME_FG_DIM)
    }

    ; Multi-line art (array of strings) with one colour per line.
    Banner(col, row, lines, colors) {
        for i, line in lines
            this.Put(col, row + i - 1, line, colors[Min(i, colors.Length)])
        return lines.Length
    }

    ; ---- frame --------------------------------------------------------
    BuildFrame() {
        cw := this.cw
        ch := this.ch
        dim := THEME_FG_DIM
        fill := SnowRepeat(GL_H, 400)

        this.pTopL := this.Put(0, 0, GL_TL GL_H "[ ", dim)
        this.pTitle := this.Put(4, 0, this.title, THEME_ACCENT)
        tcol := 4 + StrLen(this.title)
        this.pTopM := this.Put(tcol, 0, " ]", dim)
        this.titleEnd := tcol + 2
        this.pTopFill := this.g.Add("Text", "x" this.titleEnd * cw " y0 w" cw " h" ch " -Wrap 0x80 c" dim, fill)
        this.pClose := this.Put(this.cols - 5, 0, "[x]", THEME_ACCENT)
        this.pTopEnd := this.Put(this.cols - 2, 0, GL_H GL_TR, dim)

        side := SnowRepeat(GL_V "`n", 200)
        this.pLeft := this.g.Add("Text", "x0 y" ch " w" cw " h" ch " -Wrap 0x80 c" dim, side)
        this.pRight := this.g.Add("Text", "x" (this.cols - 1) * cw " y" ch " w" cw " h" ch " -Wrap 0x80 c" dim, side)

        brow := this.rows - 1
        this.pBotL := this.Put(0, brow, GL_BL GL_H, dim)
        this.pBotStatus := this.g.Add("Text", "x" 2 * cw " y" brow * ch " w" cw " h" ch " -Wrap 0x80 c" THEME_FG, "")
        this.pBotFill := this.g.Add("Text", "x" 2 * cw " y" brow * ch " w" cw " h" ch " -Wrap 0x80 c" dim, fill)
        this.pBotR := this.Put(this.cols - 1, brow, GL_BR, dim)

        ; Drag the window by its top border; [x] closes it.
        for c in [this.pTopL, this.pTitle, this.pTopM, this.pTopFill, this.pTopEnd]
            c.OnEvent("Click", (*) => PostMessage(0xA1, 2, , this.g))
        this.pClose.OnEvent("Click", (*) => this.Close())

        this.Reflow(this.cols * cw, this.rows * ch)
    }

    ; Re-lay the frame for a client area of wPx x hPx (also used for resizable windows).
    Reflow(wPx, hPx) {
        cw := this.cw
        ch := this.ch
        cols := wPx // cw
        rows := hPx // ch
        if (cols < 14 || rows < 4)
            return
        this.cols := cols
        this.rows := rows
        this.pTopFill.Move(, , Max(cw, (cols - 5 - this.titleEnd) * cw))
        this.pClose.Move((cols - 5) * cw)
        this.pTopEnd.Move((cols - 2) * cw)
        this.pLeft.Move(0, ch, cw, (rows - 2) * ch)
        this.pRight.Move((cols - 1) * cw, ch, cw, (rows - 2) * ch)
        brow := (rows - 1) * ch
        this.pBotL.Move(, brow)
        this.pBotStatus.Move(, brow)
        fillCol := 2 + this.statusLen
        this.pBotFill.Move(fillCol * cw, brow, Max(cw, (cols - 1 - fillCol) * cw))
        this.pBotR.Move((cols - 1) * cw, brow)
        if (this.onLayout != "")
            (this.onLayout)(cols, rows)
    }

    ; Text embedded in the bottom border, e.g. "1,284 clips".
    SetStatus(text) {
        len := (text = "") ? 0 : StrLen(text) + 2
        this.statusLen := len
        this.pBotStatus.Value := (text = "") ? "" : " " text " "
        this.pBotStatus.Move(, , Max(1, len) * this.cw)
        fillCol := 2 + len
        this.pBotFill.Move(fillCol * this.cw, , Max(this.cw, (this.cols - 1 - fillCol) * this.cw))
    }

    OnSize(mm, w, h) {
        if (mm = -1 || w <= 0)
            return
        this.Reflow(w, h)
    }

    ; ---- visibility ---------------------------------------------------
    Show(opts := "") {
        w := this.cols * this.cw
        h := this.rows * this.ch
        if !RegExMatch(opts, "i)(^|\s)x-?\d+") {
            opts .= " x" (A_ScreenWidth - w) // 2 " y" Max(10, (A_ScreenHeight - h) // 2)
        }
        this.g.Show("w" w " h" h " " opts)
    }

    Hide() {
        this.g.Hide()
    }

    Close() {
        if (this.onClose != "")
            (this.onClose)()
        else
            this.g.Hide()
    }

    Toggle() {
        if this.IsVisible()
            this.Close()
        else
            this.Show()
    }

    IsVisible() => DllCall("IsWindowVisible", "Ptr", this.g.Hwnd) ? true : false
    IsActive() => WinActive("ahk_id " this.g.Hwnd) ? true : false
}

; Move a window rectangle fully onto the monitor it mostly overlaps (or the primary
; monitor if it overlaps none). Fixes windows that were saved on a monitor that's gone.
ClampToScreen(&x, &y, w, h) {
    best := 0
    bestArea := -1
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        ow := Max(0, Min(x + w, r) - Max(x, l))
        oh := Max(0, Min(y + h, b) - Max(y, t))
        if (ow * oh > bestArea) {
            bestArea := ow * oh
            best := A_Index
        }
    }
    if (bestArea <= 0)
        best := MonitorGetPrimary()
    MonitorGetWorkArea(best, &l, &t, &r, &b)
    x := Max(l, Min(x, r - w))
    y := Max(t, Min(y, b - h))
}

; NM_CUSTOMDRAW handler for ListViews: the selected row is an amber bar with dark text,
; whether or not the list has focus. The dark Explorer theme paints its own selection
; and ignores custom colors, so the selected row is drawn by hand; other rows use the
; normal drawing. Hook it with: lv.OnNotify(-12, SnowListDraw)
SnowListDraw(ctrl, lParam) {
    stage := NumGet(lParam, 24, "UInt")
    if (stage = 0x1)                    ; CDDS_PREPAINT
        return 0x20                     ; CDRF_NOTIFYITEMDRAW
    if (stage != 0x10001)               ; not CDDS_ITEMPREPAINT
        return 0
    item := NumGet(lParam, 56, "UPtr")
    hwnd := ctrl.Hwnd
    if !(SendMessage(0x102C, item, 0x2, hwnd) & 0x2)    ; LVM_GETITEMSTATE, LVIS_SELECTED
        return 0

    hdc := NumGet(lParam, 32, "Ptr")
    row := Buffer(16, 0)
    SendMessage(0x100E, item, row, hwnd)                ; LVM_GETITEMRECT (LVIR_BOUNDS)
    brush := DllCall("CreateSolidBrush", "UInt", 0x20A0E8, "Ptr")    ; THEME_ACCENT (BGR)
    DllCall("FillRect", "Ptr", hdc, "Ptr", row, "Ptr", brush)
    DllCall("DeleteObject", "Ptr", brush)

    oldFont := DllCall("SelectObject", "Ptr", hdc, "Ptr", SendMessage(0x31, 0, 0, hwnd), "Ptr")   ; WM_GETFONT
    DllCall("SetBkMode", "Ptr", hdc, "Int", 1)
    DllCall("SetTextColor", "Ptr", hdc, "UInt", 0x17110D)            ; THEME_BG (BGR)
    Loop ctrl.GetCount("Col") {
        cell := Buffer(16, 0)
        NumPut("Int", 2, cell, 0)                       ; LVIR_LABEL
        NumPut("Int", A_Index - 1, cell, 4)             ; iSubItem
        SendMessage(0x1038, item, cell, hwnd)           ; LVM_GETSUBITEMRECT
        text := ctrl.GetText(item + 1, A_Index)
        DllCall("DrawText", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", cell, "UInt", 0x8824)   ; left, vcenter, single line, ellipsis, no prefix
    }
    DllCall("SelectObject", "Ptr", hdc, "Ptr", oldFont)
    return 0x4                                          ; CDRF_SKIPDEFAULT
}

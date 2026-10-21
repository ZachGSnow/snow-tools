; Synthetic sample image for the self-test and the documentation screenshots.
; It draws a small themed window and captures that window's own pixels, so nothing from
; the real screen ever ends up in a test image.
SampleImage(path, w := 320, h := 180, label := "SAMPLE") {
    g := Gui("+AlwaysOnTop -Caption +ToolWindow", "sample image")
    g.BackColor := THEME_BG
    g.MarginX := 0
    g.MarginY := 0
    bar := Max(6, (h - 40) // 6)
    for i, color in ART_LOGO_COLORS
        g.Add("Text", "x0 y" (i - 1) * bar " w" w " h" bar " Background" color)
    g.SetFont("s14 c" THEME_ACCENT, THEME_FONT)
    g.Add("Text", "x0 y" bar * 6 + 6 " w" w " h30 Center BackgroundTrans", label)
    g.Show("x0 y0 w" w " h" h " NoActivate")
    Sleep(300)
    GdipCaptureRect(0, 0, w, h, path)
    g.Destroy()
}

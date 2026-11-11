; ===== GDI+ HELPERS =====
; Clipboard bitmap <-> PNG file conversion, plus a screen-region capture used for
; development screenshots.

global GdipToken := 0

GdipStart() {
    global GdipToken
    if (GdipToken != 0)
        return true
    if !DllCall("GetModuleHandle", "Str", "gdiplus", "Ptr")
        DllCall("LoadLibrary", "Str", "gdiplus")
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, si)
    token := 0
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
    GdipToken := token
    OnExit((*) => GdipStop())
    return (token != 0)
}

GdipStop() {
    global GdipToken
    if (GdipToken != 0) {
        DllCall("gdiplus\GdiplusShutdown", "Ptr", GdipToken)
        GdipToken := 0
    }
}

GdipPngClsid() {
    static clsid := ""
    if (clsid = "") {
        clsid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "Str", "{557CF406-1A04-11D3-9A73-0000F81EF32E}", "Ptr", clsid)
    }
    return clsid
}

; Save a GDI+ bitmap to PNG and dispose it. Returns {w, h} or "".
GdipSaveAndDispose(pBmp, path) {
    w := 0
    h := 0
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBmp, "UInt*", &w)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBmp, "UInt*", &h)
    status := DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBmp, "WStr", path, "Ptr", GdipPngClsid(), "Ptr", 0)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
    return (status = 0) ? {w: w, h: h} : ""
}

; Write the clipboard's bitmap to a PNG file. Returns {w, h} or "" if there is no image.
GdipClipboardToPng(path) {
    GdipStart()
    if !DllCall("IsClipboardFormatAvailable", "UInt", 2)   ; CF_BITMAP
        return ""
    opened := false
    Loop 10 {
        if DllCall("OpenClipboard", "Ptr", 0) {
            opened := true
            break
        }
        Sleep(30)
    }
    if !opened
        return ""
    pBmp := 0
    hbm := DllCall("GetClipboardData", "UInt", 2, "Ptr")
    if (hbm)
        DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &pBmp)
    DllCall("CloseClipboard")
    if (!pBmp)
        return ""
    return GdipSaveAndDispose(pBmp, path)
}

; Put a PNG file on the clipboard as CF_DIB (24-bit) plus the registered "PNG" format
; (browsers and Office prefer it). Both are global memory the clipboard owns, so any
; process can read them; Windows synthesizes CF_BITMAP and CF_DIBV5 from the CF_DIB.
; Not a GDI+ HBITMAP: that is a DIB section whose pixels live in this process, so other
; apps got no pixels from it and pasted an empty image.
GdipPngToClipboard(path) {
    static fmtPng := DllCall("RegisterClipboardFormat", "Str", "PNG", "UInt")
    GdipStart()
    try {
        png := FileRead(path, "RAW")
    } catch {
        return false
    }
    pBmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &pBmp)
    if (!pBmp)
        return false
    w := 0
    h := 0
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBmp, "UInt*", &w)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBmp, "UInt*", &h)
    stride := (w * 3 + 3) & ~3
    hDib := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", 40 + stride * h, "Ptr")   ; GMEM_MOVEABLE | GMEM_ZEROINIT
    ok := false
    if (hDib) {
        p := DllCall("GlobalLock", "Ptr", hDib, "Ptr")
        ; BITMAPINFOHEADER: size, width, height (positive = bottom-up), planes, 24 bpp, BI_RGB, image size
        NumPut("UInt", 40, "Int", w, "Int", h, "UShort", 1, "UShort", 24, "UInt", 0, "UInt", stride * h, p)
        rect := Buffer(16, 0)
        NumPut("Int", w, rect, 8)
        NumPut("Int", h, rect, 12)
        ; GDI+ writes the rows straight into the DIB, last row first (negative stride).
        bd := Buffer(32, 0)
        NumPut("UInt", w, "UInt", h, "Int", -stride, "Int", 0x21808, bd)    ; PixelFormat24bppRGB
        NumPut("Ptr", p + 40 + stride * (h - 1), bd, 16)
        if (DllCall("gdiplus\GdipBitmapLockBits", "Ptr", pBmp, "Ptr", rect, "UInt", 5, "Int", 0x21808, "Ptr", bd) = 0) {   ; read | user buffer
            DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", pBmp, "Ptr", bd)
            ok := true
        }
        DllCall("GlobalUnlock", "Ptr", hDib)
    }
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
    if !ok {
        if hDib
            DllCall("GlobalFree", "Ptr", hDib)
        return false
    }
    hPng := DllCall("GlobalAlloc", "UInt", 0x2, "UPtr", png.Size, "Ptr")    ; GMEM_MOVEABLE
    if (hPng) {
        DllCall("RtlMoveMemory", "Ptr", DllCall("GlobalLock", "Ptr", hPng, "Ptr"), "Ptr", png, "UPtr", png.Size)
        DllCall("GlobalUnlock", "Ptr", hPng)
    }
    opened := false
    Loop 10 {
        if DllCall("OpenClipboard", "Ptr", A_ScriptHwnd) {
            opened := true
            break
        }
        Sleep(30)
    }
    if !opened {
        DllCall("GlobalFree", "Ptr", hDib)
        if hPng
            DllCall("GlobalFree", "Ptr", hPng)
        return false
    }
    DllCall("EmptyClipboard")
    ok := DllCall("SetClipboardData", "UInt", 8, "Ptr", hDib, "Ptr") != 0    ; CF_DIB; on success the clipboard owns it
    if !ok
        DllCall("GlobalFree", "Ptr", hDib)
    if (hPng && !DllCall("SetClipboardData", "UInt", fmtPng, "Ptr", hPng, "Ptr"))
        DllCall("GlobalFree", "Ptr", hPng)
    DllCall("CloseClipboard")
    return ok
}

; Copy a screen rectangle to a PNG file (development screenshots).
GdipCaptureRect(x, y, w, h, path) {
    GdipStart()
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdc := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", w, "Int", h, "Ptr")
    old := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm, "Ptr")
    DllCall("BitBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h
        , "Ptr", hdcScreen, "Int", x, "Int", y, "UInt", 0x00CC0020)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", old)
    pBmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &pBmp)
    DllCall("DeleteObject", "Ptr", hbm)
    DllCall("DeleteDC", "Ptr", hdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
    if (!pBmp)
        return ""
    return GdipSaveAndDispose(pBmp, path)
}

; CRC32 of a file's bytes, used to detect duplicate images.
FileCrc32(path) {
    f := FileOpen(path, "r")
    if !f
        return 0
    buf := Buffer(f.Length)
    f.RawRead(buf)
    f.Close()
    return DllCall("ntdll\RtlComputeCrc32", "UInt", 0, "Ptr", buf, "UInt", buf.Size, "UInt")
}

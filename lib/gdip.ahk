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

; Put a PNG file on the clipboard as a bitmap (apps get a DIB synthesized from it).
GdipPngToClipboard(path) {
    GdipStart()
    pBmp := 0
    DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &pBmp)
    if (!pBmp)
        return false
    hbm := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBmp, "Ptr*", &hbm, "UInt", 0xFFFFFFFF)
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)
    if (!hbm)
        return false
    opened := false
    Loop 10 {
        if DllCall("OpenClipboard", "Ptr", 0) {
            opened := true
            break
        }
        Sleep(30)
    }
    if !opened {
        DllCall("DeleteObject", "Ptr", hbm)
        return false
    }
    DllCall("EmptyClipboard")
    DllCall("SetClipboardData", "UInt", 2, "Ptr", hbm)   ; the clipboard now owns hbm
    DllCall("CloseClipboard")
    return true
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

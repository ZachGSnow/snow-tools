; ===== CLIP STORE =====
; Data layer for the clipboard manager (no GUI, no hooks).
;
; Text clips live in data\clips.log, an append-only journal. Each record is
;     @<length>|<timestamp>|<pinned 0/1>`n<text>`n
; Length-prefixed, so clips may contain anything. A later record for the same text
; supersedes an earlier one. Deleting/pinning rewrites the file; it is also rewritten
; when the journal has accumulated a lot of superseded records.
;
; Images are PNG files in data\img\ with a small index (data\images.idx):
;     <timestamp>|<file>|<w>|<h>|<bytes>|<crc32>|<pinned 0/1>
;
; Both stores are capped (oldest unpinned entries are dropped first); pinned entries
; don't count toward the caps. Timestamps are A_Now strings (yyyyMMddHHmmss).

global CLIP_MAX_TEXT := 10000
global CLIP_MAX_IMG := 200
global CLIP_MAX_CHARS := 500000

global ClipDataDir := SnowDataDir
global ClipTextPath := ClipDataDir "\clips.log"
global ClipImgDir := ClipDataDir "\img"
global ClipImgIdxPath := ClipDataDir "\images.idx"

global ClipTexts := []          ; oldest -> newest; {ts, pin, text}
global ClipTextMap := Map()     ; text -> entry
global ClipImages := []         ; oldest -> newest; {ts, file, w, h, size, crc, pin}
global ClipTextPins := 0
global ClipImgPins := 0
global ClipJournalExtra := 0    ; superseded/evicted records still in the journal file

ClipStoreInit() {
    DirCreate(ClipDataDir)
    DirCreate(ClipImgDir)
    ClipLoadTexts()
    ClipLoadImages()
}

ClipIndexOf(arr, entry) {
    i := arr.Length
    while (i >= 1) {
        if (arr[i] == entry)
            return i
        i--
    }
    return 0
}

; ---------------------------------------------------------------------------
; Text
; ---------------------------------------------------------------------------
ClipRecord(e) {
    return "@" StrLen(e.text) "|" e.ts "|" e.pin "`n" e.text "`n"
}

ClipLoadTexts() {
    global ClipTexts, ClipTextMap, ClipTextPins, ClipJournalExtra, CLIP_MAX_TEXT, ClipTextPath
    ClipTexts := []
    ClipTextMap := Map()
    ClipTextPins := 0
    ClipJournalExtra := 0
    if !FileExist(ClipTextPath)
        return
    raw := FileRead(ClipTextPath, "UTF-8-RAW")
    pos := 1
    n := StrLen(raw)
    total := 0
    list := []
    seen := Map()
    while (pos <= n) {
        nl := InStr(raw, "`n", , pos)
        if !nl
            break
        if !RegExMatch(SubStr(raw, pos, nl - pos), "^@(\d+)\|(\d*)\|([01])$", &m)
            break    ; corrupt tail - keep what was read
        len := Integer(m[1])
        text := SubStr(raw, nl + 1, len)
        pos := nl + len + 2
        total++
        e := {ts: m[2], pin: Integer(m[3]), text: text, dead: false}
        if seen.Has(text)
            seen[text].dead := true
        seen[text] := e
        list.Push(e)
    }
    for e in list {
        if e.dead
            continue
        ClipTexts.Push(e)
        ClipTextMap[e.text] := e
        if e.pin
            ClipTextPins++
    }
    ClipJournalExtra := total - ClipTexts.Length
    before := ClipTexts.Length
    ClipEvictTexts()
    if (ClipTexts.Length != before || ClipJournalExtra > 500)
        ClipRewriteTexts()
}

ClipRewriteTexts() {
    global ClipTexts, ClipJournalExtra, ClipTextPath
    s := ""
    for e in ClipTexts
        s .= ClipRecord(e)
    tmp := ClipTextPath ".tmp"
    f := FileOpen(tmp, "w", "UTF-8-RAW")
    f.Write(s)
    f.Close()
    FileMove(tmp, ClipTextPath, 1)
    ClipJournalExtra := 0
}

ClipEvictTexts() {
    global ClipTexts, ClipTextMap, ClipTextPins, ClipJournalExtra, CLIP_MAX_TEXT
    while (ClipTexts.Length - ClipTextPins > CLIP_MAX_TEXT) {
        idx := 0
        for i, e in ClipTexts {
            if !e.pin {
                idx := i
                break
            }
        }
        if !idx
            break
        e := ClipTexts.RemoveAt(idx)
        ClipTextMap.Delete(e.text)
        ClipJournalExtra++
    }
}

; Add (or bump to newest) a text clip. Returns the entry, or "" if it was ignored.
ClipAddText(text, ts := "") {
    global ClipTexts, ClipTextMap, ClipJournalExtra, ClipTextPath, CLIP_MAX_CHARS
    if (text = "" || StrLen(text) > CLIP_MAX_CHARS)
        return ""
    if (ts = "")
        ts := A_Now
    if ClipTextMap.Has(text) {
        e := ClipTextMap[text]
        idx := ClipIndexOf(ClipTexts, e)
        if idx
            ClipTexts.RemoveAt(idx)
        e.ts := ts
        ClipTexts.Push(e)
        ClipJournalExtra++
    } else {
        e := {ts: ts, pin: 0, text: text}
        ClipTexts.Push(e)
        ClipTextMap[text] := e
    }
    try {
        FileAppend(ClipRecord(e), ClipTextPath, "UTF-8-RAW")
    } catch as err {
        SnowLog("clip journal append failed: " err.Message)
    }
    ClipEvictTexts()
    if (ClipJournalExtra > 1000) {
        try {
            ClipRewriteTexts()
        } catch as err {
            SnowLog("clip journal rewrite failed: " err.Message)
        }
    }
    return e
}

; ---------------------------------------------------------------------------
; Images
; ---------------------------------------------------------------------------
ClipImagePath(e) {
    global ClipImgDir
    return ClipImgDir "\" e.file
}

ClipLoadImages() {
    global ClipImages, ClipImgPins, ClipImgIdxPath
    ClipImages := []
    ClipImgPins := 0
    if !FileExist(ClipImgIdxPath)
        return
    for line in StrSplit(FileRead(ClipImgIdxPath, "UTF-8"), "`n", "`r") {
        p := StrSplit(line, "|")
        if (p.Length < 7)
            continue
        e := {ts: p[1], file: p[2], w: Integer(p[3]), h: Integer(p[4]), size: Integer(p[5]), crc: p[6], pin: Integer(p[7])}
        if !FileExist(ClipImagePath(e))
            continue
        ClipImages.Push(e)
        if e.pin
            ClipImgPins++
    }
}

ClipSaveImages() {
    global ClipImages, ClipImgIdxPath
    s := ""
    for e in ClipImages
        s .= e.ts "|" e.file "|" e.w "|" e.h "|" e.size "|" e.crc "|" e.pin "`n"
    tmp := ClipImgIdxPath ".tmp"
    f := FileOpen(tmp, "w", "UTF-8-RAW")
    f.Write(s)
    f.Close()
    FileMove(tmp, ClipImgIdxPath, 1)
}

ClipEvictImages() {
    global ClipImages, ClipImgPins, CLIP_MAX_IMG
    while (ClipImages.Length - ClipImgPins > CLIP_MAX_IMG) {
        idx := 0
        for i, e in ClipImages {
            if !e.pin {
                idx := i
                break
            }
        }
        if !idx
            break
        e := ClipImages.RemoveAt(idx)
        try FileDelete(ClipImagePath(e))
    }
}

; Store the image currently on the clipboard as PNG. Returns the entry, or "" if the
; clipboard has no usable image. A duplicate of an existing image just bumps it.
ClipAddImageFromClipboard(ts := "") {
    global ClipImages, ClipImgDir
    if (ts = "")
        ts := A_Now
    DirCreate(ClipImgDir)
    tmp := ClipImgDir "\_incoming.png"
    info := GdipClipboardToPng(tmp)
    if !info
        return ""
    size := FileGetSize(tmp)
    crc := Format("{:08X}", FileCrc32(tmp))
    i := ClipImages.Length
    while (i >= 1) {
        e := ClipImages[i]
        if (e.crc = crc && e.size = size) {
            try FileDelete(tmp)
            ClipTouchImage(e, ts)
            return e
        }
        i--
    }
    name := ts "_" crc ".png"
    FileMove(tmp, ClipImgDir "\" name, 1)
    e := {ts: ts, file: name, w: info.w, h: info.h, size: size, crc: crc, pin: 0}
    ClipImages.Push(e)
    ClipEvictImages()
    ClipSaveImages()
    return e
}

ClipTouchImage(e, ts := "") {
    global ClipImages
    idx := ClipIndexOf(ClipImages, e)
    if idx
        ClipImages.RemoveAt(idx)
    e.ts := (ts = "") ? A_Now : ts
    ClipImages.Push(e)
    ClipSaveImages()
}

; ---------------------------------------------------------------------------
; Pin / delete (item = {kind: "txt"|"img", e: entry})
; ---------------------------------------------------------------------------
ClipTogglePin(item) {
    global ClipTextPins, ClipImgPins
    e := item.e
    e.pin := e.pin ? 0 : 1
    delta := e.pin ? 1 : -1
    if (item.kind = "txt") {
        ClipTextPins += delta
        ClipRewriteTexts()
        ClipEvictTexts()
    } else {
        ClipImgPins += delta
        ClipEvictImages()
        ClipSaveImages()
    }
}

ClipDeleteItem(item) {
    global ClipTexts, ClipTextMap, ClipTextPins, ClipImages, ClipImgPins
    e := item.e
    if (item.kind = "txt") {
        idx := ClipIndexOf(ClipTexts, e)
        if idx
            ClipTexts.RemoveAt(idx)
        ClipTextMap.Delete(e.text)
        if e.pin
            ClipTextPins--
        ClipRewriteTexts()
    } else {
        idx := ClipIndexOf(ClipImages, e)
        if idx
            ClipImages.RemoveAt(idx)
        if e.pin
            ClipImgPins--
        try FileDelete(ClipImagePath(e))
        ClipSaveImages()
    }
}

; All clips as one newest-first list of {kind, e}, pinned first.
ClipMergedItems() {
    global ClipTexts, ClipImages
    pinned := []
    rest := []
    ti := ClipTexts.Length
    ii := ClipImages.Length
    while (ti >= 1 || ii >= 1) {
        takeText := (ii < 1) || (ti >= 1 && ClipTexts[ti].ts >= ClipImages[ii].ts)
        if takeText {
            item := {kind: "txt", e: ClipTexts[ti]}
            ti--
        } else {
            item := {kind: "img", e: ClipImages[ii]}
            ii--
        }
        if item.e.pin
            pinned.Push(item)
        else
            rest.Push(item)
    }
    for item in rest
        pinned.Push(item)
    return pinned
}

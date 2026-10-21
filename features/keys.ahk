; ===== KEYS =====
; Text expansions (zem, :ty, cdate, callnote, ...) live in data\snippets.txt and are managed
; in the Snippets editor (Alt+S). Only key fixes are here.

; Multi-line Edit controls in AHK GUIs need an explicit Ctrl+A.
#HotIf WinActive("ahk_class AutoHotkeyGUI")
^a::Send("^a")
#HotIf

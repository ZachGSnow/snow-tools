; ===== SNOW ART =====
; Keep this file free of backticks and double quotes so the strings stay literal.
; The logo is stored with ASCII stand-ins and expanded to block and box glyphs at load, so
; the source stays plain ASCII. # is a block, = and | are the double lines, and / BACKSLASH < >
; are the four double-line corners (top-left, top-right, bottom-left, bottom-right).

global ART_LOGO_SRC := [
    "#######\###\   ##\ ######\ ##\    ##\",
    "##/====>####\  ##|##/===##\##|    ##|",
    "#######\##/##\ ##|##|   ##|##| #\ ##|",
    "<====##|##|<##\##|##|   ##|##|###\##|",
    "#######|##| <####|<######/><###/###/>",
    "<======><=>  <===> <=====>  <==><==> "
]

ArtExpand(s) {
    s := StrReplace(s, "#", Chr(0x2588))
    s := StrReplace(s, "=", GL_H)
    s := StrReplace(s, "|", GL_V)
    s := StrReplace(s, "/", GL_TL)
    s := StrReplace(s, "\", GL_TR)
    s := StrReplace(s, "<", GL_BL)
    s := StrReplace(s, ">", GL_BR)
    return s
}

global ART_LOGO := []
for line in ART_LOGO_SRC
    ART_LOGO.Push(ArtExpand(line))

; Top-to-bottom gradient for the logo, bright to dim.
global ART_LOGO_COLORS := ["8dfff0", "4aeed4", "00c4a7", "17a38f", "2a7a72", "1f5f59"]

global ART_SUBTITLE := Chr(0x2591) Chr(0x2592) Chr(0x2593) Chr(0x2588) "  T " GL_DOT " O " GL_DOT " O " GL_DOT " L " GL_DOT " S   v3  " Chr(0x2588) Chr(0x2593) Chr(0x2592) Chr(0x2591)
global ART_CREDIT   := GL_DOT GL_DOT " coded by zach snow " GL_DOT GL_DOT

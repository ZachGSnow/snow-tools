;   ___                    _____           _
;  / __|_ _  _____ __ __ |_   _|___  ___ | | ___
;  \__ \ ' \/ _ \ V  V /   | | / _ \/ _ \| |(_-<
;  |___/_||_\___/\_/\_/    |_| \___/\___/|_/__/
;
;  Snow Tools
;  by Zach Snow
;
;  Entry point. Everything lives in lib\ (shared code) and features\ (one file per tool);
;  press Alt+Y for the live list of hotkeys and hotstrings, or right-click the tray icon.

#Requires AutoHotkey v2.0
#SingleInstance Force

; The release version, shown in the banner and the tray tip. Keep it equal to the git tag.
global SNOW_VERSION := "1.0.0"

; --- shared libraries (order matters: log, theme and registry before anything that uses them)
#Include lib\log.ahk
#Include lib\settings.ahk
#Include lib\theme.ahk
#Include lib\art.ahk
#Include lib\registry.ahk
#Include lib\gdip.ahk
#Include lib\timeutil.ahk
#Include lib\calcmath.ahk
#Include lib\clipstore.ahk
#Include lib\tray.ahk

; --- tray identity
A_IconTip := "*  Snow Tools " SNOW_VERSION "  *  " GL_DOT "  by Zach Snow"
TrayTip("Snow Tools loaded", "*  Snow Tools  *", 1)
SetTimer((*) => TrayTip(), -3000)

; --- features (registry order = HUD order; the HUD goes last)
#Include features\keys.ahk
#Include features\calc.ahk
#Include features\notes.ahk
#Include features\clipboard.ahk
#Include features\snippets.ahk
#Include features\settings.ahk
#Include features\hotkeys.ahk
#Include features\transfer.ahk
#Include features\hud.ahk

SnowTrayInit()

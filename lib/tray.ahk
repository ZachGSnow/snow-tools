; ===== TRAY MENU =====
; Right-click the tray icon. Call SnowTrayInit() once, after every feature is loaded.

global SnowStartupLink := A_Startup "\Snow Tools.lnk"

SnowTrayInit() {
    A_TrayMenu.Delete()
    hudItem := "Show HUD (" HotkeyText("hud") ")"
    A_TrayMenu.Add(hudItem, (*) => HudToggle())
    A_TrayMenu.Add("Snippets... (" HotkeyText("snippets") ")", (*) => SnippetsToggle())
    A_TrayMenu.Add("Settings... (" HotkeyText("settings") ")", (*) => SettingsToggle())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Open data folder", (*) => SnowOpenDataFolder())
    A_TrayMenu.Add("Open error log", (*) => SnowOpenLog())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Run at startup", SnowToggleStartup)
    A_TrayMenu.Add("Reload", (*) => Reload())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := hudItem
    SnowStartupRefresh()
}

SnowOpenDataFolder(*) {
    DirCreate(SnowDataDir)
    Run('explorer "' SnowDataDir '"')
}

SnowOpenLog(*) {
    if !FileExist(SnowLogPath)
        SnowLog("log opened (no errors recorded yet)")
    Run('notepad "' SnowLogPath '"')
}

; Adds or removes the Startup-folder shortcut that launches this script at login.
SnowToggleStartup(*) {
    global SnowStartupLink
    try {
        if FileExist(SnowStartupLink)
            FileDelete(SnowStartupLink)
        else
            FileCreateShortcut(A_AhkPath, SnowStartupLink, A_ScriptDir, '"' A_ScriptFullPath '"'
                , "Snow Tools (AutoHotkey v2)", A_ScriptDir "\snowflake-32x32.ico")
    } catch as err {
        SnowLog("startup shortcut toggle failed: " err.Message)
        TrayTip(err.Message, "Snow Tools", "Iconx")
    }
    SnowStartupRefresh()
}

SnowStartupRefresh() {
    global SnowStartupLink
    if FileExist(SnowStartupLink)
        A_TrayMenu.Check("Run at startup")
    else
        A_TrayMenu.Uncheck("Run at startup")
}

# Architecture

Snow Tools is a set of independent tools sharing a small library. Nothing is compiled: AutoHotkey runs `hotstrings.ahk`, which `#Include`s everything.

## Layout

```
hotstrings.ahk      entry point: includes, tray identity, nothing else
lib/                shared code, included in dependency order
  log.ahk           SnowLog, global error handler, SnowDataDir
  settings.ahk      preferences in data\prefs.ini (named, defaulted, cached)
  theme.ahk         colors, glyph constants, SnowWin (the character-grid window)
  art.ahk           banner art (ASCII source, expanded to glyphs at load)
  registry.ahk      RegHotkey / RegDoc: the list the HUD reads
  gdip.ahk          clipboard bitmap <-> PNG, screen capture
  clipstore.ahk     clipboard data layer (no GUI, no hooks)
  timeutil.ahk      time-difference helpers
  calcmath.ahk      arithmetic parser
  tray.ahk          tray menu
features/           one file per tool; each registers its own hotkeys
tests/              self-test, runner, sample-image helper
tools/              showcase.ahk: documentation screenshots
```

## Registry

A tool calls `RegHotkey(id, defaultKey, description, fn)`, which both binds the hotkey and records it. Things defined by other means (a context-sensitive hotkey, an automatic behavior) call `RegDoc(kind, key, description)`. The HUD never keeps its own list: it renders the registry. Snippets are re-registered into it whenever they change, and the HUD is dropped and rebuilt the next time it opens.

Global hotkeys are rebindable. `id` is a short stable name (`pad`, `clips`) and is what is saved: a changed key lives in `data\prefs.ini` under `[hotkeys]`, and a hotkey on its default key has no entry. At start `RegHotkey` uses the saved key if it still passes `HotkeyCheck` and no other hotkey has it, and otherwise the default (the reason goes to the log). `HotkeyRebind` validates, checks for a clash, binds the new key before releasing the old one, updates the HUD entry, saves, and rebuilds the tray menu and HUD so every printed shortcut is current. `HotkeyRebindMany` releases all the old keys before binding any new one, which is what makes a swap work. Labels elsewhere (HUD footer, tray menu, Settings) read the live key through `HotkeyText(id)`, never a hardcoded string.

`HotkeyCheck` is the single rule set: a supported key (letters, digits, F1-F24, named keys), at least one of Ctrl, Alt or Win unless it is an F-key, each modifier once, and not in `SnowHotkeyReserved`. `HotkeyNormalize` gives one spelling per shortcut (modifier order, case, `Escape` as `esc`) so clashes are found by meaning. Key capture (`features/hotkeys.ahk`) is an `InputHook` that swallows every key, tracks the modifiers itself from key-down and key-up events, and reports the first non-modifier key as a shortcut; Esc on its own cancels. The script's hotkeys are suspended during capture and always resumed through the hook's end callback.

## The character grid

Every window is a `SnowWin`. The theme font (Consolas) is measured once to get a cell width and height, and every label, frame piece and control is then placed at `(column, row)` cell coordinates. The frame is made of Text controls (corners, rules, side fills), so box characters always line up regardless of DPI or font hinting. Real controls (Edit, ListView, Picture) sit on the same grid via `Add(type, col, row, cols, rows)`. Resizable windows re-lay the frame in `Reflow`. Dragging works by posting a caption-drag message from clicks on the top border.

Glyphs are not in the source. `lib/theme.ahk` builds them with `Chr()`, and `lib/art.ahk` stores the logo with ASCII stand-ins (`#` for a block, `=` and `|` for the double lines, and `/ \ < >` for corners) that `ArtExpand` converts at load. The repository stays plain ASCII while the UI keeps its look.

## Clipboard store

`lib/clipstore.ahk` is deliberately separate from the window. Text clips are an append-only journal, `data\clips.log`, with length-prefixed records (`@<length>|<timestamp>|<pinned>` then the text), so a clip may contain anything, including text that looks like a record header. A later record for the same text supersedes an earlier one; delete and pin rewrite the file, as does a journal with many superseded records. Images are PNGs in `data\img\` with a small index including a CRC32, which is how a repeated image is bumped instead of stored twice. Both stores are capped, oldest unpinned first; pinned entries do not count toward the cap.

Capture is `OnClipboardChange` in `features/clipboard.ahk`. Before anything is read, `ClipIsSensitive` checks the registered clipboard formats `ExcludeClipboardContentFromMonitorProcessing` and `CanIncludeInClipboardHistory`, and the pause flag is checked. Changes the app makes itself (paste, setting converted hours) set `ClipIgnoreUntil` so they are not recorded again.

## Settings and deleting data

`lib/settings.ahk` keeps preferences in `data\prefs.ini`. Each one is named `section.key` and must have an entry in `SnowPrefDefaults`; reading or writing an unknown name throws, so a typo cannot silently read nothing. Values are cached and `SnowPrefSet` updates cache and file together. Code that keeps a preference in a live variable (the START/END conversion) re-reads it through an `Apply` function, which is also how Reset applies defaults without a reload. The password guard is read on every clipboard change through the cache, so flipping it in the Settings window takes effect immediately.

`features/settings.ahk` is the window. Checkbox rows are clickable text (`[x]` / `[ ]`) with a getter and a setter, and `SettingsRefresh` redraws them all from the getters, so the window cannot disagree with the real state. The delete actions live next to the data they remove: `ClipClearAll` in the clip store, `NotesClearAll` in the notes feature, and `SnippetsResetToDefaults` in snippets. The window only orchestrates them and asks for confirmation. Clearing history uses a Yes/No box that defaults to No; deleting everything opens a dialog that proceeds only when the text is exactly `DELETE`. Both are plain file deletes, not secure erases. The self-test answers the real dialogs by clicking their buttons, so it covers both the decline and the accept paths.

## Export and import

`features/transfer.ahk` moves preferences, hotkeys and snippets as one text file: a `format = N` header, a `[prefs]` section (`section.key = 0|1`), a `[hotkeys]` section (`id = key`) and a `[snippets]` section in the same encoding as `snippets.txt` (the line parser, `SnipParseLine`, is shared with the loader). The work is split into small steps so each can be tested alone:

1. **`TransferParse(text)`** is pure. It reads the text and returns what it understood plus a list of what it skipped, and never touches the live state. Unknown preferences, values other than 0 or 1, invalid or duplicate triggers, oversized snippets, unknown sections, files over 1 MB and a `format` newer than this version are all handled there, so a hostile or hand-edited file cannot do more than be rejected or partly ignored.
2. **`TransferPlan(parsed)`** compares the parse with the current state: which preferences would change, which hotkeys would move, how many snippets are new, changed or identical, how many of yours a replace would drop. A preference whose new value lowers privacy (`SnowPrefRisky` in `lib/settings.ahk`) is flagged. A hotkey move that would leave two hotkeys on one shortcut is marked skipped (both moves of a clashing pair are skipped, and a move onto an unchanged hotkey's key is skipped); a pure swap is not a clash.
3. **The dialog** shows the plan and does nothing until a button is pressed.
4. **`TransferApply(plan, mode, allowRisky)`** writes a backup of the current state to `data\backup\` first (newest 10 kept), then applies preferences, moves the hotkeys in one bulk call and applies snippets, re-registering the hotstrings, so everything takes effect without a reload. Flagged preferences are held back unless `allowRisky` is true, which only the dialog's separate opt-in sets; replace is refused when the file has no snippets.

New preferences need an entry in `SnowPrefDefaults` and a label in `SnowPrefLabels`; export and import pick them up from there.

## Snippets

`data\snippets.txt` is parsed into `Snippets`, and each entry becomes a hotstring (`Hotstring()` at runtime). Plain text uses the native replacement; text with a newline or a token goes through `SnipExpand`, which fills the tokens, sends the text with `SendText`, and moves the caret back to `{cursor}`. Re-applying turns off hotstrings that are gone or changed, so edits take effect without a reload. Conflict checks (shadowing, duplicates, reserved triggers in `SnipReserved`) run as you type in the editor.

## Errors and logging

`OnError` routes uncaught errors to `data\snowtools.log` and a tray tip instead of a modal dialog, so a failure never blocks you mid-call. The log is trimmed when it passes about 1 MB.

## Tests

`tests/run-tests.ps1` runs `AutoHotkey64.exe /Validate hotstrings.ahk`, copies the project to a temp folder, and runs `tests/selftest.ahk` there, so real data is never touched. The self-test drives the real functions and windows, types into a scratch window to exercise hotstrings, and writes `results.txt`; the runner fails on any `FAIL` line, a crash or a timeout. In the self-test a crash must be fatal, so it replaces the app's error handler. Test images come from `tests/sample.ahk`, which draws and captures its own window rather than the screen.

## Adding a tool

1. Create `features/<name>.ahk` and `#Include` it in `hotstrings.ahk` before `features\hud.ahk`.
2. Build a window with `SnowWin(title, cols, rows)` and place controls by cell.
3. Register with `RegHotkey(key, description, fn)`. It appears in the HUD automatically.
4. Add a group to `tests/selftest.ahk`.

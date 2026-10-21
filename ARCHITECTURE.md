# Architecture

Snow Tools is a set of independent tools sharing a small library. Nothing is compiled: AutoHotkey runs `hotstrings.ahk`, which `#Include`s everything.

## Layout

```
hotstrings.ahk      entry point: includes, tray identity, nothing else
lib/                shared code, included in dependency order
  log.ahk           SnowLog, global error handler, SnowDataDir
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

A tool calls `RegHotkey(key, description, fn)`, which both binds the hotkey and records it. Things defined by other means (a context-sensitive hotkey, an automatic behavior) call `RegDoc(kind, key, description)`. The HUD never keeps its own list: it renders the registry. Snippets are re-registered into it whenever they change, and the HUD is dropped and rebuilt the next time it opens.

## The character grid

Every window is a `SnowWin`. The theme font (Consolas) is measured once to get a cell width and height, and every label, frame piece and control is then placed at `(column, row)` cell coordinates. The frame is made of Text controls (corners, rules, side fills), so box characters always line up regardless of DPI or font hinting. Real controls (Edit, ListView, Picture) sit on the same grid via `Add(type, col, row, cols, rows)`. Resizable windows re-lay the frame in `Reflow`. Dragging works by posting a caption-drag message from clicks on the top border.

Glyphs are not in the source. `lib/theme.ahk` builds them with `Chr()`, and `lib/art.ahk` stores the logo with ASCII stand-ins (`#` for a block, `=` and `|` for the double lines, and `/ \ < >` for corners) that `ArtExpand` converts at load. The repository stays plain ASCII while the UI keeps its look.

## Clipboard store

`lib/clipstore.ahk` is deliberately separate from the window. Text clips are an append-only journal, `data\clips.log`, with length-prefixed records (`@<length>|<timestamp>|<pinned>` then the text), so a clip may contain anything, including text that looks like a record header. A later record for the same text supersedes an earlier one; delete and pin rewrite the file, as does a journal with many superseded records. Images are PNGs in `data\img\` with a small index including a CRC32, which is how a repeated image is bumped instead of stored twice. Both stores are capped, oldest unpinned first; pinned entries do not count toward the cap.

Capture is `OnClipboardChange` in `features/clipboard.ahk`. Before anything is read, `ClipIsSensitive` checks the registered clipboard formats `ExcludeClipboardContentFromMonitorProcessing` and `CanIncludeInClipboardHistory`, and the pause flag is checked. Changes the app makes itself (paste, setting converted hours) set `ClipIgnoreUntil` so they are not recorded again.

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

# Explorer

A file browser for macOS, built to be used instead of Finder.

## Technology

- Native app in Swift + AppKit, Swift Package Manager, no Xcode project.
- `./build.sh` builds `build/Explorer.app`, signed with your Apple Development certificate when there is one (a stable signature means macOS doesn't ask again for Desktop/Documents access after every build).
- `./install.sh` copies it to `~/Applications` and opens it.
- It does not replace Finder as the default app.

## Window

- No tabs. Several windows: `cmd+n` opens another one on the same folder.
- On launch: one window on the start folder (home by default; configurable in Settings). Windows are not restored.
- Finder look: translucent sidebar on the left with Favorites (hidden with its button); the toolbar has back, forward, up, the full editable path and the filter.
- Next to the sidebar, the list.

## List

- Always a list. Columns: Name, Date Modified, Size, Kind.
- Clicking a header sorts; folders always come first.
- The disclosure triangle expands a folder in place; double-click goes into it. Double-clicking a file opens it.
- Recursive folder size in the Size column: computed in the background ("…" meanwhile), cancelled when you leave the folder, cached. When something changes inside, the old value stays until the row is drawn again (at most one recompute every 30 s per folder).
- The list updates itself when files change (FSEvents).
- Cut items are dimmed.
- A status bar under the list: with nothing selected, the folders and files of the folder (and how many before the filter); with a selection, how many of the rows and their total size (once every folder size is known). Always the free space of the volume.

## Path

- Shows the full path and can be edited. Enter goes to the folder; for a file, goes to its folder and selects it. `~` works.
- Tab completes like a shell.
- `cmd+l` or `cmd+shift+g` focus the path. Esc goes back to the list.

## Filter

- Filters the current folder by name as you type (`cmd+f`). Down arrow moves to the list.

## Favorites (left sidebar)

- Folders only.
- Dropping a folder between two favorites adds it there. Dragging inside the sidebar reorders.
- Dropping files on a favorite moves them into that folder (copies with option).
- Right-click: Open, Open in New Window, Open in den, Copy Path, Open Terminal Here, Paste Inside, Remove from Favorites.
- Defaults: home, Desktop, Documents, Downloads.

## Servers (left sidebar)

- Other machines, each with a name, a disk URL (`smb://host/share`) and a screen URL (`vnc://host[:port]`); either can be empty.
- Click: mounts the disk if needed and opens it in the list (spins while it mounts); with no disk, opens the screen.
- The display button on the row opens the screen in Screen Sharing.
- Right-click: Open Disk, Open Screen, Edit Server…, Remove Server, Add Server…. Add Server… also on the section headers and empty space.
- The section shows only when there is a server.

## Right-click

On an item:

- Open / Open in New Window (folders).
- Open in den.
- Preview (when the type doesn't open in the previewer already).
- Open With ▸ (Preview plus every app that can open it) and Always Open .ext With ▸ (remembered by Explorer, Finder is untouched).
- Quick Look.
- Copy Path (always). Show in Finder.
- Cut, Copy, Paste.
- Rename, Move to Trash.
- New Folder / New File: inside the item if it's a folder; next to it if it's a file.
- Open Terminal Here. Add to Favorites (folders).
- Show/Hide Hidden Files.

On empty space (the folder you are looking at): New Folder, New File, Paste, Copy Path, Open Terminal Here, Open in den, Add to Favorites, Show/Hide Hidden Files.

## Drag, cut, copy and paste

- Drag between windows and from/to other apps (Finder, Desktop, Mail).
- When dragging: same disk = move; another disk = copy; with option = copy.
- `cmd+c` / `cmd+x` / `cmd+v` like Windows/Linux: cut + paste moves. Paste goes into the current folder (or the right-clicked folder).
- Copying files in Finder and pasting here works, and the other way round.
- Name clashes: "name 2". Copying into the same folder: "name copy".

## Preview

- One previewer window, reused. ← and → go to the previous/next file of the folder, in list order (with the filter applied). Esc closes it.
- Images: rotate (⌘L / ⌘R, saved at once; for JPEG only the EXIF orientation changes, nothing is recompressed), copy image (⌘C), copy path (⌥⌘C), zoom with pinch and double-click (fit ↔ 100%).
- Video macOS can play (mp4, mov, m4v…): built-in player, streamed from disk (multi-GB movies are fine). Space pauses.
- Everything else: the system preview (PDF, text, audio, Office…) inside the same window.
- By default images and the videos macOS can play open in the previewer. Other videos (mkv, avi…) open in VLC when it is installed.
- Per type: "Always Open .ext With ▸" has Preview as its first option. If a type doesn't open in the previewer, right-click has "Preview". "Open With ▸" includes it too.
- Opening a file with Explorer from another app previews it when its type opens in the previewer.

## Terminal

- Open Terminal Here launches a new Ghostty instance in that folder (`--working-directory`). Another terminal can be chosen in Settings.

## den

- "Open in den" in every right-click menu (items, empty space, Favorites): runs `den <path>`.

## Shortcuts

| Shortcut | Action |
|---|---|
| `cmd+n` | New window (same folder) |
| `cmd+shift+n` | New folder |
| `cmd+option+n` | New file |
| `cmd+[` / `cmd+]` | Back / Forward |
| `cmd+↑` | Enclosing folder |
| `cmd+↓` | Open |
| Enter | Rename |
| Space | Preview (in the previewer: closes; on video: pauses) |
| `cmd+y` | macOS Quick Look |
| `cmd+backspace` | Move to Trash |
| `cmd+option+c` | Copy path |
| `cmd+option+t` | Open terminal here |
| `cmd+shift+.` | Show/hide hidden files |
| `cmd+f` | Filter |
| `cmd+l`, `cmd+shift+g` | Edit path |
| `cmd+,` | Settings |
| `cmd+z` / `cmd+shift+z` | Undo / Redo (move, copy, rename, trash, create) |
| Esc | Cancels a pending cut |
| `⌘E` (global, changeable in Settings) | Opens a window from any app |

## Launch

- Explorer starts at login (without opening a window) so the global shortcut always works. It can be turned off in Settings.

## Settings

- Start folder.
- Global shortcut for a new window (`⌘E` by default; click it and press the new one, Delete turns it off, Esc cancels). It takes the key from every app, so `⌘E` stops doing "Use Selection for Find" elsewhere.
- Terminal.
- Show hidden files.
- Open at login.
- The "Always open with" list per extension, with a − button to remove entries.

## Later

- Visible progress for large copies.

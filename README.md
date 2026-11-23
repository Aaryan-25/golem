# Golem

My own PC system for the Dell Latitude 3180. It's truthful, offline by default, keyboard first,
and nothing gets access unless I allow it.

This is a fresh start. The old attempt lives in `Aaryan-25/shilp`, and it's kept only for reference.

## Where to look
| File | What it holds |
|---|---|
| [PLAN.md](PLAN.md) | The steps, in order. Each one has a test I do on the laptop. **Start here.** |
| [DECISIONS.md](DECISIONS.md) | Things already decided, so they don't get argued again. |
| [PANEL.md](PANEL.md) | Everything the Control Panel could hold, grouped by how much input and work each needs. |
| [TESTS.md](TESTS.md) | The checklist for testing on the laptop. |
| [IDEAS.md](IDEAS.md) | Every idea that isn't in the plan yet. Ideas wait here and are never built from here. |
| [CLAUDE.md](CLAUDE.md) | Rules Claude follows in every chat about this repo. |

## The four rules
1. **One step at a time.** Only the step marked NOW in PLAN.md gets worked on.
2. **The laptop is the judge.** A step is done when its test passes on the Dell, not when GitHub shows a green tick.
3. **Small and explained.** Every change can be explained in plain words before it's made.
4. **Ideas wait.** New ideas go into IDEAS.md. They only get built after I move them into PLAN.md myself.

## Put Golem on the pendrive
1. On GitHub, open this repo's **Releases** and download `golem.img.xz`.
2. Unplug every USB drive except the pendrive. In Rufus, pick the pendrive (check it says about 64 GB),
   press SELECT, choose `golem.img.xz`, then Start. If Rufus asks, choose "DD image".
3. Restart the laptop, press **F12** at the Dell logo, and pick the pendrive.
4. Golem starts straight in (no lock screen). Open a terminal
   (Alt+Enter) and type `passwd` to set your own password (the first one is **arise**).

The laptop's SSD and Windows are never touched.

## Keys
Super = the Windows key. **Super+H** shows the full list on screen. Every key can be changed in the Control Panel.

| Key | Does |
|---|---|
| Super+Z | Control Panel |
| Alt+Space | open an app (asks its zone the first time, then always opens in that zone) |
| Alt+Enter | terminal |
| Alt+Tab | switch window (list of names) |
| Alt+Q | close window (asks first) |
| Alt+F | fullscreen |
| Super+arrows / Super+Shift+arrows | focus / move windows |
| Super+= / Super+- | bigger / smaller |
| Super+F1 / F2 / F3 | next window beside / below / turn the split around |
| Super+1…4 / Super+Shift+1…4 | go to a workspace / send the window there (its app opens there from now on) |
| Super+I | face: Shadow / Negative |
| Super+Escape | the Start panel: CONTINUE, GADA (editor), FATE (Control Panel), SUMMON (apps), SLUMBER (sleep, restart, shut down) |
| Super+T | truth log: what the system did |
| Super+N / Super+W | Wi-Fi on/off / choose a network |
| Super+R | reload keys and windows |
| Volume, mute, mic, brightness keys | what they say |

New windows don't take focus: move to them with Alt+Tab or Super+arrows.

To turn off the laptop: Super+Escape, or type `poweroff` in a terminal.

- **Golem starts straight in:** no lock screen for now. The password is asked only when settings change.
- **The start menu** waits 3 seconds. Choose **Golem - text only** to start without the picture; it shows what went wrong last time (`golem-why`).
- **Lid:** closing it sleeps.
- **Idle:** the screen dims at 4 minutes, locks at 5 (not while Caps Lock is ON), and the laptop sleeps at 30.
- **Start-up is silent.** Hold **Shift** while it starts to see the menu with older versions.
- **The clock never syncs over the internet by itself.** To set it: Control Panel > NETWORK (once from the internet, or by hand), with your password.
- In a terminal, `golem-wifi` turns Wi-Fi on or off and says which.

## Control Panel (Super+Z)
A game menu for the whole system, keyboard only. Behind it, motes of light drift in the dark; between pages the
old page melts into falling particles and the new one gathers in, with faint tracker lines. **Super+I** (or
MIMIC > FACE) turns the realm inside out: **Shadow** (pale light on black) ⇄ **Negative** (ink on white), for the
whole desktop.

**Q / E** switch groups · **↑↓** move · **Enter** open / change · **Esc** back · **F** find anything · **I** face

| Group | Pages |
|---|---|
| SPELL | RUNNING (apps in zones, memory, close) · STARTUP (everything running, stop with password, core ones warned) · STORAGE (space used, clean unused pieces) · SAVE SLOTS (older versions; the newest 3 always kept) · ABOUT |
| WEAVE | APPS (each app's zone and permissions) · KEYS (press new keys) · DRIVERS (camera, microphone, Bluetooth, Wi-Fi card, USB drives, card reader, touchpad: off = not loaded at all; and parts with no driver) · NETWORK (Wi-Fi, Bluetooth, clock once from the internet or by hand) · SOUND & SCREEN (volume, mic, brightness) · POWER (battery, health, dim/lock/sleep times, processor mode, charge limit) · KEYBOARD (repeat, touchpad speed) |
| MIMIC | FACE (Shadow/Negative) · COLOURS · ANIMATIONS (effects, motes) · TEXT · WINDOWS (windows as sand) · NIGHT LIGHT · RED ALERT (key and presses, battery and drive alerts, test) · in progress: START SCREEN · LOCK SCREEN · WALLPAPER · TRANSITIONS · KEYBOARD LIGHT · WAKING UP |
| MEMORIES | TRUTH LOG (filter: apps, internet, devices, passwords, settings, system) · PRIVACY (tracker and ad blocking, telemetry, sharing, history, hidden name and MAC, certificates) · BACKUPS (save and load your settings by name) |
| TRUE NAME | ZONES · ALL KEYS · GOLEM (the principles) |

Changes wait on a copy: **A** applies them (your password, once), **X** throws them away, Esc with changes
waiting asks first. At once, without the password: closing an app, volume, brightness, Wi-Fi, Bluetooth, the look.
Admin actions (stopping a service, the clock, cleaning, save slots, backups) ask the password each time.
Settings live in `/var/lib/golem`: you can read them, only the panel (with your password) changes them.
Every change goes to the truth log.

## Red alert
The only thing that ever covers the screen by itself: a full red screen, dismissed by pressing the chosen key
several times (MIMIC > RED ALERT). It comes when the battery runs low and isn't charging, when the drive is almost
full, or when the Control Panel can't open.

## Truth log
**Super+T** (or `golem-truth` in a terminal) shows what the system did, in plain words, newest at the bottom,
kept 30 days: apps opened and closed (with zone and permissions), every internet connection (which app, which
site, how long, data in and out; written when the connection ends), USB plugged in and out, admin rights used,
wrong passwords, lock and unlock, Wi-Fi on and off, networks joined, zone and window changes, updates.

## Zones
`zone red|offline|yellow|green <app>` runs an app in a zone this time. `zone <app>` uses the app's settings
(RED if it has none). An app opened from Alt+Space asks its zone once; after that only the Control Panel changes it.
`zone show <app>` says what it may do.
Your folders: `documents`, `projects`, `media`, and `zones`, where each app keeps its own folder.
App settings are in `/var/lib/golem/apps` (window placements stay in `~/zones/settings`).

## Text editor (Super+E)
Notepad-style typing in Cool Retro Term's glass, in Golem's colours. **F1 inside it shows every key.**
Autosave with an honest SAVED / NOT SAVED line, find and replace, files panel (Ctrl+B), Ctrl+P to find a file,
F5 runs the file, Ctrl+J a terminal (Alt+S switches shell), F6 live preview of HTML and Markdown, F7 a picture
of the code, Ctrl+K the AI (Gemini with your key; your own AI later). A gada flies in, travels the bottom line
while things work, strikes when you save, and reacts to finds, replaces, undo, deletes, runs, failures and the AI;
relics are found along the way. Alt+G: animations HIGH / MEDIUM / LOW / OFF, weapon (gada, vajra, trishul), sound, codex,
spell check and word suggestions. Opening it without a file shows its dashboard (a big gada, today, pinned and recent files,
battery / memory / Wi-Fi). Super+O opens it with the file finder. F6 also shows Hindi / Sanskrit text with letters joined.
F9 draws the code as a flowchart beside it (live for Python); F10 opens a block builder that writes Python, JavaScript or Lua as you snap blocks. Pictures, music, video, PDFs and links open in their own
apps; Word and Excel open inside the editor, as a document and a table. There is no Firefox in Golem.
Languages it can run: `editor/languages.nix`. Extensions: `editor/extensions.nix`. Add a name on GitHub, then `golem-update`.
It starts in GREEN with internet (for the AI), sound and USB allowed; the Control Panel can change that.

## Updating (no reinstalling)
Turn Wi-Fi on, open a terminal and type `golem-update`.
- It shows **what changed** and which files. Press `d` to see every changed line.
- It changes nothing until you press `y`.
- Every update is listed in `~/golem-updates.txt`.
- The recipe itself is in `~/golem`, readable any time.
- If an update ever breaks something, restart and pick the older version from the boot menu.

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
4. Golem starts into a dark lock screen: type the password `golem` and press Enter. Then open a terminal
   (Alt+Enter) and type `passwd` to set your own password.

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
| Super+L | lock the screen |
| Super+I | face: Shadow / Negative |
| Super+Escape | power: lock, sleep, restart, shut down, log out |
| Super+T | truth log: what the system did |
| Super+N / Super+W | Wi-Fi on/off / choose a network |
| Super+R | reload keys and windows |
| Volume, mute, mic, brightness keys | what they say |

New windows don't take focus: move to them with Alt+Tab or Super+arrows.

To turn off the laptop: Super+Escape, or type `poweroff` in a terminal.

- **Golem starts straight into the lock screen:** a dark screen with no name and no box. Type your password and press Enter.
- **Lid:** closing it sleeps. On waking it's locked, unless Caps Lock was ON.
- **Idle:** the screen dims at 4 minutes, locks at 5 (not while Caps Lock is ON), and the laptop sleeps at 30.
- **Start-up is silent.** Hold **Shift** while it starts to see the menu with older versions.
- **The clock never syncs over the internet by itself.** To set it: Control Panel > NETWORK (once from the internet, or by hand), with your password.
- In a terminal, `golem-wifi` turns Wi-Fi on or off and says which.

## Control Panel (Super+Z)
A game menu for the whole system, keyboard only. Behind it, motes of light drift in the dark; between pages the
old page melts into falling particles and the new one gathers in, with faint tracker lines. **Super+I** (or
LOOK > FACE) turns the realm inside out: **Shadow** (pale light on black) ⇄ **Negative** (ink on white), for the
whole desktop.

**Q / E** switch groups · **↑↓** move · **Enter** open / change · **Esc** back · **F** find anything · **I** face

| Group | Pages |
|---|---|
| SYSTEM | RUNNING (apps in zones, memory, close) · STARTUP (everything running, stop with password, core ones warned) · STORAGE (space used, clean unused pieces) · SAVE SLOTS (older versions; the newest 3 always kept) · ABOUT |
| CONTROLS | APPS (each app's zone and permissions) · KEYS (press new keys) · DRIVERS (camera, microphone, Bluetooth, Wi-Fi card, USB drives, card reader, touchpad: off = not loaded at all; and parts with no driver) · NETWORK (Wi-Fi, Bluetooth, clock once from the internet or by hand) · SOUND & SCREEN (volume, mic, brightness, night light) · POWER (battery, health, dim/lock/sleep times, processor mode, charge limit) · KEYBOARD (repeat, touchpad speed) |
| LOOK | FACE (Shadow/Negative, effects, motes) · ALERTS (red alert key and presses, battery and drive alerts, test) |
| YOU | TRUTH LOG (filter: apps, internet, devices, passwords, settings, system) · PRIVACY (tracker and ad blocking, telemetry, sharing, history, hidden name and MAC, certificates) · BACKUPS (save and load your settings by name) |
| CODEX | ZONES · ALL KEYS · GOLEM (the principles) |

Changes wait on a copy: **A** applies them (your password, once), **X** throws them away, Esc with changes
waiting asks first. At once, without the password: closing an app, volume, brightness, Wi-Fi, Bluetooth, the look.
Admin actions (stopping a service, the clock, cleaning, save slots, backups) ask the password each time.
Settings live in `/var/lib/golem`: you can read them, only the panel (with your password) changes them.
Every change goes to the truth log.

## Red alert
The only thing that ever covers the screen by itself: a full red screen, dismissed by pressing the chosen key
several times (LOOK > ALERTS). It comes when the battery runs low and isn't charging, when the drive is almost
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

## Updating (no reinstalling)
Turn Wi-Fi on, open a terminal and type `golem-update`.
- It shows **what changed** and which files. Press `d` to see every changed line.
- It changes nothing until you press `y`.
- Every update is listed in `~/golem-updates.txt`.
- The recipe itself is in `~/golem`, readable any time.
- If an update ever breaks something, restart and pick the older version from the boot menu.

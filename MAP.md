# MAP.md: how Golem is put together

This is the map of Golem's code, written for whoever reads it next (a person, or an AI helping the owner).
It says what each file does, how the parts talk to each other, where things live on the running laptop,
and how to change something without breaking the rest. Read it before changing code.

**The owner can't read code.** He steers by plain-language explanations and by testing on his laptop.
Everything Golem shows him, and every note in the code, is written in plain words. Keep it that way.

---

## 1. Read these first

| File | What it is |
|---|---|
| `CLAUDE.md` | The rules for any AI working here. **Follow them.** One step at a time (PLAN.md), ask before long work, small changes, new ideas go to IDEAS.md, follow DECISIONS.md. |
| `PLAN.md` | The road: what's built, what's NOW, what comes next. Only work on the step marked NOW. |
| `DECISIONS.md` | Choices the owner made (and why). If one seems wrong, ask him; never change it quietly. |
| `IDEAS.md` | Ideas for later. Not to be built until they move into PLAN.md. |
| `TESTS.md` | What the owner checks by hand on the real laptop (the last word on whether a step is done). |
| `README.md` | For the owner: how to put Golem on the pendrive, start it, update it. |
| `PANEL.md` | The Control Panel's pages, described for the owner. |
| `ANIMATIONS.md` | A guide for the separate chat where the animations are designed. |
| `MAP.md` | This file. |

---

## 2. What Golem is, in one breath

Golem is the owner's own operating system, built on **NixOS** (the whole system is one recipe, `flake.nix`,
and every build from the same recipe is the same). It runs from a **pendrive** on his two laptops
(Dell Latitude 3180: Celeron N3350, 4 GB; Asus TUF FX506LH: i5-10300H, 8 GB, NVIDIA GTX 1650).

Its promise is **truthfulness**: the system does nothing he didn't ask for, and says plainly what it did
(the **truth log**). Every app runs in a **zone** that decides what it may touch; the only way to the
internet is **the Gate**, which asks him about each new site. The look is the **shadow realm**: black and
white, things drawn as drifting sand, letters cut like old stone (**Golem Runes**).

---

## 3. The folders

```
flake.nix            The whole recipe: which parts make up Golem, the test, and the pendrive image.
flake.lock           Exactly which version of NixOS the recipe uses (changed only on purpose).
system/              Starting up, hardware, power, updates, reports, the self-test, installing, the phone.
settings/            The owner's settings and the pieces that make them real; the look (faces), the red alert.
truth/               The truth log, and the watcher that writes every internet connection into it.
zones/               Zones and rooms (what each app may touch), the Gate (internet), the browser.
realm/               The shadow realm: the Start panel and idle screen (sand), the runes, the keys and windows.
panel/               The Control Panel (Super+Z) and the guard that is the only one allowed to change settings.
echo/                Echo: the owner's AIs (talk, feeding, hands, extensions, training).
editor/              GADA: the text editor (Neovim inside Cool Retro Term) and all its tools.
keylight/            The keyboard's lights.
tests/               The automated test: GitHub starts Golem in a virtual laptop and checks it.
.github/workflows/   check.yml (the test on every change), image.yml (builds the pendrive image on request).
```

Each part has a `.nix` file (the recipe for that part: what gets installed, which services run, which
commands exist) and the code files it uses (`.py` Python, `.lua` editor code, `.sh` shell, `.html` pages).
Every file starts with a few lines saying what it is. The `.nix` files are listed in `flake.nix`.

---

## 4. How a start goes (from the power button to the Start panel)

1. **The pendrive's boot menu (GRUB)** shows "Golem" for 3 seconds, plus "text only" (a start without the
   picture, for when the screen stays black). `system/truthful.nix`, `system/golem.nix`.
2. **Linux starts**, quietly but not hidden (warnings still show). Drivers load for the hardware found:
   the firmware list is in `system/golem.nix` (only what the two laptops need); the NVIDIA card in
   `system/nvidia.nix` (it loads only if the card is there, and sleeps when unused).
3. **The owner is logged in by himself** (no password at start, no lock screen: decided 22 Nov 2026).
   `system/idle.nix` (autologin), `system/golem.nix` (`loginShellInit`).
4. **The picture starts** (`startx`, tried 4 times; if it never comes, a message says to type `golem-why`).
5. **The window manager (i3) starts** with Golem's keys and rules: `realm/desktop.nix` writes its config.
   Its `exec` lines start the session helpers:
   - `golem-session-apply` (settings: idle, keyboard, touchpad, night light, face) `settings/session_apply.py`
   - `golem-alert --watch` (the red alert) `settings/alert.py`
   - `xss-lock … golem-idle` (dim, idle screen, sleep) `system/idle.nix`
   - `golem-realm --daemon` (the sand engine; wakes up into the Start panel) `realm/realm.py`
   - `golem-gate ask` (shows the Gate's questions) `zones/gate_ask.py`
   - `golem-tune` (the window in front gets the computer's attention) `system/optimiser.nix`
   - `golem-clip watch` (clipboard history, memory only) `realm/desktop.nix`
   - `golem-echo-hands` (the only way an Echo can do more than talk) `echo/hands.py`
6. **The Start panel** (sand): CONTINUE, GADA (the editor), ECHO, FATE (the Control Panel), SUMMON (open
   an app), SLUMBER (sleep / restart / shut down). `realm/realm.py` (`TABS`).

System services started before all this: the Gate (`zones/gate.nix`), the truth log's internet watcher
(`truth/truth.nix`), the guard (`panel/panel.nix`), the settings applier (`settings/look.nix`),
Wi-Fi (off at every start: `system/truthful.nix`), the memory guard (`system/optimiser.nix`).

---

## 5. The big ideas, and where each one lives

### 5.1 The truth log (`truth/`)
- **Writing to it:** any part writes a plain sentence with `logger -t golem "…"` (in Python:
  `subprocess.run(["logger", "-t", "golem", msg])`, or `syslog` with ident `golem`). Other tags it reads:
  `zone`, `golem-net`, `golem-gate`, `earlyoom`, `golem-usb`, `sudo`, `login`, `su`, `NetworkManager`,
  `systemd-coredump` (the list is `SOURCES` in `truth/truth.py`).
- **Reading it:** `golem-truth` (Super+T) turns those journal lines into sentences (`sentence()` in
  `truth/truth.py`). Kept 30 days (`truth/truth.nix`).
- **Internet:** `truth/netwatch.py` notes each connection when it ends (which app, zone, site, how long,
  how much), using the laptop's own DNS answers.
- **Rule:** if Golem does something the owner would want to know about, write it to the truth log. Never
  write something that didn't happen.

### 5.2 Zones and rooms (`zones/zones.nix`)
- Every app the owner opens goes through `zone <app>` (the launcher `golem-launch` in `realm/desktop.nix`
  does this). Four zones: **RED** (nothing: no internet, no home folder), **OFFLINE** (its own folder, no
  internet), **YELLOW** (its own folder, internet through the Gate), **GREEN** (trusted: my own screen and
  files). Built with firejail (sandbox) and systemd (memory and processor limits).
- Each app's settings: `/var/lib/golem/apps/<app>.conf` (lines like `zone=offline`, `ram=2G`, `cpu=200%`,
  `internet=`, `camera=`, `sound=`, `usb=`, `nvidia=`, `folder=`). Only the Control Panel changes them.
- **Limits** come from `settings/settings.nix` (`limits`), doubled on computers with 6 GB or more
  (`bigger` in the same file).
- **Rooms:** a RED, OFFLINE or YELLOW app with a window gets its own sealed screen (a Xephyr window titled
  `ROOM | ZONE | app | :N`), so it can't see other windows, keys or the clipboard. `golem-carry in|out`
  (Super+C / Super+Shift+C) moves the clipboard in or out, and logs it.

### 5.3 The Gate (`zones/gate.nix`, `zones/gate.py`, `zones/gate_ask.py`)
- The firewall stops the owner's programs from reaching outside directly. Everything is pointed at the Gate
  (`http_proxy` / `https_proxy` = `127.0.0.1:3128`).
- The first time an app wants a site, the Gate asks (once / always / never / anywhere) through
  `golem-ask` (a small menu, `realm/desktop.nix`). Answers: `/var/lib/golem-gate/rules.json`. Every request:
  the truth log, and `/var/lib/golem-gate/feed.jsonl` (for Echo to watch, later).
- **HIDDEN** mode sends everything through Tor (`golem-gate hidden`). System services (updates, clock,
  Wi-Fi) are not the owner's apps and are not asked about.
- The browser (`zones/browser.py`, Super+B) is the only browser: YELLOW, through the Gate, keeps nothing,
  no JavaScript unless turned on for a site (Ctrl+J), no pop-ups.

### 5.4 Settings (`settings/`, `panel/`)
How one setting travels:
1. `settings/settings-schema.json` lists every setting (its values, its default, which page shows it).
2. The Control Panel (`panel/panel.py`, Super+Z) shows them. Groups: **SPELL** (what's running, startup,
   storage, save slots, about), **WEAVE** (apps, keys, drivers, network, the Gate, sound and screen, power,
   keyboard), **MIMIC** (the look), **MEMORIES** (truth log, privacy, backups), **TRUE NAME** (zones, all
   keys, Golem itself).
3. Changing one asks for the password and goes to the **guard**, `golem-helper` (`panel/helper.py`, runs
   as root, socket `/run/golem-helper.sock`). Only the guard writes `/var/lib/golem/settings.conf`,
   `/var/lib/golem/apps/*.conf` and `/var/lib/golem/keys.conf`, and it logs every change.
4. The system side is made real by `golem-settings-apply` (`settings/settings_apply.py`, root: drivers,
   microphone, power mode, battery limit, ad blocking); the owner's side by `golem-session-apply`
   (`settings/session_apply.py`: idle, keyboard, touchpad, night light, face).
- Settings fixed at build time (user name, theme colours, zone limits, the GitHub repo): `settings/settings.nix`.
- Keys: `/var/lib/golem/keys.conf` → `golem-keys-gen` (`panel/keysgen.py`) → i3's key lines and the
  Super+H list. Golem's default keys: the `keys` list in `realm/desktop.nix`.

### 5.5 The shadow realm (`realm/`)
- `realm/realm.py` (`golem-realm`): one program for the whole session, drawing with the graphics chip
  (OpenGL: moderngl + glfw). Four layers of sand grains: the tabs, the scenery, a window or page, dust.
  Commands arrive on a socket (`$XDG_RUNTIME_DIR/golem-realm.sock`): `show`, `idle`, `hide`,
  `win close|min|full|moved`, `page A.png B.png`.
- `realm/runes.py` makes the **Golem Runes** font at build time from Caladea Bold (Cambria's free twin):
  chips, cracks and pits, traced back into letters (`realm/realm.nix`).
- `realm/sand.py` (`golem-sand`): the sand test, to check a laptop can carry the look.
- `realm/desktop.nix`: i3's config (no bars, no titles, focus by keys), the keys list, window helpers
  (`golem-win`: close, minimise, full, switch, send to a workspace), the launcher (`golem-launch`), sound
  keys (`golem-sound`), the small menu (`golem-ask`), clipboard history (`golem-clip`).

### 5.6 Echo (`echo/`)
- **Echos** are the owner's AIs. Each is its own person: a name, a description of its personality and
  quirks, and the way it talks, learned only from chats he feeds it. They **only talk**.
- `echo/echo.py` (`golem-echo`, ECHO in the Start panel): the app and the command line. Sections TALK,
  ECHOS, FEEDING, MEMORY, RULES, COMPARE, PERMISSIONS, EXTENSIONS, ACTIONS, AVATAR, CARRY. Runs in the
  OFFLINE zone. Its data: `~/zones/golem-echo/echo/` (inside its zone that folder is its home).
- **The brain:** llama.cpp's `llama-server` on `127.0.0.1:8091`, with Llama 3.2 (1B on the Dell, 3B on the
  Asus), fetched once by `golem-echo-brain` through the Gate into `…/echo/brain/`.
- **Feeding:** `echo/feed.py` reads WhatsApp exports (Android and iPhone formats) or hand-edited chats from
  `~/zones/golem-echo/feed/`, keeps only the chosen person's messages (`samples.jsonl`); voice notes become
  text with whisper.cpp. A few real messages go into each conversation as examples of how to talk.
- **Hands:** `echo/hands.py` (`golem-echo-hands`, outside the zone, socket `…/echo/hands.sock`) is the
  only way an Echo can do more than talk. An Echo writes `USE name: …`; the hands ask the owner the first
  time (only this time / always / never), run the extension in its own zone, and log it (ACTIONS).
  Extensions live where Echo can't write: `~/.local/share/golem-echo/extensions/<name>/`
  (`extension.json` + a script). Permissions: `~/.config/golem-echo/permissions.json`.
- **Training** (the Asus): `echo/train.py` (`golem-echo-train`, OFFLINE zone, NVIDIA allowed) trains a
  small voice layer (LoRA) per Echo on its fed messages; `golem-echo-trainer` fetches its tools once.
  The voice is used by loading it into `llama-server` (`wake_brain()` in `echo/echo.py`).
- **STOP:** Super+Shift+E (`golem-echo stop`) stops every Echo, its brain and every running extension.

### 5.7 GADA, the editor (`editor/`)
- `editor/editor.nix` builds it: Neovim with Golem's Lua code (`editor/*.lua`), inside Cool Retro Term.
  `golem-edit [file]` opens it; the dashboard shows first.
- Lua files (each starts with what it does and its keys): `init.lua` (Notepad-like keys, truthful
  SAVED), `dashboard.lua`, `files.lua` (FILES explorer, Alt+E), `writing.lua` (spelling, pins and groups),
  `panels.lua` (side panels, run F5, preview F6, flowchart F9, blocks F10, wires F11, map F12),
  `flow.lua`, `mace.lua` (the gada, the animated mace), `palette.lua` (F1 list), `intro.lua` (tour),
  `ai.lua` (Ctrl+K, Gemini only with the owner's key).
- Helper programs in `editor/bin/`: `golem-run`, `golem-open`, `golem-view` (shows local pages only),
  `golem-preview`, `golem-office` (Word / Excel), `golem-blocks`, `golem-wires`, `golem-map`, `golem-flow`,
  `golem-ai`. Pages: `blocks.html`, `wires.html`, `map.html`.
- Languages it can run: `editor/languages.nix`; extensions (Neovim plugins): `editor/extensions.nix`.
- The editor's own data: `~/.local/share/golem-edit/`.

### 5.8 Updates, reports, the optimiser (`system/`)
- `golem-update` (`system/update.nix`): fetches the recipe from GitHub into `~/golem`, shows what changed,
  asks, rebuilds, logs to `~/golem-updates.txt`. No reinstalling.
- `golem-report` (`system/optimiser.nix`): writes a report (self-test, errors, hardware, truth log, Gate
  rules, updates; a screen picture with `--screen`) and pushes it to the owner's private `golem-reports`
  repo with his token (`~/.config/golem-report/token`). Runs after each update when set up.
- The optimiser (`system/optimiser.nix`): compressed memory (zram), a memory guard (earlyoom), `golem-tune`
  (the window in front gets more processor), power mode by charger, small logs, weekly clean-up.
- `golem-selftest` (`system/selftest.sh`): checks on the real laptop what a machine can check by itself.
- `golem-why`: what went wrong at this start (or the one before).

### 5.9 Hardware (`system/`, `keylight/`)
- Firmware for the two laptops: `system/golem.nix` (`hardware.firmware`).
- NVIDIA (the Asus): `system/nvidia.nix`. NVIDIA's own driver (the only closed part, the owner's choice),
  for computing only; only apps marked `nvidia=allowed` may use it.
- Keyboard lights: `keylight/keylight.py` (`golem-keylight`): the Dell's white light, the Asus's colour.

### 5.10 Installed on a laptop, and reached from the phone (`system/install.nix`, `disk.nix`, `remote.nix`)
- **Two Golems from one recipe** (`flake.nix`): `golem` (the pendrive) and `golem-disk` (installed on a
  laptop's own disk). They differ only in `system/disk.nix`: the disk's parts are labelled `golem` and
  `GOLEM-BOOT` (the pendrive's: `nixos` and `ESP`). `/etc/golem/config-name` says which one is running, and
  `golem-update` rebuilds that one.
- **`golem-install`** (`system/install.nix`, only on the pendrive): the pendrive carries the installed
  Golem ready-made, so installing needs no internet. It never offers the pendrive itself, shows what's on the
  chosen disk, and does nothing unless the owner types ERASE. Then: two parts, `nixos-install`, optionally
  the owner's files. **`golem-install-ui`** (`system/install_ui.py`, INSTALL in the Start panel, only on the
  pendrive) is the same in a small window: disk tiles, type ERASE, password, sand pouring into a bar; its
  SEND TO CLAUDE button runs `golem-report --screen` (the report includes `/var/log/golem-install.log`).
- **`golem-remote`** (`system/remote.nix`): off until turned on (`/var/lib/golem/remote-on`).
  Tailscale links the owner's own devices (encrypted); `golem-remote-screen` (started by i3) shares the real
  screen with x11vnc (port 5900) and noVNC in a browser (port 6080), only on the Tailscale link, with a
  password. While on, `golem-remote-awake` keeps the laptop from sleeping (also with the lid closed). Every
  connection goes to the truth log (`Remote: ...`).

### 5.11 The staying-on guard (`system/guard.nix`)
- Always: `golem-heat` (service) watches the processor's temperature: slows it at 85 °C, full speed again under
  70 °C, shuts down safely at 95 °C; each step in the truth log. `golem-disk-health` (weekly) logs each disk's health.
- While remote is on: the battery stops at 60% (`golem-remote-awake` in `remote.nix`; my own setting comes back
  when remote is turned off), and idle turns the screen fully off instead of the moving sand (`idle.nix`).

---

## 6. Every command, and where it comes from

| Command | What it does | Made in |
|---|---|---|
| `zone` | run an app in its zone; `zone show`, `zone set`, `zone defaults` | `zones/zones.nix` |
| `golem-carry` | clipboard into / out of a room | `zones/zones.nix` |
| `golem-net-test` | checks that the internet goes only through the Gate | `zones/zones.nix` |
| `golem-gate` | the Gate: ask, on, off, hidden, status, rules, forget | `zones/gate.nix`, `zones/gate_ask.py` |
| `golem-browser` | the browser | `zones/browser.nix`, `zones/browser.py` |
| `golem-truth` | the truth log | `truth/truth.nix`, `truth/truth.py` |
| `golem-panel`, `golem-panel-start` | the Control Panel | `panel/panel.nix`, `panel/panel.py` |
| `golem-helper` | the guard (root service) | `panel/panel.nix`, `panel/helper.py` |
| `golem-keys-gen` | keys file → i3 lines | `panel/keysgen.py` |
| `golem-settings-apply` | settings, system side | `settings/look.nix`, `settings/settings_apply.py` |
| `golem-session-apply` | settings, the owner's side | `settings/look.nix`, `settings/session_apply.py` |
| `golem-face` | Shadow / Negative face | `settings/look.nix` |
| `golem-alert` | the red alert | `settings/look.nix`, `settings/alert.py` |
| `golem-term` | the terminal | `settings/look.nix` |
| `golem-realm` | the sand engine | `realm/realm.nix`, `realm/realm.py` |
| `golem-sand` | the sand test | `realm/sand.nix`, `realm/sand.py` |
| `golem-launch`, `golem-win`, `golem-sound`, `golem-ask`, `golem-clip` | launcher, windows, sound, small menu, clipboard history | `realm/desktop.nix` |
| `golem-idle` | dim, idle screen, sleep | `system/idle.nix` |
| `golem-wifi` | Wi-Fi on / off | `system/truthful.nix` |
| `golem-why` | what went wrong at start | `system/golem.nix` |
| `golem-update` | updates from GitHub | `system/update.nix` |
| `golem-report`, `golem-tune` | reports to GitHub; window in front gets attention | `system/optimiser.nix` |
| `golem-selftest` | the self-test | `system/selftest.nix`, `system/selftest.sh` |
| `golem-echo`, `golem-echo-brain`, `golem-echo-hands`, `golem-echo-train`, `golem-echo-trainer` | Echo | `echo/echo.nix` |
| `golem-keylight` | keyboard lights | `keylight/keylight.nix`, `keylight/keylight.py` |
| `golem-heat`, `golem-disk-health` | heat watch; weekly disk health | `system/guard.nix` |
| `golem-install`, `golem-install-ui` | put Golem on a laptop's own disk (from the pendrive), typed or in a window | `system/install.nix`, `system/install_ui.py` |
| `golem-remote`, `golem-remote-screen` | reach this laptop from the phone | `system/remote.nix` |
| `golem-edit`, `golem-edit-open`, `golem-view`, `golem-office`, `golem-preview`, `golem-blocks`, `golem-wires`, `golem-map`, `golem-flow` | the editor and its tools | `editor/editor.nix`, `editor/bin/` |

---

## 7. Where things live on the running laptop

| Place | What | Who may change it |
|---|---|---|
| `/var/lib/golem/settings.conf` | the owner's settings | the guard only |
| `/var/lib/golem/apps/<app>.conf` | each app's zone and permissions | the guard only (and `zone set` for a new app) |
| `/var/lib/golem/keys.conf`, `keys.i3`, `keys.txt` | keys | the guard / keysgen |
| `/var/lib/golem/backups/` | save slots | the guard |
| `/var/lib/golem-gate/rules.json`, `feed.jsonl` | the Gate's answers and its record | the Gate |
| `/run/golem-helper.sock`, `/run/golem-gate/` | the guard's and the Gate's sockets | — |
| `/etc/golem/` | things the build puts in place (version, settings schema) | the build |
| `~/zones/<app>/` | the folder of an OFFLINE or YELLOW app (its home inside its zone) | that app |
| `~/zones/settings/` | the owner's session pieces (face, placements, scenery.png) | session helpers |
| `~/zones/golem-echo/echo/` | Echo: echos, brain, trainer, hands socket, actions | Echo and its hands |
| `~/zones/golem-echo/feed/` | chats waiting to be fed to an Echo | the owner |
| `~/.local/share/golem-echo/extensions/` | Echo's extensions | the owner (Echo can't) |
| `~/.config/golem-echo/permissions.json` | what each Echo may use | the hands, after asking |
| `~/.local/share/golem-edit/` | the editor's data | the editor |
| `~/.config/golem-report/token` | the GitHub token for reports | `golem-report setup` |
| `~/golem/`, `~/golem-updates.txt` | the recipe for updates, the update log | `golem-update` |
| `/etc/golem/config-name` | `golem` (pendrive) or `golem-disk` (installed) | the build |
| `/var/lib/golem/remote-on` | exists = the phone may reach this laptop | `golem-remote on/off` |
| `~/.config/golem-remote/passwd` | the screen password for the phone | `golem-remote setup` |

---

## 8. Tests: how to know nothing broke

- **On every change** GitHub runs `tests/tests.nix` (workflow `.github/workflows/check.yml`): it starts
  Golem in a virtual laptop and checks each step (login, keys, zones, rooms, the Gate, HIDDEN, the browser,
  the realm, Echo, wires, the map, keylight, NVIDIA marking, the optimiser, the self-test…). Each check is a
  `with subtest("…")` block with a plain name.
- **The pendrive image** is built only on request (`image.yml`), and only with the owner's yes.
- **On the real laptop:** `golem-selftest`, and the owner's checklist in `TESTS.md`. A step is done only
  when he says its test passed on the laptop.

---

## 9. How to change Golem safely (for an AI)

1. Read `CLAUDE.md`, `PLAN.md` (the NOW step), `DECISIONS.md`. Explain the change to the owner in plain
   words and get a yes before long work.
2. Find the part in this map. Read the whole file you change, and its header.
3. Make the change small. Keep the plain-language style: in messages the owner sees, in comments, in
   commit messages.
4. Check before pushing:
   - The recipe evaluates: `nix eval .#nixosConfigurations.golem.config.system.build.toplevel.drvPath`
     and `nix eval .#checks.x86_64-linux.vm.drvPath`.
   - Shell scripts inside `.nix` files are checked by `shellcheck` at build time: check them first.
   - Python: `python3 -m pyflakes FILE`; Lua: load it in Neovim headless.
   - Add a `subtest` to `tests/tests.nix` for what you built.
5. Push; wait for the GitHub check to pass; fix what it says.
6. **To prove a change only moves or renames things**, compare the build's recipe hash before and after
   (`nix eval --raw …drvPath`): identical hashes mean identical systems. (Used for the folder tidy, 24 Nov.)
7. Update this map when you add a file, a command, or a place on disk.

---

## 10. Words the owner uses

| Word | Means |
|---|---|
| **Golem** | the whole system |
| **GADA** | the text editor (and the gada, the mace drawn in it) |
| **ECHO** / an Echo | the owner's AIs; one Echo = one person it talks like |
| **FATE** | the Control Panel (Start panel tab) |
| **SUMMON** | open an app (Start panel tab) |
| **SLUMBER** | sleep, restart, shut down (Start panel tab) |
| **CONTINUE** | back to the desktop (Start panel tab) |
| **the shadow realm** | the look: black and white, drifting sand |
| **sand / drift / picture to picture** | how things appear, move and change in the look |
| **yin-yang flip** | Shadow ↔ Negative (white on black ↔ black on white), Super+I |
| **the Gate** | the only way to the internet |
| **zones** (RED, OFFLINE, YELLOW, GREEN) | what an app may touch |
| **rooms** | an app's own sealed screen |
| **the truth log** | what the system did, in plain words |
| **ember** | the one warm colour, used for mistakes and warnings |
| **LOW / OFF** | animation levels (Alt+G in the editor) |
| **SPELL, WEAVE, MIMIC, MEMORIES, TRUE NAME** | the Control Panel's groups |

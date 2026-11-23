# Decisions

These are already decided. They carry over from the old Shilp repo. Change one only when I say so.

## The machines
Golem runs on the Dell now and on my **Asus TUF F15 (FX506LH, GTX 1650)** later, from one setup
that detects which laptop it is on. The pendrive should also boot on any ordinary PC.

## The laptop
Dell Latitude 3180: Celeron N3350 (2 cores), 4 GB RAM, Intel HD 500, 128 GB M.2 SATA SSD (GPT),
Intel AC-7265 Wi-Fi. It runs Windows 10 for now, and a full backup image plus a rescue ISO are on an external drive.
I have one 64 GB pendrive. Golem runs from it until I decide to install to the SSD.

## Principles
The goal: **private, clean, usable.**
- **Private:** no app touches a file or permission I didn't give it. Nothing updates itself. All internet traffic is visible. Every app tells me what it may do and what it did.
- **Clean:** no bloat, no feature I didn't ask for, no process I can't kill, structured the way I want, and game-clean to look at.
- **Usable:** designed around my needs.
- **The Control Panel is the heart of the system, and it reigns supreme:** settings change only through it (or with my password), never by an app.
- **Truthful:** it does only what I say, shows what it did, and does nothing in the background.
- **Default = deny:** apps get nothing unless their zone and settings allow it.
- **Keyboard first:** no taskbar, no Start menu, no bars, no desktop popups.
- **Light:** it has to run well on the laptop above.
- **Ask first:** no code gets written before the need is clear.

## Specific decisions
| Topic | Decision |
|---|---|
| Base | NixOS, built from this repo. GitHub checks every change and builds the installer. |
| Account | User name `lilgolemwitch`. It's never shown or typed at login. |
| Zones | RED: nothing, disposable, wiped on close. OFFLINE: no internet, own folder. YELLOW: internet, and only its own folder (e.g. a browser's downloads), never my files. GREEN: trusted. BLUE (my AI) comes later. |
| Permissions | Each app's settings decide (allowed or never). Nothing is asked at launch. An app with no settings asks for its zone once. |
| Network | Wi-Fi off at every start. No time sync over the internet; the Control Panel can set the clock once from the internet, or by hand, with my password. |
| Windows | Tiling with an existing engine. No gaps, titles or borders, only a 1 px line on the focused window. Focus moves by keys only. |
| Close | Closing a window asks for confirmation. This is the one allowed popup. |
| Notifications | None. Only a full-screen red alert, dismissed by pressing a key several times. |
| Lock | **None** (decided 22–23 Nov 2026): Golem starts straight in, and idle shows the idle screen. The password, **arise**, is asked only by settings. |
| Lid | Closing it sleeps. (No lock on wake for now.) |
| Panels | The Control Panel and every system panel run in the GREEN zone. Apply asks the password once. |
| Look | The shadow realm: black background, everything else white; the yin-yang flip turns it over. Everything is sand (drift, picture to picture, the light). |
| Terminal | A light terminal now, Cool Retro Term later. |
| BIOS password | No. A PC password, maybe later. |
| Windows OS | Gets wiped, but only at the very end, after Golem works fully from the pendrive. |
| Save slots | Two things: SAVE SLOTS are older versions of the whole system (go back if an update breaks; the last 5 kept, the newest 3 never deletable from the panel), BACKUPS are my settings (keys, zones, look, quests) saved and loaded by name. |

## Decided on 23 Nov 2026
| Topic | Decision |
|---|---|
| Password | **arise** (the first password on a new install; `passwd` changes it). |
| Start panel | CONTINUE, GADA, ECHO, FATE, SUMMON, SLUMBER. |
| Echo | My AI: several Echos, each its own person (an avatar name, a description analysing its personality and quirks), shaped only by the chats I choose for it. It only talks; every other power comes from extensions I add, each with permissions I give. Offline (llama.cpp); voice notes become text offline (whisper.cpp); Hinglish, Hindi and English. |
| The Gate | The only way to the internet; asks once / always / never / any site for this app; HIDDEN through Tor. |
| Links | Open in golem-browser (no reader). |
| Rooms | RED, OFFLINE and YELLOW apps get their own sealed screen and clipboard; Super+C / Super+Shift+C carry the clipboard. |
| Reports | `golem-report` pushes the self-test, errors, version, hardware and the truth log to my private repo `golem-reports`; Claude reads only GitHub, never my PC. |
| Not now | Disk encryption, a lock, Wine, the reader, the round menu. A software manager comes later through Echo's extensions and the editor. |
| Keyboard light | Per key, as an experiment on the Asus (FX506LH). |

## Decided on 22 Nov 2026 (the shadow realm)
| Topic | Decision |
|---|---|
| Letters | My own made-up rune letters, carved-looking, readable as English. |
| Start panel | Like a game's start menu: tabs on the left (CONTINUE, GADA, FATE, SUMMON, SLUMBER), avatar or scenery on the right (added later). With the tabs blown away it's the idle screen, after a few minutes untouched. |
| Drift | Everything that isn't inside an app drifts. |
| Picture to picture | Almost every change: windows opening, closing, maximising, minimising, and page changes. Switches in MIMIC. |
| The light | The cursor is a small light in the sand; Enter or a click sends a pulse. |
| Editor | My main editor, opened by GADA, with its dashboard first. |

## Decided on 21 Nov 2026 (question round)
| Topic | Decision |
|---|---|
| Drivers | A driver finder that asks: it detects the hardware, says in plain words what's missing and why, downloads only after I say yes, and logs it. |
| NVIDIA (Asus) | Hybrid: the built-in GPU runs the desktop, NVIDIA wakes only for apps I mark (games, AI training). No switch for it; keep it safe and untouched. |
| Keyboard light (Asus) | Follows the LOOK palette's light colour, pulses red with the red alert, off at start. Probably one colour zone (to be checked on the laptop): whole-keyboard colour, 4 brightness levels, a few effects, no per-key designs. Any key can be bound to a light change. |
| Battery | Stop charging at 80% where the laptop allows it (Asus: yes; Dell: Linux if supported, else the BIOS setting, which Golem explains). |
| Idle | Dim at 4 min, lock at 5, sleep at 30. All timings changeable in the Control Panel. Caps Lock ON still stops locking. (Hibernate after 3 h asleep on battery is removed for now, to come back with the SSD install: see IDEAS.md.) |
| Internet traffic | Per app: which site (by name), when, and how much data in and out. Kept 30 days like the truth log. |
| Sites | Each app with internet has its own allowed-sites list (a browser can have "everything"). A new site is blocked, shown in the truth log, and I can add it. |
| Trackers and ads | A well-known block list (e.g. OISD or StevenBlack), built in, updated only when I say. |
| Clipboard | GREEN apps share one clipboard; RED, OFFLINE and YELLOW each keep their own. Only the last item, in memory, never on disk (a short history is an idea for later). |
| Screen | No app may see the screen (screenshots, recording, sharing) unless that app is allowed, like the camera. Golem's own screenshot key always works. |
| Driver switches | On/off (driver not loaded at all) for: camera + microphone, Bluetooth + Wi-Fi, USB ports + card reader, touchpad. |
| Zone limits | Shilp's limits on the Dell (RED 1G RAM / half a core, OFFLINE 1.5G / 1 core, YELLOW 2G / 1.5 cores, GREEN 2.5G / almost 2 cores), scaled up on the Asus. |
| History | None: no recent files, no searches remembered. **Exception (owner's choice, 22 Nov 2026): the text editor** keeps its recent and pinned files, last session, undo, spelling dictionary and relics, in `~/.local/share/golem-edit` and its own state folder. |
| Language | English only for now. |
| Guest | No guest user. |
| Folders | `documents`, `projects`, `media`, `zones` (each app's own folder; a YELLOW browser's downloads land in its folder there, and I move files out on purpose). |
| Software source | The app list on GitHub (nixpkgs), downloaded ready-built from cache.nixos.org with signatures checked. Only when I press update. |
| Updates | Only when I press update, after showing what will change. |
| Camera / mic in use | Truth log only for now (no on-screen sign). |
| Storage | A view of what uses space; it cleans only what I pick. |
| Startup list | Everything that starts at boot or on a timer, in plain words. Mine can be switched off; system ones only after my password, with a warning. |
| Crash reports | Kept on the laptop 7 days, shown in the truth log in plain words, never sent anywhere. |
| Certificates | A page listing them in plain words (country, organisation); any can be distrusted after my password. |

## The Control Panel (basic for now; a nicer UI comes later)
| Topic | Decision |
|---|---|
| Layout | One full-screen panel, keyboard only. Pages listed on the left, the chosen page on the right. ↑↓ move, Enter opens or changes, Esc goes back or leaves. |
| Look | Dark background, pale text; the chosen row is highlighted. No animations, no sounds yet. |
| Changes | Made on a copy. A applies them with my password once, X throws them away, Esc with changes waiting asks first. |
| At once | Things that can't wait happen at once without Apply: closing an app, volume, brightness. |
| Admin | Things that need admin rights ask my password each time. |
| Truth | Every change goes to the truth log. |
| If it fails | If the panel can't open, a red alert says so and the truth log has the reason. |

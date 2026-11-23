# Plan

**NOW: testing Steps A to E on the laptop** (the shadow realm look, asked for on 22 Nov 2026), with the last
part of [TESTS.md](TESTS.md). All five are built and pass GitHub's virtual-laptop test. (On the laptop, Step 9's build gave only a black screen, so Step A makes the screen visible first.)

Done: Step 1 (21 Nov 2026). Step 0 was skipped; its hardware checks moved into Step 3's test.

Each step has a goal, what gets made, and a **done when** test that I do myself on the Dell.
The next step only starts when the current one's test passes. If a test fails, the step stays
open and gets fixed. Nothing new gets added on top of a failing step.

---

## Step 0: Check the laptop with plain NixOS (skipped)
**Goal:** find out what works on this hardware before writing any code.
**Made:** nothing. Use the official NixOS live USB.

1. On Windows, download the NixOS **Graphical ISO** (GNOME) from nixos.org.
2. Flash it to the pendrive with Rufus ("DD image" mode if asked).
3. BIOS (F2): UEFI on, Secure Boot **off**. Then F12 and pick the pendrive.
4. Try each thing below and write ✅ or ❌ (a phone photo of any error helps).

**Done when** this list is filled in:
- [ ] Boots to the desktop
- [ ] Wi-Fi finds and joins my network
- [ ] Sound plays
- [ ] Volume and brightness keys work
- [ ] Closing the lid sleeps, and opening it wakes the laptop
- [ ] Battery percentage shows
- [ ] A USB stick shows up
- [ ] Rough feel: is it usable on 4 GB of RAM?

The SSD and Windows are not touched.

---

## Step 1: Golem's smallest self, on the pendrive ✅
**Goal:** my own system boots from the pendrive. It's plain, but it's mine.
**Made:** the recipe (NixOS flake), the GitHub check, and a pendrive image built by GitHub. You flash it and it's already Golem, with no installer step.
After boot: a login, a tiling window manager, a terminal, and Wi-Fi I can turn on.

**Done when:** I flash the image, start from the pendrive, log in, open a terminal (Alt+Enter),
and join Wi-Fi (Super+W).

## Step 2: Update without a new installer (built together with Step 1)
**Goal:** after this, changes reach the laptop with one command, not a new pendrive flash.
**Made:** `golem-update`. It shows what changed on GitHub (and every changed line, if I ask), asks first, then applies it.
Old versions stay in the boot menu, and every update is listed in `~/golem-updates.txt`.

**Done when:** a small visible change made on GitHub (for example, the terminal colour) reaches the laptop through `golem-update`,
and picking the older version from the boot menu still works.

## Step 3: Truthful base
**Goal:** the system does nothing I didn't ask for.
**Made:** Wi-Fi off at every start, no internet time sync, silent boot, a key to turn Wi-Fi on and off.

**Done when:** after a reboot Wi-Fi is off, nothing connects until I turn it on, and the boot shows no text.
Also check the hardware left over from Step 0: sound, volume and brightness keys, lid sleep, battery, a USB stick.

## Step 4: Zones
**Goal:** default = deny, so every app runs in a zone.
**Made:** one `zone` command: RED (nothing, wiped on close), OFFLINE (no internet, own folder),
YELLOW (internet, no files), GREEN (trusted). RAM and CPU limits per zone.

**Done when:** I run one real app in each zone and check what it can and can't do, using a short test sheet.

## Step 5: My keys and my windows
**Goal:** the desktop works the way I want: keyboard first, no bars, no popups.
**Made:** my key list (from Shilp), tiling with no gaps, titles or borders (only a thin focus line), a launcher
that always opens apps through their zone, a window switcher, close confirmation, remembered workspaces, power menu.

**Done when:** I use the laptop for a day with only the keyboard and nothing annoys me. Anything that does goes back into this step.

## Step 6: Lock screen and lid
**Goal:** a simple lock with no username and no box. I just type my password.
**Made:** login = lock screen (starts locked, no username, no box), Super+L, the lid rule (Caps Lock ON means no lock
on wake), idle: dim at 4 min, lock at 5, sleep at 30. Plain dark lock now; the veil animation comes later.
Hibernate after 3 h asleep is removed for now (back with the SSD install, see IDEAS.md).

**Done when:** locking, a wrong password, the right password, and the lid with Caps on and off all behave as decided.

## Step 7: Truth log
**Goal:** I can see what happened, in plain words.
**Made:** Super+T / `golem-truth`: apps opened and closed (with zone), every internet connection (which app, which site,
how long, data in and out), USB, admin use, wrong passwords, lock, Wi-Fi, networks joined, settings, updates. Kept 30 days.
Not yet: file changes inside sandboxes; a browser using its own encrypted DNS hides site names (IP shown instead).

**Done when:** I do ten things and all ten show up in the log in words I understand.

## Step 8: Control Panel (simple)
**Goal:** change zones and keys without touching files.
**Made:** the basic full-screen panel from DECISIONS.md (pages on the left, the page on the right, no effects) in the GREEN zone. Apply asks my password once. No text panel is made.

**Also:** app settings and keys moved to `/var/lib/golem`: I can read them, only the panel (after my password) changes them.
Pages: RUNNING, APPS, KEYS, NETWORK, SOUND & SCREEN, TRUTH LOG, ABOUT. Not yet: the red alert when it can't open
(a plain message for now), drivers, storage, startup list and the other PANEL.md items.

**Done when:** I change an app's zone and a key from the panel, and both work after Apply.

## Later step: Screen and clipboard separation
**Why:** today any app with a window can see other windows and key presses, whatever its zone.
**Made:** each zone's windows in their own nested screen, so they can't see each other; this also gives
the clipboard rules in DECISIONS.md (GREEN shares one, the others keep their own) and the screen rule (no app
sees the screen unless allowed).

## Step 9: Control Panel (game style) — built
**Made:** the same panel as a game menu: groups (SYSTEM, CONTROLS, LOOK, YOU, CODEX), drifting motes, pages that
melt and gather, Shadow/Negative turning inside out, find (F), and every page from PANEL.md that doesn't need
Wayland. Not yet: per-app site lists, distrusting certificates, clipboard and screen rules (these need the
Wayland step).

## Add-on: Text editor (built early, on the `text-editor` branch, at my request, 22 Nov 2026)
**Goal:** my editor: Notepad-style typing in Cool Retro Term's glass, files panel, running code, live preview,
the AI (Gemini now, my own later) and the gada animations.
**Made:** `editor.nix` and the `editor/` folder; Super+E. Its starting zone is GREEN with internet (for the AI),
sound and USB; after that the Control Panel decides. It joins main when I say so, after the laptop test of Steps 2 to 8.

**Done when:** on the laptop, Super+E opens it; I type, save (SAVED shows), find and replace, open the files panel
(Ctrl+B), run a Python file (F5), preview an HTML file (F6), and ask Gemini something (Ctrl+K) with my key;
Alt+G changes the animation level and weapon, and nothing feels slow on LOW; F9 shows a Python file as a flowchart, and F10's
blocks write a small program that F5 then runs.

### Next for the editor (planned, not built yet)
**Wires (node programming), like Unreal's Blueprints, Node-RED and LabVIEW.** A program as boxes ("nodes") joined
by wires. Each box does one thing (read a number, add, show text, repeat); its little sockets on the left take things in
and the ones on the right give results out; a wire carries a value (or, in Blueprints, the order of steps) from one box
to the next. A box runs once everything it needs has arrived along its wires. Plan: a wire canvas in a window beside the
editor (like the F10 blocks), Golem's colours, boxes for Python's basics plus "call a function from my code"; it writes
the code as you connect, and the wires picture is kept beside the file, like the blocks are.

**The whole program in one 3D picture (a "program map").** Known ideas: CodeCity (each file a district, each function a
tower, its height = how long it is), call graphs (a light beam from each function to the ones it calls), Gource (the
project's history grown as an animation). Plan: one key shows the open project as a dark 3D landscape in a window: files
as districts, functions as towers (taller = longer, brighter = changed recently, ember = has a mistake), beams for calls,
the gada hovering over the one you are in. Mouse or arrows to fly around; a click on a tower opens that function in the
editor. Python first (read like F9, never run); other languages through the AI. Drawn with WebGL in a bar-less golem-view
window, kept small so the Celeron's graphics can turn it smoothly; a flat 2D version for LOW.

**Done when:** on the laptop, I build a small program by wiring boxes and F5 runs it; and the program map of a project
with a few files shows its towers and beams, turns smoothly, and a click opens the right function.

---

## Step A: A screen you can see
No lock screen: Golem starts straight in. Boot messages are shown, not hidden. The start menu waits 3 seconds and
has a second line, **Golem (text only)**, which never starts the picture and shows what went wrong on the last start.
**Done when:** the laptop starts into something visible, and the text-only line gives a text login.

## Step B: The Start panel, made of sand
My own carved rune letters (readable English). Black and white. A game-like start screen: tabs on the left,
**CONTINUE, GADA, FATE, SUMMON, SLUMBER**, and a space on the right for an avatar or scenery (a picture I put in
`~/zones/settings/scenery.png`). Everything outside apps drifts; the cursor is a small light; Enter sends a pulse;
B turns the paper over. After a few minutes untouched, the tabs blow away and it becomes the idle screen.
**Done when:** the laptop starts into the Start panel and every tab does its job.

## Step C: Windows as sand
Opening, closing, maximising and minimising a window turn it to sand that flies (picture to picture).
A switch in MIMIC turns it off. **Done when:** it works and doesn't feel slow, or the switch turns it off.

## Step D: The Control Panel in runes
The panel in rune letters, pure black and white, page changes as flying sand, I flips it (yin-yang).
**Done when:** every page still works, and it looks like runes.

## Step E: The editor joins
The text editor add-on is merged; GADA opens it with its dashboard. **Done when:** GADA opens the editor.

## The road after the shadow realm (agreed 23 Nov 2026, in this order)
1. **(built)** **FILES inside the editor:** a full file explorer (Alt+E, or E on the dashboard): places, files with size, date
   and kind, a look inside, copy / cut / paste, rename, a Bin that gives things back, new folder, details (who can see
   it), hidden files. Pins (files or folders) go into groups on the dashboard. **Done when:** I manage a folder of
   my files only through FILES, and nothing surprises me.
2. **(built)** **Firefox out.** The live preview and the block builder get a tiny viewer that can only show pages from this
   computer. Word and Excel files open inside the editor (as a document, as a table). Links wait for the Gate.
3. **(built: the Gate, `golem-gate`, and golem-browser; a Control Panel page for its rules is next)** **The Gate:** the only way to the internet for the whole system. The first time an app or a site uses it, it asks
   me; everything goes into the truth log, ready for my AI to watch. Its own browser, in YELLOW, behind it.
4. **HIDDEN mode (Tor)** in the Gate, saying plainly what it hides and what it can't.
5. **Screen and clipboard separation** (the step below).
6. **Wires** in the editor: boxes that say what they do and how, my own notes on them, copy / paste / delete.
7. **The 3D map** of a program.
8. *(built)* **Small changes:** the password becomes **arise**; the Start panel gets ECHO (CONTINUE, GADA, ECHO, FATE, SUMMON, SLUMBER).
9. *(built)* **The optimiser:** compressed memory, a guard against freezes, the window I work in first, power by charger;
   nearly all of it kernel features, plus one tiny program that only wakes when I switch windows. And **reports**:
   `golem-report` pushes the self-test, errors, version, hardware and the truth log to my private repo
   `golem-reports` (after each update, and when I ask; `--screen` adds a picture). Claude reads only GitHub.
10. *(built)* **Clipboard history:** the last 10 things copied on my screen, in memory only; Super+V picks one.
11. **Echo:** my AIs, each its own person, in their own app (TALK, ECHOS, FEEDING, PERMISSIONS, ACTIONS, EXTENSIONS,
   AVATAR, MEMORY, COMPARE, RULES, CARRY, and a STOP key). Offline (llama.cpp, Llama 3.2: 1B on the Dell, 3B on the
   Asus), voice notes to text offline (whisper.cpp), Hinglish / Hindi / English. Each Echo has an avatar name and a
   description that analyses its personality and quirks from the chats I feed it. It only talks; extensions I add
   give it every other power, each with my permission.
   *Part 1 built:* the app, ECHOS, TALK, the STOP key (Super+Shift+E), `golem-echo-brain` to fetch the brain once
   through the Gate. *Part 2 built:* FEEDING (WhatsApp exports, voice notes heard offline), the description written
   from the chats (Ctrl+A in ECHOS), MEMORY, RULES, COMPARE.
   The brain runs on any processor for now; a faster one for the Asus comes when Golem moves there.
12. **golem-keylight:** colours per key where the keyboard allows (the Asus FX506LH, as an experiment), the Dell's
   backlight now; a command and file format Echo's extensions can use.
13. **Wires and the 3D map**, inside GADA (my graphical editor).
14. **The final image**, once everything passes on GitHub (and I say yes).
No disk encryption, no lock, no Wine, no reader (decided 23 Nov 2026). Later: a software manager through Echo's extensions.

## Test tools (22 Nov 2026, asked for by me)
- `golem-selftest`: every check a machine can do on the laptop, as ✓ or ✗.
- `golem-sand`: the sand test (drift, yin-yang, picture to picture). It tells whether this laptop can carry the
  sand look from IDEAS.md, and how many grains it can draw smoothly. The look itself is not built yet.

After Step 9 the next steps come from IDEAS.md, one at a time, picked by me.

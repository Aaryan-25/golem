# Plan

**NOW: Step 3** (built, waiting for my test on the laptop). Step 2 is waiting for its test too.

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
**Made:** my key list, tiling with no gaps, titles or borders (only a thin focus line), and a launcher.

**Done when:** I use the laptop for a day with only the keyboard and nothing annoys me. Anything that does goes back into this step.

## Step 6: Lock screen and lid
**Goal:** a simple lock with no username and no box. I just type my password.
**Made:** the lock screen (plain first, then the veil animation), and the lid rule: Caps Lock ON means no lock on wake.

**Done when:** locking, a wrong password, the right password, and the lid with Caps on and off all behave as decided.

## Step 7: Truth log
**Goal:** I can see what happened, in plain words.
**Made:** a log of apps opened and closed (with zone), internet connections, USB, admin use and wrong passwords. Kept 30 days.

**Done when:** I do ten things and all ten show up in the log in words I understand.

## Step 8: Control Panel (simple)
**Goal:** change zones and keys without touching files.
**Made:** the basic full-screen panel from DECISIONS.md (pages on the left, the page on the right, no effects) in the GREEN zone. Apply asks my password once. No text panel is made.

**Done when:** I change an app's zone and a key from the panel, and both work after Apply.

## Step 9: Control Panel (game style)
**Goal:** the same panel becomes the game menu (no second panel).
**Made:** decided at the time, in small pieces, from IDEAS.md.

---

After Step 9 the next steps come from IDEAS.md, one at a time, picked by me.

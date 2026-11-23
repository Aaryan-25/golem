# Tests to do on the laptop

Write ✅ or ❌ next to each line, or just tell Claude what happened. A phone photo of anything odd helps.

## Before testing
Turn Wi-Fi on (Super+N, then Super+W), open a terminal (Alt+Enter), run `golem-update`, press `y`, then `reboot`.
At the Dell logo press F12 and choose **Golem** (or move Golem to the top of the Boot Sequence in F2).
From now on Golem starts into a dark lock screen: type your password and press Enter.

**First, the machine checks:** connect Wi-Fi, open a terminal (Alt+Enter) and type `golem-selftest`.
It checks everything a machine can check by itself and prints ✓ or ✗ for each. Send Claude a photo, or the file
`~/golem-selftest.txt`. The lines below are the things only your eyes and hands can check.

Already proven automatically on GitHub (in a virtual laptop): the lock screen and passwords, the keys and launcher,
all four zones, the truth log (including an internet connection named by app), and the Control Panel changing a
zone and a key with the password. What only the real laptop can prove: Wi-Fi, sound, brightness, the lid, battery,
USB, how fast it feels, and whether it all feels right to you.

## Step 2: updates
- [ ] `golem-update` showed what changed and asked before doing anything
- [ ] After it finished, `cat ~/golem-updates.txt` lists the update

## Step 3: truthful base
- [ ] Start-up is silent: no menu, no scrolling text, straight to `golem login:`
- [ ] Holding **Shift** while it starts shows a menu that says **Golem**
- [ ] After a restart Wi-Fi is **off** (Super+W shows no networks, or says Wi-Fi is disabled)
- [ ] **Super+N** turns Wi-Fi on, and Super+W can then join a network
- [ ] In a terminal, `golem-wifi` says whether Wi-Fi is now ON or OFF
- [ ] `timedatectl` shows "NTP service: inactive" (no clock over the internet)

Hardware (left over from step 0). Some may not work yet, and that's fine:
- [ ] Sound: `speaker-test -t wav -c 2 -l 1` says "front left, front right" (if not: tell Claude, it's probably a missing firmware file)
- [ ] Volume keys
- [ ] Brightness keys
- [ ] Closing the lid makes it sleep, and opening it wakes it
- [ ] Battery: `cat /sys/class/power_supply/BAT*/capacity` shows a percentage
- [ ] A USB stick: plug it in, then `lsblk` shows it as a new disk

## Step 4: zones
Turn Wi-Fi on first (Super+N). In a normal terminal, `golem-net-test` should say ONLINE.
Then run each line below. A new terminal window opens inside the zone. Type the commands
in **that new window**, then close it with Alt+Q.

**RED:** `zone red xterm`  (known gap: windows in any zone can still see other windows; that comes later)
- [ ] `ls ~` shows nothing (none of your folders)
- [ ] `golem-net-test` says OFFLINE (turn Wi-Fi on first, so this really tests the zone)
- [ ] `touch ~/x`, close the window, open RED again, and `ls ~` is empty again (wiped on close)

**OFFLINE:** `zone offline xterm`
- [ ] `ls ~` is empty, then `touch ~/hello`, close, and `ls ~/zones/xterm` (in a normal terminal) shows `hello`
- [ ] `golem-net-test` says OFFLINE

**YELLOW:** `zone yellow xterm` (turn Wi-Fi on first)
- [ ] `golem-net-test` says ONLINE, and `ls ~` shows nothing of your folders

**GREEN:** `zone green xterm`
- [ ] `ls ~` shows your folders: documents, projects, media, zones
- [ ] `golem-net-test` says OFFLINE (GREEN gets internet only if allowed)

**Settings:**
- [ ] Open xterm with Alt+Space, choose a zone when asked; `zone show xterm` says that zone

## Step 5: keys and windows
- [ ] **Super+H** shows the key list
- [ ] **Alt+Space** opens the launcher at the bottom left; typing "xtrem" (with a typo) still finds xterm
- [ ] An app opened for the first time asks for its zone once, and not the second time
- [ ] New windows open beside the old one without taking focus; **Alt+Tab** shows a list of names to switch to
- [ ] **Super+arrows** move the focus, the focused window has a thin pale line, there are no bars or titles
- [ ] **Alt+Q** asks "CLOSE …?" before closing
- [ ] **Super+Shift+2** on a terminal sends it to workspace 2, and next time it opens there by itself
- [ ] **Super+Escape** shows the power menu
- [ ] Volume, mute and brightness keys work

## Step 6: lock screen and lid
- [ ] Golem starts into a dark screen with no name and no box; typing the password and Enter unlocks it
- [ ] A wrong password keeps it locked
- [ ] **Super+L** locks
- [ ] Closing the lid (Caps Lock OFF) sleeps; opening it shows the lock
- [ ] Closing the lid with Caps Lock ON: on opening, no lock
- [ ] Left alone, the screen dims at 4 minutes and locks at 5 (not while Caps Lock is ON)

## Step 7: truth log
Do these, then press **Super+T** and check each shows up in words you understand:
- [ ] In `zone yellow xterm`, run `golem-net-test`: "xterm (YELLOW) talked to 1.1.1.1 …"
- [ ] `zone red xterm`, then close it: "Opened xterm in RED …" and "Closed xterm (RED)"
- [ ] A wrong password at the lock screen: "Wrong password at the lock screen"
- [ ] Super+L, then unlock: "Screen locked", "Screen unlocked"
- [ ] Plug in and pull out a USB stick: "USB plugged in: …", "USB unplugged: …"
- [ ] `sudo ls`: "Admin rights used for: …"
- [ ] Super+N twice: "Wi-Fi turned OFF/ON"
- [ ] Join a network: "Connected to the network '…'"
- [ ] Change an app's zone in the Control Panel: "Settings: <app>: zone …"
- [ ] Send a window to workspace 2: "WINDOW … now opens on workspace 2"

## Step 8: Control Panel
- [ ] **Super+Z** opens it full screen: dark realm, drifting motes, groups at the top (Q / E switch)
- [ ] Opening a page: the old page melts, the new one gathers in
- [ ] **I** (or Super+I anywhere): the screen turns inside out to Negative (ink on white), and back
- [ ] WEAVE > APPS: change an app's zone; "changes waiting"; **A** asks the password once; Super+T shows it
- [ ] A wrong password applies nothing, and the truth log says so
- [ ] KEYS: change a key (Enter, then press the new keys), apply, and the new key works
- [ ] DRIVERS: camera OFF, apply; the camera can't be used (and ON again)
- [ ] NETWORK: Wi-Fi and Bluetooth on/off; "Set the clock from the internet, once" fixes the clock
- [ ] SOUND & SCREEN: volume, brightness, night light change at once
- [ ] POWER: change "Lock after", apply; it locks after the new time
- [ ] STARTUP lists what runs; SAVE SLOTS lists versions; STORAGE shows space
- [ ] YOU > PRIVACY: trackers ON (a known ad site doesn't load); BACKUPS: save one, load it
- [ ] MIMIC > RED ALERT: "Show a test alert": red screen, gone after pressing Space 3 times
- [ ] **F** finds things (try "battery")
- [ ] In a terminal, `touch /var/lib/golem/apps/test.conf` is refused (only the panel can change settings)

## The sand test (for Golem's look, not a step yet)
Open a terminal (Alt+Enter) and type `golem-sand`. A moon made of sand fills the screen and drifts.
Space: the sand flies into the next picture. B: the paper turns over. D: drift on/off. T: FLY or FLOW travel.
`+` / `-`: more or fewer grains. Esc: quit. Your own picture: `golem-sand ~/media/mypicture.png`.
- [ ] It opened and drew sand
- [ ] The number it printed when it closed (frames a second, and how many grains): ______
- [ ] Does the drift feel like the shadow realm? What's missing? ______

## The shadow realm (Steps A to E, 22 Nov 2026)
Get it: on the text screen or a terminal, `golem-update`, answer `y`, then `sudo reboot`.
- [ ] The start menu shows for 3 seconds, with **Golem - text only** as a second line
- [ ] Start messages scroll by (not a black screen), then the sand gathers into the **Start panel**
- [ ] ↑↓ or the mouse moves the carved mark; the cursor is a small light; Enter sends a ring
- [ ] **CONTINUE** (or Esc): the sand flies off and the desktop is there. **Super+Escape** brings it back
- [ ] **GADA** opens the editor (its dashboard first) · **FATE** the Control Panel · **SUMMON** the app finder
- [ ] **SLUMBER** shows SLEEP, RESTART, SHUT DOWN, BACK
- [ ] **B** turns everything over: ink on white paper. B again: back to black
- [ ] Leave it untouched for 5 minutes: it dims, then the tabs blow away. A key brings them back
- [ ] A window (Alt+Enter): it gathers out of sand. **Alt+F** flies it to full size and back. **Super+M** blows it
      down to the bottom; **Super+Shift+M** brings it back. **Alt+Q** (yes): it blows away
- [ ] The Control Panel (FATE or Super+Z): runes, black and white, tabs SPELL WEAVE MIMIC MEMORIES TRUE NAME;
      changing page turns the page to sand. MIMIC > WINDOWS turns the window sand off
- [ ] Choose **Golem - text only** once: a text screen that shows what went wrong last time
- [ ] Put a picture at `~/zones/settings/scenery.png` and open the Start panel: it's on the right, made of sand

## The final version (23 Nov 2026)
Password is now **arise**. First, once: `golem-report setup` (see README), then every report goes to GitHub by itself.
- [ ] The Start panel: CONTINUE, GADA, **ECHO**, FATE, SUMMON, SLUMBER
- [ ] **Super+V**: the last things I copied; pick one and paste it. **Super+Shift+V** forgets them
- [ ] It feels fast enough; nothing froze when memory was full (the truth log says if something was closed)
- [ ] `golem-report --screen`: the report and a picture of the screen appear in my golem-reports repo
- [ ] **Echo:** in a terminal `golem-echo-brain` (say yes to the Gate twice). Then ECHO in the Start panel:
      in ECHOS type a name and Enter; in TALK talk to it (Esc stops a reply). Replies come within a few seconds
- [ ] FEEDING: put a WhatsApp export (.zip) in `~/zones/golem-echo/feed`, pick the chat, pick the person;
      then ECHOS, Ctrl+A writes its description. Talk again: does it sound more like them?
- [ ] Voice notes in the export became text (FEEDING says "listening to voice note...")
- [ ] MEMORY, RULES and AVATAR: write something, Ctrl+S, and the Echo follows it
- [ ] COMPARE: two Echos answer the same question
- [ ] `golem-keylight extension`, then ask an Echo to light the keyboard red: I am asked first (only this time /
      always / never), the light changes, and ACTIONS shows it. **Super+Shift+E** stops everything
- [ ] `golem-keylight what` on the Dell (white light) and on the Asus (colour?); `golem-keylight all orange`
- [ ] GADA: open a .py file, **F11** wires: two numbers into ADD into SHOW; F5 runs it
- [ ] GADA: **F12** the program map turns smoothly; a click on a tower opens that function

# Tests to do on the laptop

Write ✅ or ❌ next to each line, or just tell Claude what happened. A phone photo of anything odd helps.

## Before testing
Turn Wi-Fi on (Super+W), open a terminal (Alt+Enter), run `golem-update`, press `y`, then `reboot`.
At the Dell logo press F12 and choose **Golem** (or move Golem to the top of the Boot Sequence in F2).

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
- [ ] Sound: `speaker-test -t wav -c 2 -l 1` says "front left, front right"
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

**YELLOW:** open Firefox with Alt+Space and choose YELLOW when it asks (turn Wi-Fi on first)
- [ ] Firefox opens websites
- [ ] Firefox's download folder is inside `~/zones/firefox` and it can't open your `documents`

**GREEN:** `zone green xterm`
- [ ] `ls ~` shows your folders: documents, projects, media, zones
- [ ] `golem-net-test` says OFFLINE (GREEN gets internet only if allowed)

**Settings:**
- [ ] `zone show firefox` says YELLOW, internet allowed
- [ ] `zone red firefox` opens Firefox with no internet and no access to your files

## Step 5: keys and windows
- [ ] **Super+H** shows the key list
- [ ] **Alt+Space** opens the launcher at the bottom left; typing "firfox" (with a typo) still finds Firefox
- [ ] An app opened for the first time asks for its zone once, and not the second time
- [ ] New windows open beside the old one without taking focus; **Alt+Tab** shows a list of names to switch to
- [ ] **Super+arrows** move the focus, the focused window has a thin pale line, there are no bars or titles
- [ ] **Alt+Q** asks "CLOSE …?" before closing
- [ ] **Super+Shift+2** on Firefox sends it to workspace 2, and next time Firefox opens there by itself
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
- [ ] Open Firefox (YELLOW) and visit a website: "firefox (YELLOW) talked to <site>: … out, … in"
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
- [ ] **Super+Z** opens it full screen, dark, pages on the left
- [ ] RUNNING lists open apps with their zone and memory; Enter closes one after asking
- [ ] APPS: change Firefox's zone; the bottom line says changes are waiting; **A** asks the password once
- [ ] After applying, Firefox opens in the new zone, and Super+T shows "Settings: firefox: …"
- [ ] A wrong password applies nothing, and the truth log says so
- [ ] KEYS: change a key (Enter, then press the new keys), apply, and the new key works
- [ ] **X** throws waiting changes away; Esc with changes waiting asks first
- [ ] NETWORK turns Wi-Fi on/off; SOUND & SCREEN changes volume and brightness at once
- [ ] In a terminal, `touch /var/lib/golem/apps/test.conf` is refused (only the panel can change settings)

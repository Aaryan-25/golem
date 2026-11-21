# Ideas (waiting room)

Nothing here gets built until I move it into PLAN.md. New ideas from any chat get added here.

## System
- Install to the SSD and wipe Windows
- Hibernate after 3 h asleep on battery (needs 4 GB of swap: comes with the SSD install)
- Disk encryption (one password at boot)
- BLUE zone for my own offline AI
- Clipboard manager with real separation between zones
- The Fetcher (`golem-fetch <link>`): download inside YELLOW, find out what the file really is, and open it in a safe zone
- Network privacy switch (VPN or Tor) and a connection watcher
- Red alert triggers, press count and sound

## Apps
- Text editor
- File manager
- Browser with internet control and no ads or popups
- Cool Retro Term

## Look and feel (the shadow realm)
- The veil: motes of light that gather into a sigil (the lock screen, and later the wallpaper)
- Living, clickable wallpaper that pauses when covered
- Shadow and Negative looks
- A round menu that blooms from the bottom-left corner while Super is held
- Gate lock screen from my night-palace wallpaper
- The mace that travels across the UI
- The shade (my AI's body) with animations for each state
- Windows that gather and melt, and focus shown by light and shadow
- Rituals, the Spell voice, the true side, ancestors (older versions), fog of the unexplored, earned techniques
- Lock screen extras: unlock by a hidden mechanism or by the AI, live space footage, welcome message, boot animation

## Later
- Phone as a viewer, reachable from anywhere through an encrypted tunnel I control: see the truth log, status and alerts. See only at first. Not before the laptop side is done.
- An animated avatar of my PC: shows when the camera or mic is in use, and in the idle scene (like games' idle screens).
- Keyboard light scripts: designs, flashes, colours tied to modes and keybinds (limited by the keyboard being one zone).
- Clipboard: a short history (last 10, memory only, cleared on lock).

## Control Panel contents
- Truth log captures all internet traffic: which app, where to, when, and how much data
- Drivers panel

## Control Panel as a game menu (the nicer UI, later)
- Five groups (SYSTEM, CONTROLS, LOOK, YOU, CODEX) with Q / E, and F to find anything
- A full-screen pause menu over the drifting veil
- Page transitions, sigil, zone icons, soft sounds (with on/off)
- LOOK page: face, colours, realm palettes, veil, wallpaper, lock, effects, fonts, focus line, reset
- Quick actions, volume/display/performance managers
- Save slots, loadouts, codex, character sheet, stats, quests, search
- Idle scene using my AI's elements (maybe on the lock screen too), after the AI exists
- Working code for most of this is in Aaryan-25/shilp, branch `graphical-panel` (pull request #6), as reference
- Technical notes from building it there: the panel's GREEN sandbox blocks the system bus, so Wi-Fi, power and the system service list need a small fixed-list helper outside it; admin actions need a small root helper that checks the password and accepts only a fixed list; the truth log alone can't say which app made a connection

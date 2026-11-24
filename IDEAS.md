# Ideas (waiting room)

Nothing here gets built until I move it into PLAN.md. New ideas from any chat get added here.

## System
- Install to the SSD and wipe Windows
- Hibernate after 3 h asleep on battery (needs 4 GB of swap: comes with the SSD install)
- The download checker: an Echo extension (and golem-browser says what each download really is); was: the Fetcher, download inside YELLOW, find out what the file really is, and open it in a safe zone
- Red alert triggers, press count and sound

## Apps

## Look and feel (the shadow realm)
- The veil: motes of light that gather into a sigil (the lock screen, and later the wallpaper)
- Living, clickable wallpaper that pauses when covered
- Shadow and Negative looks
- The mace that travels across the UI
- The shade (my AI's body) with animations for each state
- Windows that gather and melt, and focus shown by light and shadow
- Rituals, the Spell voice, the true side, ancestors (older versions), fog of the unexplored, earned techniques
- Idle screen extras: live space footage, welcome message, boot animation (no lock: decided 23 Nov 2026)

## Later
- A software manager (Windows programs too), run by Echo's extensions and the editor
- For the animations chat (see ANIMATIONS.md): the gada travelling across the screen, a living wallpaper, an avatar of my PC that shows when the camera or mic is in use
- The phone viewer, after the laptop boots Golem
- Phone as a viewer, reachable from anywhere through an encrypted tunnel I control: see the truth log, status and alerts. See only at first. Not before the laptop side is done.
- An animated avatar of my PC: shows when the camera or mic is in use, and in the idle scene (like games' idle screens).
- Keyboard light scripts: designs, flashes, colours tied to modes and keybinds (limited by the keyboard being one zone).

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

## The sand look (decided with me, 22 Nov 2026, after testing gather.be-of-dao.com)
- Golem's look is made of sand, like Gather: every picture is thousands of grains.
- Drift = the shadow realm. One side of a picture holds still and breathes; past a wavy line, grains let go, blow away, and come home again.
- Yin-yang = light and shadow. Flip between light on black and ink on white; each grain turns into its opposite, with a short dip to nothing in between.
- Picture to picture = almost every transition. Each grain flies from its place in the old picture to its place in the new one (kick out, drift back in).
- Used for: waking up, start screen, lock screen, wallpaper, and panel page changes. Details to decide together.
- The 3D "depth brain" is not needed for any of this.

## Echo, growing up (24 Nov 2026; after Golem is tested on the Asus)
- **Many brains:** each Echo picks its own brain in ECHOS from free offline models (Llama, Qwen, Gemma, Mistral…).
  Sizes the laptops can carry: the Dell up to about 3B; the Asus up to about 7-8B (smarter, slower). The trainer
  fetches the matching training copy for whichever brain an Echo uses.
- **More kinds of food:** besides chats, notes, documents and PDFs, essays, and question-and-answer lists.
- **More ways to train,** chosen in FEEDING:
  - voice layer, stronger or lighter (learns more, or trains faster)
  - taste: I mark the better of two answers, and it learns what I like
  - facts: learns from my documents
  (Retraining a whole brain from scratch is beyond a 4 GB graphics card; small add-on layers are the realistic kind.)
- Echo on the Dell thinking with the Asus's bigger brain and graphics card, when the Asus is online (also in PLAN.md).

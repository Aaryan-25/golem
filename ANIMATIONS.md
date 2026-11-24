# Animations in Golem: a guide for whoever works on them

This is for a new chat (or a person) who wants to make Golem's animations: the waking-up, the idle screen,
the wallpaper, transitions, the avatar's emotes. Read it, then [CLAUDE.md](CLAUDE.md), [PLAN.md](PLAN.md) and
[DECISIONS.md](DECISIONS.md). The owner can't read code: talk to him in plain words, ask before long work.

## The look, as decided (DECISIONS.md, 22–23 Nov 2026)
- **The shadow realm:** black ground, everything else white. The **yin-yang flip** turns it over: ink on white
  paper (Super+I, or B in the Start panel). No other colours for now.
- **Everything outside apps is sand.** Inspired by gather.be-of-dao.com:
  - **drift:** past a wavering line, grains let go, blow away and come home;
  - **picture to picture:** every grain flies from its place in the old picture to its place in the new one, thrown
    out a little, then drawn in;
  - **the light:** the cursor is a lamp in the sand; Enter sends a ring.
- **Letters:** Golem Runes, Cambria's shapes (via its free twin Caladea) carved as ancient broken stone (`realm/runes.py`).
- **Waking up:** an animation of something waking, inspired by Nine Sols and Shadow Slave. To be designed with the owner.
- **No lock screen.** The idle screen = the Start panel with its tabs blown away.

## Where things live
| File | What it is |
|---|---|
| `realm/realm.py` | **The sand engine.** One program for the whole session (OpenGL 3.3 through moderngl + glfw). Draws the Start panel, the idle screen, windows turning to sand, the Control Panel's page turns. |
| `realm/realm.nix` | Builds the font and the `golem-realm` command; starts it with the desktop. |
| `realm/runes.py` | Makes the Golem Runes font at build time. |
| `realm/sand.py` / `realm/sand.nix` | `golem-sand`, the stand-alone sand test (drift, flip, picture to picture, a smoothness number). A good playground. |
| `panel/panel.py` | The Control Panel (Tk). Its page turns ask the realm for sand (`sand_turn`). |
| `settings/settings.nix` | The colours of the two faces (`theme`, `themeNegative`). |
| `~/zones/settings/scenery.png` | The owner's picture on the right of the Start panel (a moon until he puts one). |

## How the realm works (realm/realm.py)
- **Grains** live in one buffer. Each grain has `a_from` (x, y, brightness), `a_to` (x, y, brightness) and `a_more`
  (seed, layer). x and y go from 0 to 1 across the screen, y downwards.
- **Layers** (`a_more.y`): 0 = the Start panel's words, 1 = the scenery, 2 = a window or page, 3 = dust in the air.
- **A picture becomes grains** with `homes(image, n, rng)`: brighter places get more grains, sorted along a curve
  that fills the screen so two pictures' grains pair up with near neighbours (that's what makes "picture to
  picture" look like flowing, not chaos). Pictures are drawn at half the screen's size.
- **Moving from one picture to another:** `load(from, to, seconds, slow)`; the shader eases each grain from
  `a_from` to `a_to` as `fly` goes 0 → 1, each grain leaving at its own moment.
- **The shader's knobs (uniforms):** `t_now`, `fly`, `slow` (how far grains are thrown), `ink` (paper turned over),
  `fade` (dips to nothing during the flip), `erase` (the idle screen blowing the words away), `size`, `aspect`,
  `lamp`, `lamp_on`, `pulse`, `line_at` / `line_out` (the drift line and the wind's direction).
- **What it's told to do** (a small socket, `$XDG_RUNTIME_DIR/golem-realm.sock`):
  `golem-realm show | idle | hide`, `golem-realm win close|min|full|moved X Y W H`, `golem-realm page A.png B.png`.
- **Its window** floats above everything (not arranged by i3) and takes the keyboard only while the Start panel is up.

## Adding an animation, the Golem way
1. A new scene is a picture (or a few) turned into grains, plus how they move: start in `realm/sand.py` or a copy of it
   to try ideas fast, then move the result into `realm/realm.py` as a new mode next to `show` / `idle`.
2. New behaviour goes in the shader as a new layer number or a new uniform, so the old scenes stay as they are.
3. Keep it light: the Dell (Celeron N3350, Intel HD 500, 4 GB) draws about 30,000 grains smoothly. Aim for ~40,000
   at most on screen at once; the Asus (FX506LH) can do far more.
4. Black and white only; whatever you draw must also look right on white paper (`ink = 1`).
5. Every change gets a test in `tests/tests.nix` (the virtual laptop on GitHub runs it) and a plain-words commit.
6. Settings that switch animations on or off belong to MIMIC (`settings/settings-schema.json`, pages ANIMATIONS / WINDOWS /
   TRANSITIONS / WAKING UP / WALLPAPER / START SCREEN), and the owner chooses their names.

## Waiting to be designed with the owner
- **Waking up** (MIMIC > WAKING UP): today the sand just gathers into the Start panel.
- **The wallpaper** (MIMIC > WALLPAPER): plain black today; animations or videos later.
- **Transitions** (MIMIC > TRANSITIONS): only picture to picture today.
- **Echo's avatar emotes:** each draft of the owner's AI has an avatar with emotes for its actions (idle, thinking,
  speaking, working, refusing...). They will be pictures or sand scenes the realm can play; see PLAN.md (Echo).

## Trying it without the laptop
On any Linux with a virtual screen: `Xvfb :7 -screen 0 1366x768x24 +extension GLX &`, then
`DISPLAY=:7 XDG_RUNTIME_DIR=/tmp GOLEM_RUNES=/path/GolemRunes.ttf python3 realm/realm.py --daemon` and take pictures
with `import -window root shot.png`. Make the font with `python3 realm/runes.py Caladea-Bold.ttf GolemRunes.ttf`.

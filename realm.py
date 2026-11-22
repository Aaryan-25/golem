"""golem-realm: the shadow realm. Everything outside apps is drawn here as sand, by the graphics chip.

One program stays running for the whole session, so it answers at once:
  golem-realm --daemon      start it (i3 does this at login; it wakes up into the Start panel)
  golem-realm show          the Start panel (Super+Escape)
  golem-realm idle          the idle screen: the tabs blow away; any touch brings them back
  golem-realm hide          back to the desktop
  golem-realm win close|min|full X Y W H    a window turns to sand (golem-win asks, then acts once "ready")
  golem-realm win moved X Y W H             where that window is now (after full)
  golem-realm page A.png B.png              the Control Panel's page change: picture A flies into picture B

Start panel keys: Up/Down (or the mouse) choose, Enter (or a click) does it, Esc goes back to the desktop,
B turns the paper over (the yin-yang: the same as Super+I). The cursor is a small light in the sand.
"""
import os, queue, socket, subprocess, sys, threading, time
import numpy as np

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "golem-realm.sock")
SETTINGS = "/var/lib/golem/settings.conf"
SCENERY = os.path.expanduser("~/zones/settings/scenery.png")
FONT = os.environ.get("GOLEM_RUNES", "GolemRunes.ttf")

TABS = [("CONTINUE", "continue"), ("GADA", "golem-launch golem-edit"), ("FATE", "golem-panel-start"),
        ("SUMMON", "golem-launch"), ("SLUMBER", "slumber")]
SLUMBER = [("SLEEP", "systemctl suspend"), ("RESTART", "systemctl reboot"), ("SHUT DOWN", "systemctl poweroff"),
           ("BACK", "back")]

VERT = """
#version 330
in vec3 a_from; in vec3 a_to; in vec2 a_more;           // a_more: seed, layer (0 = tabs, 1 = scenery, 2 = a window)
uniform float t_now, fly, slow, ink, fade, erase, size, aspect;
uniform vec2 lamp; uniform float lamp_on, pulse;
uniform vec2 line_at, line_out;
out float v_amt; out float v_lit;
float rnd(float k) { return fract(sin(a_more.x * 91.7 + k * 47.3) * 43758.55); }
float ease(float x) { return x * x * (3.0 - 2.0 * x); }
void main() {
    // picture to picture: each grain leaves at its own moment, is thrown out a little, then drawn home
    float wait = rnd(1.0) * 0.35;
    float e = ease(clamp((fly - wait) / (1.0 - wait), 0.0, 1.0));
    vec2 p = mix(a_from.xy, a_to.xy, e);
    float bright = mix(a_from.z, a_to.z, e);
    vec2 out_dir = normalize(a_from.xy - vec2(0.5) + vec2(rnd(2.0) - 0.5, rnd(3.0) - 0.5) * 0.4 + 1e-4);
    p += out_dir * sin(3.14159 * e) * (0.02 + 0.10 * rnd(4.0)) * slow;

    p = vec2(0.5) + (p - vec2(0.5)) * (1.0 + 0.004 * sin(t_now * 0.7));        // breathing

    // drift: past a wavering line the sand lets go, blows away and comes home; the tabs only shed a little
    vec2 q = vec2(p.x * aspect, p.y);
    float along = dot(q - line_at, vec2(-line_out.y, line_out.x));
    float waver = 0.08 * sin(along * 5.0 + t_now * 0.15) + 0.04 * sin(along * 13.0 - t_now * 0.1) + (rnd(5.0) - 0.5) * 0.25;
    float away = a_more.y > 1.5 ? 0.0 : a_more.y > 0.5 ? smoothstep(0.0, 0.6, dot(q - line_at, line_out) + waver) : 0.12 * step(0.9, rnd(10.0));
    float alive = 1.0;
    if (away > 0.0) {
        float life = 4.0 + 5.0 * rnd(6.0);
        float ph = fract(t_now / life + rnd(7.0));
        float stay = mix(0.9, 0.1, away);
        float gone = max(0.0, (ph - stay) / (1.0 - stay));
        vec2 swirl = vec2(sin(p.y * 9.0 + t_now + a_more.x), cos(p.x * 7.0 - t_now * 0.8 + a_more.x));
        p += (vec2(line_out.x / aspect, line_out.y) + 0.3 * swirl * vec2(1.0 / aspect, 1.0)) * 0.9 * away * gone * sqrt(gone) * (0.5 + rnd(8.0));
        alive = smoothstep(0.0, 0.06, ph) * (1.0 - smoothstep(0.35, 1.0, gone));
    }
    // idle: the tabs blow away, each grain at its own moment, and come back the same way
    if (a_more.y < 0.5 && erase > 0.0) {
        float g = clamp(erase * 1.6 - rnd(11.0) * 0.6, 0.0, 1.0);
        p += vec2(0.35 / aspect, -0.12 + 0.24 * rnd(12.0)) * g * g;
        alive *= 1.0 - g;
    }
    // the light: grains near it glow (or, on paper, the ink near it lifts); a pulse rings out from it
    vec2 d = vec2((p.x - lamp.x) * aspect, p.y - lamp.y);
    float r = length(d);
    float lit = lamp_on * exp(-r * r / 0.004) * 1.6;
    if (pulse < 1.0) {
        float ring = exp(-pow((r - pulse * 0.45) / 0.03, 2.0)) * (1.0 - pulse);
        lit += ring * 2.0;
        p += normalize(d + 1e-5) * vec2(1.0 / aspect, 1.0) * ring * 0.012;
    }
    v_lit = lit;
    v_amt = bright * alive * fade;
    gl_Position = vec4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    gl_PointSize = size * (0.7 + 0.8 * rnd(9.0)) * (1.0 + 0.6 * min(lit, 1.0));
}
"""
FRAG = """
#version 330
in float v_amt; in float v_lit; uniform float ink; out vec4 color;
void main() {
    float r = length(gl_PointCoord * 2.0 - 1.0);
    float a = v_amt * smoothstep(1.0, 0.2, r);
    // light on black: each grain adds light. Ink on paper: each grain takes light away, and the light lifts the ink
    color = ink > 0.5 ? vec4(vec3(a * 0.6 / (1.0 + 3.0 * v_lit)), 1.0)
                      : vec4(vec3(0.95, 0.94, 0.91) * a * (0.6 + 0.9 * v_lit), 1.0);
}
"""

QUAD_V = """
#version 330
in vec2 p; out vec2 uv;
void main() { uv = vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5); gl_Position = vec4(p, 0.0, 1.0); }
"""
QUAD_F = """
#version 330
in vec2 uv; uniform sampler2D tex; out vec4 c;
void main() { c = vec4(texture(tex, uv).rgb, 1.0); }
"""


# ---------- pictures ----------
def hilbert(x, y, n):
    d = np.zeros_like(x)
    s = n // 2
    while s > 0:
        rx = (x & s) > 0
        ry = (y & s) > 0
        d += s * s * ((3 * rx) ^ ry)
        flip = ~ry
        x, y = np.where(flip & rx, s - 1 - x, x), np.where(flip & rx, s - 1 - y, y)
        x, y = np.where(flip, y, x), np.where(flip, x, y)
        s //= 2
    return d


def homes(img, n, rng):
    """n grains for a picture (0..1 brightness, as big as the screen / 2): brighter places get more grains.
    Sorted along a curve that fills the screen, so two pictures' grains pair up with near neighbours."""
    h, w = img.shape
    wt = img.ravel() ** 1.2
    if wt.sum() <= 0:
        return np.zeros((n, 3), "f4")
    pick = rng.choice(img.size, size=n, p=wt / wt.sum())
    py, px = np.divmod(pick, w)
    big = 1 << int(np.ceil(np.log2(max(w, h))))
    order = np.argsort(hilbert(px.astype(np.int64), py.astype(np.int64), big))
    pick, px, py = pick[order], px[order], py[order]
    return np.stack([(px + rng.random(n)) / w, (py + rng.random(n)) / h, img.ravel()[pick]], 1).astype("f4")


class Pictures:
    def __init__(self, w, h):
        from PIL import ImageFont
        self.w, self.h = w // 2, h // 2
        self.font = ImageFont.truetype(FONT, max(12, int(self.h * 0.065)))

    def tabs(self, items, sel):
        """One picture per word, and one for the carved mark beside the chosen tab.
        Each word keeps its own share of grains, so moving the choice only brightens and dims words in place,
        and the mark flies from one tab to the next."""
        from PIL import Image, ImageDraw
        x, y0, step = int(self.w * 0.09), int(self.h * 0.30), int(self.h * 0.11)
        out = []
        for i, (name, _) in enumerate(items):
            im = Image.new("L", (self.w, self.h), 0)
            ImageDraw.Draw(im).text((x, y0 + i * step), name, font=self.font, fill=255)
            out.append((np.asarray(im, "f4") / 255.0, 1.0 if i == sel else 0.42))
        im = Image.new("L", (self.w, self.h), 0)
        c, r = y0 + sel * step + self.font.size * 0.42, self.font.size * 0.22
        m = x - self.font.size * 0.7
        ImageDraw.Draw(im).polygon([(m, c - r), (m + r, c), (m, c + r), (m - r, c)], fill=255)
        out.append((np.asarray(im, "f4") / 255.0, 1.0))
        return out

    def tab_box(self, items, i):
        y0, step = 0.30 + i * 0.11, 0.11
        return 0.04, y0 - 0.02, 0.5, y0 + step - 0.02

    def scenery(self):
        """My picture from ~/zones/settings/scenery.png, or a moon until I choose one."""
        from PIL import Image
        box_w, box_h = int(self.w * 0.42), int(self.h * 0.8)
        a = np.zeros((self.h, self.w), "f4")
        try:
            im = Image.open(SCENERY).convert("L")
            im.thumbnail((box_w, box_h))
            pic = np.asarray(im, "f4") / 255.0
        except OSError:
            s = min(box_w, box_h)
            y, x = np.mgrid[-1:1:s * 1j, -1:1:s * 1j]
            r = np.hypot(x, y) / 0.8
            z = np.sqrt(np.clip(1 - r * r, 0, 1))
            pic = np.where(r < 1, 0.05 + 0.95 * np.clip(-0.5 * x + 0.4 * y + 0.7 * z, 0, 1) ** 0.8, 0.0).astype("f4")
        ph, pw = pic.shape
        top, left = (self.h - ph) // 2, int(self.w * 0.53) + (box_w - pw) // 2
        a[top:top + ph, left:left + pw] = pic
        return a


# ---------- the realm ----------
class Realm:
    def __init__(self):
        import glfw, moderngl
        self.glfw, self.mgl = glfw, moderngl
        if not glfw.init():
            raise SystemExit("golem-realm: no screen")
        for k, v in ((glfw.CONTEXT_VERSION_MAJOR, 3), (glfw.CONTEXT_VERSION_MINOR, 3),
                     (glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE), (glfw.DECORATED, False), (glfw.VISIBLE, False)):
            glfw.window_hint(k, v)
        glfw.window_hint_string(glfw.X11_CLASS_NAME, "golem-realm")
        glfw.window_hint_string(glfw.X11_INSTANCE_NAME, "golem-realm")
        mode = glfw.get_video_mode(glfw.get_primary_monitor())
        self.W, self.H = mode.size.width, mode.size.height
        self.win = glfw.create_window(self.W, self.H, "golem-realm", None, None)
        if not self.win:
            raise SystemExit("golem-realm: the graphics chip could not open a window")
        glfw.make_context_current(self.win)
        glfw.swap_interval(1)
        # The realm floats above everything and isn't arranged by the window manager; when the Start panel
        # is up it takes the keyboard itself (like a game's menu), and gives it back when it goes.
        from Xlib import display as xdisplay, X
        self.X, self.xd = X, xdisplay.Display()
        self.xw = self.xd.create_resource_object("window", glfw.get_x11_window(self.win))
        self.xw.change_attributes(override_redirect=True)
        self.xd.sync()
        glfw.set_window_pos(self.win, 0, 0)
        # The keyboard grab must come from the drawing's own connection to the screen, or the keys go elsewhere.
        import ctypes
        self.x11 = ctypes.CDLL("libX11.so.6")
        self.x11.XGrabKeyboard.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
        self.x11.XUngrabKeyboard.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        self.x11.XFlush.argtypes = [ctypes.c_void_p]
        self.gdpy = ctypes.c_void_p(glfw.get_x11_display())
        self.gwin = glfw.get_x11_window(self.win)
        glfw.set_input_mode(self.win, glfw.CURSOR, glfw.CURSOR_HIDDEN)
        self.ctx = moderngl.create_context()
        self.ctx.enable(moderngl.PROGRAM_POINT_SIZE | moderngl.BLEND)
        self.prog = self.ctx.program(vertex_shader=VERT, fragment_shader=FRAG)
        self.rng = np.random.default_rng()
        self.pics = Pictures(self.W, self.H)
        self.n_tabs, self.n_scene = 36000, 30000
        self.scene = homes(self.pics.scenery(), self.n_scene, self.rng)
        self.items, self.sel = TABS, 0
        self.tab_homes = self.tabs_now()
        self.cur = None
        self.visible = False
        self.t0 = time.monotonic()
        self.fly_t0, self.fly_len, self.slow = -99.0, 1.0, 1.0
        self.erase, self.erase_goal, self.idle = 0.0, 0.0, False
        self.ink = self.face_is_ink()
        self.flip_t0, self.flip_due = -99.0, False
        self.lamp, self.lamp_goal, self.mouse_t, self.pulse_t0 = [0.1, 0.4], [0.1, 0.4], -99.0, -99.0
        self.after = None                                  # what to do when the sand has flown away
        self.queue = queue.Queue()
        self.vbo = self.ctx.buffer(reserve=(self.n_tabs + self.n_scene) * 8 * 4)
        self.vao = self.ctx.vertex_array(self.prog, [(self.vbo, "3f 3f 2f", "a_from", "a_to", "a_more")])
        self.seeds = self.rng.random(self.n_tabs + self.n_scene).astype("f4")
        self.n_win = 40000
        self.win_vbo = self.ctx.buffer(reserve=self.n_win * 8 * 4)
        self.win_vao = self.ctx.vertex_array(self.prog, [(self.win_vbo, "3f 3f 2f", "a_from", "a_to", "a_more")])
        self.quad = self.ctx.program(vertex_shader=QUAD_V, fragment_shader=QUAD_F)
        qb = self.ctx.buffer(np.array([-1, -1, 1, -1, -1, 1, 1, 1], "f4").tobytes())
        self.quad_vao = self.ctx.vertex_array(self.quad, [(qb, "2f", "p")])
        self.bg = None
        self.mode = "panel"                              # or "window": a window turning to sand over the screen
        self.reply, self.reply_due, self.pending_open, self.win_pic = None, False, None, None
        glfw.set_key_callback(self.win, self.on_key)
        glfw.set_cursor_pos_callback(self.win, self.on_mouse)
        glfw.set_mouse_button_callback(self.win, self.on_click)
        threading.Thread(target=self.listen, daemon=True).start()
        threading.Thread(target=self.watch_windows, daemon=True).start()

    # --- grains ---
    def tabs_now(self):
        parts = self.pics.tabs(self.items, self.sel)
        mark = self.n_tabs // 14                   # the rest is shared by how much ink each word has
        mass = np.array([img.sum() for img, _ in parts[:-1]])
        sizes = list((mass / mass.sum() * (self.n_tabs - mark)).astype(int))
        sizes.append(self.n_tabs - sum(sizes))
        out = []
        for (img, glow), n in zip(parts, sizes):
            h = homes(img, n, self.rng)
            h[:, 2] *= glow
            out.append(h)
        return np.vstack(out)

    def scattered(self, n, wide=1.6):
        p = self.rng.random((n, 3)).astype("f4")
        p[:, :2] = (p[:, :2] - 0.5) * wide + 0.5
        p[:, 2] = 0
        return p

    def load(self, frm, to, length, slow=1.0):
        layer = np.r_[np.zeros(self.n_tabs, "f4"), np.ones(self.n_scene, "f4")]
        data = np.hstack([frm, to, np.stack([self.seeds, layer], 1)]).astype("f4")
        self.vbo.write(data.tobytes())
        self.cur = to
        self.fly_t0, self.fly_len, self.slow = time.monotonic(), length, slow

    def where_now(self):
        return self.cur if self.cur is not None else np.vstack([self.scattered(self.n_tabs), self.scattered(self.n_scene)])

    def go(self, items=None, sel=None, length=0.45):
        """Picture to picture: the tabs as they are now fly into the tabs as they should be."""
        if items is not None:
            self.items = items
        if sel is not None:
            self.sel = sel
        new = self.tabs_now()
        self.load(self.where_now(), np.vstack([new, self.scene]), length, slow=0.25)

    # --- showing and hiding ---
    def show(self, waking=False):
        self.items, self.sel, self.after = TABS, 0, None
        frm = np.vstack([self.scattered(self.n_tabs, 1.0), self.scattered(self.n_scene, 1.0)]) if waking or not self.visible else self.where_now()
        self.load(frm, np.vstack([self.tabs_now(), self.scene]), 2.6 if waking else 0.9)
        self.mode = "panel"
        self.appear(grab=True)
        self.erase_goal, self.idle = 0.0, False

    def leave(self, then=None):
        """The sand flies away, then the realm hides and `then` runs (an app, the panel, or nothing)."""
        frm = self.where_now()
        self.load(frm, np.vstack([self.scattered(self.n_tabs, 2.2), self.scattered(self.n_scene, 2.2)]), 0.6)
        self.after = ("hide", then)

    def appear(self, grab):
        if not self.visible:
            self.glfw.show_window(self.win)
            self.visible = True
        self.xw.configure(stack_mode=self.X.Above)
        if grab:
            self.xw.set_input_focus(self.X.RevertToParent, self.X.CurrentTime)
            self.xd.flush()
            for _ in range(40):                          # someone else (a menu) may hold the keyboard a moment
                if self.x11.XGrabKeyboard(self.gdpy, self.gwin, 0, 1, 1, 0) == 0:
                    break
                time.sleep(0.05)
            self.x11.XFlush(self.gdpy)
        self.xd.flush()

    def hide_now(self):
        self.x11.XUngrabKeyboard(self.gdpy, 0)
        self.x11.XFlush(self.gdpy)
        self.glfw.hide_window(self.win)
        self.visible = False
        self.mode = "panel"

    def go_idle(self):
        if not self.visible:
            self.show()
            self.erase = 1.0                              # the idle screen starts with the tabs already gone
        self.erase_goal, self.idle = 1.0, True
        log("The idle screen came")

    def wake(self):
        if self.idle:
            self.erase_goal, self.idle = 0.0, False

    # --- windows as sand ---
    def window_sand_on(self):
        try:
            return not any(line.strip() == "window_sand=off" for line in open(SETTINGS))
        except OSError:
            return True

    def screen(self):
        from PIL import ImageGrab
        return np.asarray(ImageGrab.grab().convert("RGB").resize((self.W, self.H)))

    def window_homes(self, shot, rect):
        """The window's own picture as grains: where it's bright, more sand."""
        x, y, w, h = rect
        lum = shot[::2, ::2].mean(axis=2) / 255.0
        img = np.zeros_like(lum, dtype="f4")
        img[y // 2:(y + h) // 2, x // 2:(x + w) // 2] = 0.15 + 0.85 * lum[y // 2:(y + h) // 2, x // 2:(x + w) // 2]
        return homes(img, self.n_win, self.rng)

    def set_bg(self, shot, hole=None):
        bg = shot.copy()
        if hole:
            x, y, w, h = hole
            bg[max(0, y):y + h, max(0, x):x + w] = 0
        if self.bg is None or self.bg.size != (self.W, self.H):
            self.bg = self.ctx.texture((self.W, self.H), 3, bg.tobytes())
        else:
            self.bg.write(bg.tobytes())

    def win_load(self, frm, to, length):
        data = np.hstack([frm, to, np.stack([self.rng.random(self.n_win, "f4"), np.full(self.n_win, 2, "f4")], 1)])
        self.win_vbo.write(data.astype("f4").tobytes())
        self.fly_t0, self.fly_len, self.slow = time.monotonic(), length, 0.6

    def point(self, rect, spread, n):
        x, y, w, h = rect
        p = np.zeros((n, 3), "f4")
        p[:, 0] = (x + w / 2) / self.W + (self.rng.random(n) - 0.5) * spread * w / self.W
        p[:, 1] = (y + h / 2) / self.H + (self.rng.random(n) - 0.5) * spread * h / self.H
        return p

    def window_event(self, kind, rect, conn=None):
        """close / min: the window's sand flies off (it closes underneath). full: it flies to its new size.
        open: the new window gathers out of a little cloud."""
        if self.visible and self.mode == "panel":
            if conn:
                conn.close()
            return
        x, y, w, h = rect
        rect = (max(0, x), max(0, y), min(w, self.W), min(h, self.H))
        shot = self.screen()
        self.win_pic = (self.window_homes(shot, rect), rect)
        here = self.win_pic[0]
        if kind == "close":
            self.set_bg(shot, rect)
            away = here.copy()                             # blown off by the wind of the realm, fading
            away[:, 0] += (0.25 + 0.4 * self.rng.random(self.n_win)) * 0.94
            away[:, 1] += (self.rng.random(self.n_win) - 0.6) * 0.3
            away[:, 2] = 0
            self.win_load(here, away, 0.6)
        elif kind == "min":
            self.set_bg(shot, rect)
            self.win_load(here, self.point((self.W // 2 - 20, self.H - 6, 40, 4), 1.0, self.n_win), 0.5)
        elif kind == "full":
            self.set_bg(shot * 0, None)
            self.win_load(here, here, 3.0)                 # held still until it's told where the window went
        elif kind == "open":
            self.set_bg(shot, rect)
            self.win_load(self.point(rect, 0.15, self.n_win), here, 0.5)
        self.mode = "window"
        self.after = ("hide", None)
        self.appear(grab=False)
        self.reply, self.reply_due = conn, conn is not None

    def window_moved(self, rect, conn):
        if conn:
            conn.close()
        if not self.win_pic or self.mode != "window":
            return
        here, (x0, y0, w0, h0) = self.win_pic
        x, y, w, h = rect
        to = here.copy()
        to[:, 0] = (x + (here[:, 0] * self.W - x0) * w / max(1, w0)) / self.W
        to[:, 1] = (y + (here[:, 1] * self.H - y0) * h / max(1, h0)) / self.H
        self.win_load(here, to, 0.45)
        self.after = ("hide", None)

    def page_turn(self, a, b, conn):
        """The Control Panel's pages: the old page's sand flies into the new one, over the panel's own ground."""
        from PIL import Image
        if (self.visible and self.mode == "panel") or not self.window_sand_on():
            conn.close()
            return
        try:
            pa, pb = (np.asarray(Image.open(p).convert("L").resize((self.W // 2, self.H // 2)), "f4") / 255.0 for p in (a, b))
        except OSError:
            conn.close()
            return
        ground = np.full((self.H, self.W, 3), 244 if self.ink else 0, np.uint8)
        self.set_bg(ground)
        self.win_load(homes(pa, self.n_win, self.rng), homes(pb, self.n_win, self.rng), 0.5)
        self.win_pic = None
        self.mode = "window"
        self.after = ("hide", None)
        self.appear(grab=False)
        self.reply, self.reply_due = conn, True

    def open_soon(self, con_id):
        self.pending_open = (time.monotonic() + 0.15, con_id)

    def open_now(self, con_id):
        try:
            import i3ipc
            con = i3ipc.Connection().get_tree().find_by_id(con_id)
            r = con.rect
            self.window_event("open", (r.x, r.y, r.width, r.height))
        except Exception as e:
            print("realm: no open animation:", e)

    # --- doing ---
    def choose(self):
        name, act = self.items[self.sel]
        self.pulse_t0 = time.monotonic()
        if act == "continue":
            self.leave()
        elif act == "slumber":
            self.go(SLUMBER, 0)
        elif act == "back":
            self.go(TABS, len(TABS) - 1)
        else:
            log(f"Start panel: {name}")
            self.leave(act)

    def on_key(self, w, key, sc, action, mods):
        g = self.glfw
        if action not in (g.PRESS, g.REPEAT):
            return
        if self.idle:
            self.wake()
            return
        if key in (g.KEY_UP, g.KEY_W, g.KEY_K):
            self.go(sel=(self.sel - 1) % len(self.items))
        elif key in (g.KEY_DOWN, g.KEY_S, g.KEY_J, g.KEY_TAB):
            self.go(sel=(self.sel + 1) % len(self.items))
        elif key in (g.KEY_ENTER, g.KEY_KP_ENTER, g.KEY_SPACE):
            self.choose()
        elif key == g.KEY_ESCAPE:
            if self.items is SLUMBER:
                self.go(TABS, len(TABS) - 1)
            else:
                self.leave()
        elif key in (g.KEY_B, g.KEY_I):
            start(["golem-face"])                        # the whole system turns over; the realm follows

    def on_mouse(self, w, x, y):
        if self.idle:
            self.wake()
        self.mouse_t = time.monotonic()
        self.lamp_goal = [x / self.W, y / self.H]
        for i in range(len(self.items)):
            x0, y0, x1, y1 = self.pics.tab_box(self.items, i)
            if x0 <= x / self.W <= x1 and y0 <= y / self.H <= y1 and i != self.sel:
                self.go(sel=i)

    def on_click(self, w, button, action, mods):
        if action == self.glfw.PRESS:
            if self.idle:
                self.wake()
            elif button == self.glfw.MOUSE_BUTTON_LEFT:
                self.choose()

    # --- outside ---
    def listen(self):
        try:
            os.unlink(SOCK)
        except OSError:
            pass
        srv = socket.socket(socket.AF_UNIX)
        srv.bind(SOCK)
        os.chmod(SOCK, 0o600)
        srv.listen(4)
        while True:
            c, _ = srv.accept()
            c.settimeout(2)
            try:
                cmd = c.recv(256).decode(errors="replace").strip()
            except OSError:
                c.close()
                continue
            if cmd.startswith(("win ", "page ")):
                self.queue.put((cmd, c))                   # answered once the sand is on the screen
            else:
                c.close()
                self.queue.put((cmd, None))
            self.glfw.post_empty_event()

    def watch_windows(self):
        """When any app's window opens, the realm steps aside so the app is seen."""
        try:
            import i3ipc
            i3 = i3ipc.Connection()
        except Exception as e:                            # no i3 (a test outside Golem): nothing to watch
            print("realm: not watching windows:", e)
            return

        def new(_, ev):
            self.queue.put(("app-opened %d" % ev.container.id, None))
            self.glfw.post_empty_event()
        i3.on(i3ipc.Event.WINDOW_NEW, new)
        i3.main()

    def face_is_ink(self):
        try:
            return any(line.strip() == "face=negative" for line in open(SETTINGS))
        except OSError:
            return False

    # --- each frame ---
    def run(self):
        g, last_face = self.glfw, 0.0
        self.show(waking=True)
        log("The realm woke up")
        while not g.window_should_close(self.win):
            while not self.queue.empty():
                cmd, conn = self.queue.get()
                word = cmd.split()
                if word[:1] == ["win"] and len(word) >= 6 and self.window_sand_on():
                    try:
                        rect = tuple(int(float(v)) for v in word[2:6])
                    except ValueError:
                        conn.close()
                        continue
                    if word[1] == "moved":
                        self.window_moved(rect, conn)
                    else:
                        self.window_event(word[1], rect, conn)
                    continue
                if word[:1] == ["page"] and len(word) == 3:
                    self.page_turn(word[1], word[2], conn)
                    continue
                if conn:
                    conn.close()
                if word[:1] == ["app-opened"]:
                    if self.visible and self.mode == "panel" and not self.after:
                        self.hide_now()
                    elif not self.visible and self.window_sand_on():
                        self.open_soon(int(word[1]))
                    continue
                if cmd == "show":
                    self.show()
                elif cmd == "idle":
                    self.go_idle()
                elif cmd == "hide" and self.visible:
                    self.leave()

            if self.pending_open and time.monotonic() >= self.pending_open[0]:
                self.open_now(self.pending_open[1])
                self.pending_open = None
            if not self.visible:
                g.wait_events_timeout(0.05 if self.pending_open else 0.5)
                continue
            now = time.monotonic()
            if now - last_face > 1:                       # the face changed (B, Super+I or the panel): turn the paper
                last_face = now
                if self.face_is_ink() != self.ink and not self.flip_due:
                    self.flip_t0, self.flip_due = now, True
            f = (now - self.flip_t0) / 0.7
            if self.flip_due and f >= 0.5:
                self.ink, self.flip_due = not self.ink, False
            fade = 1.0 if f >= 1 else abs(1 - 2 * f) ** 1.5
            fly = min(1.0, (now - self.fly_t0) / self.fly_len)
            if self.after and fly >= 1:
                _, then = self.after
                self.after = None
                self.hide_now()
                if then:
                    start(["i3-msg", "-q", "exec", then])
                continue
            self.erase += (self.erase_goal - self.erase) * (0.012 if self.erase_goal else 0.05)
            if now - self.mouse_t > 3:                    # keyboard: the light rests beside the chosen tab
                x0, y0, x1, y1 = self.pics.tab_box(self.items, self.sel)
                self.lamp_goal = [x0 + 0.01, (y0 + y1) / 2]
            self.lamp = [a + (b - a) * 0.15 for a, b in zip(self.lamp, self.lamp_goal)]
            fw, fh = g.get_framebuffer_size(self.win)
            self.ctx.viewport = (0, 0, fw, fh)
            if self.mode == "window":
                self.ctx.disable(self.mgl.BLEND)
                self.bg.use(0)
                self.quad_vao.render(self.mgl.TRIANGLE_STRIP)
                self.ctx.enable(self.mgl.BLEND)
                self.ctx.blend_func = (self.mgl.ZERO, self.mgl.ONE_MINUS_SRC_COLOR) if self.ink else (self.mgl.ONE, self.mgl.ONE)
            elif self.ink:
                self.ctx.clear(0.957, 0.957, 0.945)
                self.ctx.blend_func = self.mgl.ZERO, self.mgl.ONE_MINUS_SRC_COLOR
            else:
                self.ctx.clear(0.0, 0.0, 0.0)
                self.ctx.blend_func = self.mgl.ONE, self.mgl.ONE
            u = {"t_now": now - self.t0, "fly": fly, "slow": self.slow, "ink": float(self.ink), "fade": fade,
                 "erase": self.erase, "size": max(1.6, 2.4 * fh / 1080) * (1.5 if self.mode == "window" else 1.0), "aspect": fw / max(1, fh),
                 "lamp": tuple(self.lamp), "lamp_on": 0.0 if self.idle or self.mode == "window" else 1.0,
                 "pulse": min(1.0, (now - self.pulse_t0) / 0.6),
                 "line_at": (0.62 * fw / max(1, fh), 0.5), "line_out": (0.94, -0.34)}
            for k, v in u.items():
                if k in self.prog:
                    self.prog[k].value = v
            (self.win_vao if self.mode == "window" else self.vao).render(self.mgl.POINTS)
            g.swap_buffers(self.win)
            if self.reply_due:                            # the sand is on the screen: the window may go now
                try:
                    self.reply.sendall(b"ready")
                    self.reply.close()
                except OSError:
                    pass
                self.reply, self.reply_due = None, False
            g.poll_events()


def start(cmd):
    try:
        subprocess.Popen(cmd)
    except OSError as e:
        log(f"Could not start {cmd[0]}: {e}")


def quiet(cmd):
    try:
        subprocess.run(cmd, check=False, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        pass


def log(msg):
    quiet(["logger", "-t", "golem", msg])


def send(cmd):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(2)
    s.connect(SOCK)
    s.sendall(cmd.encode())
    s.close()


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else "show"
    if arg == "--daemon":
        try:
            Realm().run()
        except SystemExit as e:
            log(f"The realm could not start: {e}")
            raise
        return
    if arg in ("win", "page"):
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(1.5)
        try:
            s.connect(SOCK)
            s.sendall(" ".join(sys.argv[1:]).encode())
            s.recv(16)                                   # wait until the sand covers the window (or give up)
        except OSError:
            pass
        return
    if arg not in ("show", "idle", "hide"):
        print(__doc__)
        return
    try:
        send(arg)
    except OSError:
        if arg not in ("show", "idle"):
            return
        # Not running (it stopped): start it again, as part of the desktop, and then ask again.
        quiet(["i3-msg", "-q", "exec", "golem-realm --daemon"])
        for _ in range(40):
            time.sleep(0.25)
            try:
                send(arg)
                return
            except OSError:
                pass


if __name__ == "__main__":
    main()

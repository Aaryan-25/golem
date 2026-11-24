# Part of Golem: the shadow realm and the desktop; MAP.md section 5.5.
"""golem-sand: the sand test. Can this laptop draw Golem's look, and does it feel like the shadow realm?

Every picture is made of grains of sand, drawn by the graphics chip.
  Space   the sand flies into the next picture
  B       turn the paper over (light on black <-> ink on white)
  D       drift on or off
  T       how the sand travels: FLY (anywhere) or FLOW (short paths)
  + / -   more or fewer grains
  Esc, Q  quit (the smoothness is written to ~/golem-sand.txt and the truth log)
golem-sand [--grains N] [--seconds S] [--windowed] [picture.png ...]
"""
import os, subprocess, sys, time
import numpy as np
import glfw, moderngl

GRID = 256   # each picture is read at 256 x 256

VERT = """
#version 330
in vec3 a_from; in vec3 a_to; in float a_seed;
uniform float t_now, fly, fly_mode, wind, ink, fade, aspect, size;
uniform vec2 line_at, line_out;
out float v_amt;
float rnd(float s, float k) { return fract(sin(s * 91.7 + k * 47.3) * 43758.55); }
float ease(float x) { return x * x * (3.0 - 2.0 * x); }
void main() {
    // flying from the old picture to the new one: each grain leaves at its own moment,
    // is thrown outward at first, then drawn in to its new home
    float wait = rnd(a_seed, 1.0) * mix(0.45, 0.25, fly_mode);
    float e = ease(clamp((fly - wait) / (1.0 - wait), 0.0, 1.0));
    vec2 p = mix(a_from.xy, a_to.xy, e);
    float bright = mix(a_from.z, a_to.z, e);
    vec2 out_dir = normalize(a_from.xy + vec2(rnd(a_seed, 2.0) - 0.5, rnd(a_seed, 3.0) - 0.5) + 1e-4);
    float far = 0.1 + 0.9 * pow(rnd(a_seed, 4.0), 2.0);
    p += out_dir * sin(3.14159 * e) * far * mix(0.12, 0.45, fly_mode);

    // breathing: slow and shallow
    p *= 1.0 + 0.008 * sin(t_now * 0.7);

    // drift: past a wavering line the sand lets go, blows away, and comes home again
    float along = dot(p - line_at, vec2(-line_out.y, line_out.x));
    float waver = 0.10 * sin(along * 3.0 + t_now * 0.15) + 0.05 * sin(along * 8.0 - t_now * 0.1)
                + (rnd(a_seed, 5.0) - 0.5) * 0.3;
    float away = smoothstep(0.0, 1.1, dot(p - line_at, line_out) + waver) * wind;
    float alive = 1.0;
    if (away > 0.0) {
        float life = 4.0 + 5.0 * rnd(a_seed, 6.0);
        float ph = fract(t_now / life + rnd(a_seed, 7.0));
        float stay = mix(0.85, 0.08, away);
        float gone = max(0.0, (ph - stay) / (1.0 - stay));
        float reach = 1.6 * away * (0.5 + rnd(a_seed, 8.0));
        vec2 swirl = vec2(sin(p.y * 5.0 + t_now + a_seed), cos(p.x * 4.0 - t_now * 0.8 + a_seed));
        p += (line_out + 0.35 * swirl) * reach * gone * sqrt(gone);
        alive = smoothstep(0.0, 0.06, ph) * (1.0 - smoothstep(0.35, 1.0, gone));
    }
    v_amt = bright * alive * fade;
    gl_Position = vec4(p.x / aspect, p.y, 0.0, 1.0);
    gl_PointSize = size * (0.7 + 0.8 * rnd(a_seed, 9.0));
}
"""
FRAG = """
#version 330
in float v_amt; uniform float ink; out vec4 color;
void main() {
    float r = length(gl_PointCoord * 2.0 - 1.0);
    float a = v_amt * smoothstep(1.0, 0.2, r);
    // light on black: each grain adds light.  ink on white: each grain takes light away
    color = ink > 0.5 ? vec4(vec3(a * 0.55), 1.0) : vec4(vec3(0.92, 0.91, 0.88) * a * 0.6, 1.0);
}
"""


def moon():
    y, x = np.mgrid[-1:1:GRID * 1j, -1:1:GRID * 1j]
    r = np.hypot(x, y) / 0.7
    z = np.sqrt(np.clip(1 - r * r, 0, 1))
    light = np.clip(-0.55 * x / 0.7 + 0.45 * y / 0.7 + 0.7 * z, 0, 1)
    return np.where(r < 1, 0.05 + 0.95 * light ** 0.8, 0.0)


def taiji():
    y, x = np.mgrid[-1:1:GRID * 1j, -1:1:GRID * 1j]
    R = 0.72
    r = np.hypot(x, y)
    light = x > 0
    light = np.where(np.hypot(x, y - R / 2) < R / 2, True, light)
    light = np.where(np.hypot(x, y + R / 2) < R / 2, False, light)
    light = np.where(np.hypot(x, y - R / 2) < R / 7, False, light)
    light = np.where(np.hypot(x, y + R / 2) < R / 7, True, light)
    img = np.where(light, 1.0, 0.07)
    img = np.where(np.abs(r - R) < 0.012, 0.8, img)
    return np.where(r <= R + 0.012, img, 0.0)


def from_file(path):
    from PIL import Image
    im = Image.open(path).convert("L")
    im.thumbnail((GRID, GRID))
    a = np.zeros((GRID, GRID))
    w, h = im.size
    a[(GRID - h) // 2:(GRID - h) // 2 + h, (GRID - w) // 2:(GRID - w) // 2 + w] = np.asarray(im) / 255.0
    return a


def hilbert(x, y, n=GRID):
    """Position along a curve that fills the square: grains near each other get numbers near each other."""
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
    """Where each of n grains lives in this picture, and how bright it is. Brighter places get more grains."""
    w = img.ravel() ** 1.3
    w = w / w.sum()
    pick = rng.choice(img.size, size=n, p=w)
    py, px = np.divmod(pick, GRID)
    pick = pick[np.argsort(hilbert(px, py))]
    py, px = np.divmod(pick, GRID)
    x = (px + rng.random(n)) / GRID * 2 - 1
    y = 1 - (py + rng.random(n)) / GRID * 2
    return np.stack([x, y, img.ravel()[pick]], 1).astype("f4")


def main():
    args = sys.argv[1:]
    grains, seconds, windowed, files = 65536, None, False, []
    while args:
        a = args.pop(0)
        if a == "--grains": grains = int(args.pop(0))
        elif a == "--seconds": seconds = float(args.pop(0))
        elif a == "--windowed": windowed = True
        elif a in ("-h", "--help"): print(__doc__); return
        else: files.append(a)
    pictures = [from_file(f) for f in files] or [moon(), taiji()]
    if len(pictures) == 1: pictures.append(taiji())

    if not glfw.init(): sys.exit("golem-sand: no screen to draw on")
    glfw.window_hint(glfw.CONTEXT_VERSION_MAJOR, 3); glfw.window_hint(glfw.CONTEXT_VERSION_MINOR, 3)
    glfw.window_hint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
    mon = glfw.get_primary_monitor(); mode = glfw.get_video_mode(mon)
    W, H = (1000, 640) if windowed else (mode.size.width, mode.size.height)
    win = glfw.create_window(W, H, "golem-sand", None if windowed else mon, None)
    if not win: sys.exit("golem-sand: the graphics chip could not open a drawing window")
    glfw.make_context_current(win); glfw.swap_interval(1)
    ctx = moderngl.create_context()
    ctx.enable(moderngl.PROGRAM_POINT_SIZE | moderngl.BLEND)
    prog = ctx.program(vertex_shader=VERT, fragment_shader=FRAG)
    chip = ctx.info.get("GL_RENDERER", "unknown")

    rng = np.random.default_rng(7)
    S = {"n": grains, "pic": 0, "fly_t0": -99.0, "fly_mode": 1.0, "ink": False, "flip_t0": -99.0,
         "wind": 1.0, "wind_goal": 1.0, "quit": False, "frames": [], "vbo": None, "vao": None, "cache": {}}

    def pic_homes(i):
        key = (i, S["n"])
        if key not in S["cache"]: S["cache"][key] = homes(pictures[i], S["n"], rng)
        return S["cache"][key]

    def load(frm, to):
        n = S["n"]
        if S["fly_mode"] > 0.5: to = to[rng.permutation(n)]   # FLY: every grain goes anywhere
        data = np.hstack([frm, to, rng.random((n, 1), dtype="f4")]).astype("f4")
        if S["vbo"] is None or S["vbo"].size != data.nbytes:
            S["vbo"] = ctx.buffer(data.tobytes())
            S["vao"] = ctx.vertex_array(prog, [(S["vbo"], "3f 3f 1f", "a_from", "a_to", "a_seed")])
        else:
            S["vbo"].write(data.tobytes())
        S["to"] = to

    def turn():
        S["pic"] = (S["pic"] + 1) % len(pictures)
        load(S["to"], pic_homes(S["pic"]))
        S["fly_t0"] = time.monotonic()

    def resize(n):
        S["n"] = max(4096, min(1 << 20, n)); S["cache"].clear()
        h = pic_homes(S["pic"]); load(h, h)
        print(f"grains: {S['n']}")

    def on_key(w, key, sc, action, mods):
        if action != glfw.PRESS: return
        if key in (glfw.KEY_ESCAPE, glfw.KEY_Q): S["quit"] = True
        elif key == glfw.KEY_SPACE: turn()
        elif key == glfw.KEY_B: S["flip_t0"] = time.monotonic(); S["flip_due"] = True
        elif key == glfw.KEY_D: S["wind_goal"] = 0.0 if S["wind_goal"] else 1.0
        elif key == glfw.KEY_T:
            S["fly_mode"] = 0.0 if S["fly_mode"] else 1.0
            print("travel:", "FLY" if S["fly_mode"] else "FLOW")
        elif key in (glfw.KEY_EQUAL, glfw.KEY_KP_ADD): resize(S["n"] * 2)
        elif key in (glfw.KEY_MINUS, glfw.KEY_KP_SUBTRACT): resize(S["n"] // 2)
    glfw.set_key_callback(win, on_key)

    h = pic_homes(0); load(h, h)
    start = last = last_print = time.monotonic()
    while not glfw.window_should_close(win) and not S["quit"]:
        now = time.monotonic()
        S["frames"].append(now - last); last = now
        if seconds and now - start > seconds: break
        # turning the paper: everything dips to nothing, the paper changes, and the sand comes back
        f = (now - S["flip_t0"]) / 0.7
        if S.get("flip_due") and f >= 0.5:
            S["ink"] = not S["ink"]; S["flip_due"] = False
        fade = 1.0 if f >= 1 else abs(1 - 2 * f) ** 1.5
        S["wind"] += (S["wind_goal"] - S["wind"]) * 0.03
        fw, fh = glfw.get_framebuffer_size(win)
        ctx.viewport = (0, 0, fw, fh)
        if S["ink"]:
            ctx.clear(0.957, 0.957, 0.945); ctx.blend_func = moderngl.ZERO, moderngl.ONE_MINUS_SRC_COLOR
        else:
            ctx.clear(0.02, 0.02, 0.024); ctx.blend_func = moderngl.ONE, moderngl.ONE
        u = {"t_now": now - start, "fly": min(1.0, (now - S["fly_t0"]) / 1.8), "fly_mode": S["fly_mode"],
             "wind": S["wind"], "ink": float(S["ink"]), "fade": fade, "aspect": fw / max(1, fh),
             "size": max(1.5, 2.2 * fh / 1080), "line_at": (-0.05, 0.0), "line_out": (0.97, -0.24)}
        for k, v in u.items():
            if k in prog: prog[k].value = v
        S["vao"].render(moderngl.POINTS)
        glfw.swap_buffers(win); glfw.poll_events()
        if now - last_print > 2:
            fps = len([x for x in S["frames"][-240:] if x > 0]) / max(1e-6, sum(S["frames"][-240:]))
            glfw.set_window_title(win, f"golem-sand {fps:.0f} fps, {S['n']} grains")
            print(f"smoothness: {fps:.0f} frames a second with {S['n']} grains"); last_print = now

    fr = [x for x in S["frames"][10:] if x > 0]
    fps = len(fr) / sum(fr) if fr else 0
    verdict = "smooth" if fps >= 50 else "a bit slow, try fewer grains" if fps >= 25 else "too slow, try fewer grains"
    line = f"Sand test: {fps:.0f} frames a second with {S['n']} grains ({verdict}), chip: {chip}"
    print(line)
    with open(os.path.expanduser("~/golem-sand.txt"), "a") as out:
        out.write(time.strftime("%d %b %Y %H:%M  ") + line + "\n")
    subprocess.run(["logger", "-t", "golem", line], check=False)
    glfw.terminate()


if __name__ == "__main__":
    main()

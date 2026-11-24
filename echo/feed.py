# Feeding an Echo: reading chats (WhatsApp exports, or chats edited by hand) and keeping only the messages
# of the one person this Echo is. Voice notes from that person become text offline (whisper.cpp).
# The chats go into Echo's own folder first: ~/zones/golem-echo/feed (a .txt, or the .zip WhatsApp makes).
# Part of Golem: Echo, the owner's AIs; MAP.md section 5.6.
import json
import os
import random
import re
import subprocess
import tempfile
import zipfile

# 12/11/26, 9:41 pm - Name: text        (Android)
# [12/11/26, 9:41:05 PM] Name: text     (iPhone)
# Name: text                            (a chat edited by hand)
STAMPED = re.compile(r"^‎?\[?(\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}),? (\d{1,2}[:.]\d{2}(?:[:.]\d{2})?\s?(?:[apAP]\.?[mM]\.?)?)\]?(?: -)? ([^:]{1,40}): (.*)$")
PLAIN = re.compile(r"^([^:\[\]]{1,40}): (.+)$")
VOICE = re.compile(r"(?:<attached: )?([\w-]+\.(?:opus|ogg|m4a|mp3|aac|wav))(?:>| \(file attached\))", re.I)
SKIP = ("<media omitted>", "this message was deleted", "you deleted this message", "end-to-end encrypted",
        "null", "<this message was edited>", "missed voice call", "missed video call")


def chats(feed_dir):
    """The chats waiting in the feed folder: .txt files, and the .txt inside each .zip."""
    out = []
    for f in sorted(os.listdir(feed_dir)) if os.path.isdir(feed_dir) else []:
        p = os.path.join(feed_dir, f)
        if f.lower().endswith(".zip"):
            d = p[:-4]
            if not os.path.isdir(d):
                with zipfile.ZipFile(p) as z:
                    for m in z.namelist():   # only plain names: nothing may land outside the folder
                        if "/" not in m and "\\" not in m and not m.startswith("."):
                            z.extract(m, d)
            out += [os.path.join(d, t) for t in sorted(os.listdir(d)) if t.lower().endswith(".txt")]
        elif f.lower().endswith(".txt"):
            out.append(p)
    return out


def parse(path):
    """[(who, text)] in order. Lines without a name continue the message before them."""
    msgs, stamped = [], None
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()
    stamped = sum(1 for x in lines[:200] if STAMPED.match(x)) > 2
    for line in lines:
        m = STAMPED.match(line) if stamped else PLAIN.match(line)
        if m:
            who, text = m.groups()[-2:]
            msgs.append([who.strip().lstrip("‎~ "), text.strip()])
        elif msgs and line.strip():
            msgs[-1][1] += "\n" + line.strip()
    return [(w, t.replace("‎", "")) for w, t in msgs]


def people(msgs):
    count = {}
    for w, _ in msgs:
        count[w] = count.get(w, 0) + 1
    return sorted(count.items(), key=lambda x: -x[1])


def hear(audio, ears, lang="auto"):
    """A voice note as text, offline. Returns '' if it can't be heard."""
    if not ears or not os.path.exists(audio):
        return ""
    with tempfile.TemporaryDirectory() as t:
        wav = os.path.join(t, "v.wav")
        if subprocess.run(["ffmpeg", "-loglevel", "quiet", "-i", audio, "-ar", "16000", "-ac", "1", wav]).returncode:
            return ""
        r = subprocess.run(["whisper-cli", "-m", ears, "-f", wav, "-l", lang, "-nt", "-np", "-t", str(os.cpu_count() or 2)],
                           capture_output=True, text=True)
        return " ".join(r.stdout.split()) if r.returncode == 0 else ""


def take(path, person, ears=None, say=lambda s: None):
    """This person's messages from one chat, each with the message it answered (if someone else wrote it)."""
    msgs, out, before = parse(path), [], ""
    folder = os.path.dirname(path)
    voices = 0
    for who, text in msgs:
        low = text.lower()
        if who != person:
            if not any(s in low for s in SKIP):
                before = text[:200]
            continue
        v = VOICE.search(text)
        if v:
            voices += 1
            say(f"listening to voice note {voices}...")
            heard = hear(os.path.join(folder, v.group(1)), ears)
            if not heard:
                continue
            text, kind = heard, "voice"
        elif any(s in low for s in SKIP) or not text.strip():
            continue
        else:
            kind = "text"
        out.append({"to": before, "said": text[:600], "kind": kind})
        before = ""
    return out


def add(samples_path, new):
    old = load(samples_path)
    seen = {s["said"] for s in old}
    fresh = [s for s in new if s["said"] not in seen]
    with open(samples_path, "a", encoding="utf-8") as f:
        for s in fresh:
            f.write(json.dumps(s, ensure_ascii=False) + "\n")
    return len(fresh)


def load(samples_path):
    out = []
    try:
        with open(samples_path, encoding="utf-8") as f:
            for line in f:
                try:
                    out.append(json.loads(line))
                except ValueError:
                    pass
    except OSError:
        pass
    return out


def pick(samples, budget=2400, seed=None):
    """A spread of short real messages that fits the brain's room (about 4 characters per word-piece)."""
    rnd = random.Random(seed)
    pool = [s for s in samples if len(s["said"]) <= 240]
    rnd.shuffle(pool)
    out, used = [], 0
    for s in pool:
        line = (f"(to: {s['to'][:80]}) " if s.get("to") else "") + s["said"]
        if used + len(line) > budget:
            break
        out.append(line)
        used += len(line)
    return out

# Echo's trainer: teaches one Echo the voice of the person it is fed, on the NVIDIA card (the Asus).
# It trains a small "voice layer" (a LoRA) on top of the brain; the brain itself never changes, and the layer can
# be thrown away any time. It runs in the OFFLINE zone (no internet), and only reads what the Echo was fed.
#   python3 train.py ECHO_FOLDER SLUG          (started by Echo's hands when I press TRAIN)
# Progress goes to echos/SLUG/train.json, so the app can show a bar. A file echos/SLUG/train.stop stops it.
import json
import math
import os
import random
import subprocess
import sys
import time

D, SLUG = sys.argv[1], sys.argv[2]
E = os.path.join(D, "echos", SLUG)
T = os.path.join(D, "trainer")
PROGRESS, STOP = os.path.join(E, "train.json"), os.path.join(E, "train.stop")
SIZES = [("3B", "Llama-3.2-3B-Instruct-Q4_K_M.gguf"), ("1B", "Llama-3.2-1B-Instruct-Q4_K_M.gguf")]
MAX_LEN, ACCUM, MAX_UPDATES = 256, 8, 400


def tell(**k):
    k["t"] = time.strftime("%H:%M:%S")
    with open(PROGRESS + ".new", "w", encoding="utf-8") as f:
        json.dump(k, f)
    os.replace(PROGRESS + ".new", PROGRESS)


def fail(why):
    tell(state="failed", why=why)
    subprocess.run(["logger", "-t", "golem", f"Echo: training {SLUG} failed: {why}"], check=False)
    sys.exit(1)


def examples(profile):
    """(question, answer) pairs from the fed messages: what was said to the person, and what they replied."""
    out = []
    with open(os.path.join(E, "samples.jsonl"), encoding="utf-8") as f:
        for line in f:
            try:
                s = json.loads(line)
            except ValueError:
                continue
            if s.get("said", "").strip():
                out.append((s.get("to") or "(you start the chat)", s["said"].strip()))
    return out


def train(size, base, pairs, name):
    import torch
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

    tell(state="loading", size=size)
    tok = AutoTokenizer.from_pretrained(base)
    # 4-bit brain; float16 maths (this card has no bfloat16)
    q = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4", bnb_4bit_use_double_quant=True,
                           bnb_4bit_compute_dtype=torch.float16)
    model = AutoModelForCausalLM.from_pretrained(base, quantization_config=q, device_map={"": 0}, torch_dtype=torch.float16)
    model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)
    model = get_peft_model(model, LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05, task_type="CAUSAL_LM",
                                             target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                                                             "gate_proj", "up_proj", "down_proj"]))
    system = f"You are {name}."
    data = []
    for to, said in pairs:   # learn only the reply, not the question
        prompt = tok.apply_chat_template([{"role": "system", "content": system}, {"role": "user", "content": to}],
                                         add_generation_prompt=True)
        reply = tok(said, add_special_tokens=False)["input_ids"] + [tok.convert_tokens_to_ids("<|eot_id|>")]
        ids = (prompt + reply)[:MAX_LEN]
        labels = ([-100] * len(prompt) + reply)[:MAX_LEN]
        if any(x != -100 for x in labels):
            data.append((ids, labels))
    epochs = 2 if len(data) < 600 else 1
    updates = min(MAX_UPDATES, math.ceil(len(data) * epochs / ACCUM))
    opt = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad], lr=2e-4)
    scaler = torch.amp.GradScaler("cuda")
    model.train()
    order, start, step, loss_avg = [], time.time(), 0, None
    while step < updates:
        if os.path.exists(STOP):
            os.remove(STOP)
            fail("stopped by me")
        for _ in range(ACCUM):
            if not order:
                order = list(range(len(data)))
                random.shuffle(order)
            ids, labels = data[order.pop()]
            with torch.autocast("cuda", dtype=torch.float16):
                out = model(input_ids=torch.tensor([ids], device="cuda"), labels=torch.tensor([labels], device="cuda"))
            scaler.scale(out.loss / ACCUM).backward()
            loss_avg = out.loss.item() if loss_avg is None else 0.95 * loss_avg + 0.05 * out.loss.item()
        scaler.step(opt)
        scaler.update()
        opt.zero_grad(set_to_none=True)
        step += 1
        left = (time.time() - start) / step * (updates - step)
        tell(state="training", size=size, step=step, of=updates, minutes_left=round(left / 60), loss=round(loss_avg, 3))
    out_dir = os.path.join(T, "out-" + SLUG)
    model.save_pretrained(out_dir)
    return out_dir


def main():
    profile = json.load(open(os.path.join(E, "profile.json"), encoding="utf-8"))
    pairs = examples(profile)
    if len(pairs) < 30:
        fail(f"only {len(pairs)} messages fed; it needs at least 30 (FEEDING)")
    try:
        import torch
    except ImportError:
        fail("the trainer isn't set up: in a terminal, type golem-echo-trainer")
    if not torch.cuda.is_available():
        fail("no NVIDIA card here, or this app may not use it (Control Panel > APPS > golem-echo-train > nvidia)")
    tell(state="starting", messages=len(pairs))
    for size, gguf in SIZES:
        base = os.path.join(T, "base-" + size)
        if not os.path.isdir(base):
            continue
        try:
            out = train(size, base, pairs, profile["name"])
            break
        except torch.cuda.OutOfMemoryError:
            import gc
            gc.collect()
            torch.cuda.empty_cache()
            tell(state="smaller", why=f"the {size} brain did not fit on the card; trying a smaller one")
    else:
        fail("no brain fitted on the NVIDIA card")
    tell(state="saving", size=size)
    voice = os.path.join(E, f"voice-{size}.gguf")
    # The converter only needs the brain's shape and words; give it a plain copy of them (not the 4-bit details).
    shape = os.path.join(T, "shape-" + size)
    os.makedirs(shape, exist_ok=True)
    cfg = json.load(open(os.path.join(base, "config.json"), encoding="utf-8"))
    cfg.pop("quantization_config", None)
    cfg["torch_dtype"] = "float16"
    json.dump(cfg, open(os.path.join(shape, "config.json"), "w", encoding="utf-8"))
    for f in os.listdir(base):
        if f.startswith(("tokenizer", "special_tokens", "generation_config")):
            with open(os.path.join(base, f), "rb") as a, open(os.path.join(shape, f), "wb") as b:
                b.write(a.read())
    src = os.environ["GOLEM_LLAMA_SRC"]
    r = subprocess.run([sys.executable, os.path.join(src, "convert_lora_to_gguf.py"), "--base", shape, "--outtype", "f16",
                        "--outfile", voice, out], env=dict(os.environ, PYTHONPATH=f"{src}:{src}/gguf-py"),
                       capture_output=True, text=True)
    if r.returncode or not os.path.exists(voice):
        fail("the voice layer could not be saved: " + (r.stderr.strip().splitlines() or ["?"])[-1][:200])
    for other, _ in SIZES:                      # one voice per Echo
        if other != size and os.path.exists(os.path.join(E, f"voice-{other}.gguf")):
            os.remove(os.path.join(E, f"voice-{other}.gguf"))
    profile["voice"] = {"brain": size, "brain_file": dict(SIZES)[size], "file": os.path.basename(voice),
                        "messages": len(pairs), "made": time.strftime("%Y-%m-%d %H:%M")}
    with open(os.path.join(E, "profile.json"), "w", encoding="utf-8") as f:
        json.dump(profile, f, ensure_ascii=False, indent=1)
    note = "" if size == "3B" else " (the 3B brain did not fit, so it uses the 1B brain)"
    tell(state="done", size=size, note=note)
    subprocess.run(["logger", "-t", "golem", f"Echo: {profile['name']} learned its voice from {len(pairs)} messages"
                    f" on the NVIDIA card{note}"], check=False)


if __name__ == "__main__":
    main()

#!/usr/bin/env python
"""Sound effects from a written description, with AudioGen.

    ~/.audiocraft/bin/python examples/audiogen.py "a door closing in a stairwell"

Same shape as musicgen.py, different model: AudioGen is trained on environmental
sound rather than music, so it wants descriptions of events — footsteps on
gravel, a kettle coming to the boil — not genres. There is only one public
checkpoint, audiogen-medium, and it is about 6 GB on first run.

This is the model the installer's own --generate flag uses, so if that step
passed, this script is exercising a path that already worked once.
"""
import argparse
import os
import warnings

warnings.filterwarnings("ignore")

import torch
from audiocraft.data.audio import audio_write
from audiocraft.models import AudioGen

p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
p.add_argument("prompt", nargs="+", help="one or more descriptions; each becomes its own file")
p.add_argument("--duration", type=float, default=5, help="seconds (default 5)")
p.add_argument("--model", default="facebook/audiogen-medium", help="default facebook/audiogen-medium")
p.add_argument("--out", default="out", help="directory to write into (default ./out)")
p.add_argument("--seed", type=int, help="fix the randomness, so the same prompt gives the same audio")
args = p.parse_args()

if args.seed is not None:
    torch.manual_seed(args.seed)

print(f"loading {args.model} — the first time, this downloads it")
model = AudioGen.get_pretrained(args.model)
model.set_generation_params(duration=args.duration)

print(f"generating {args.duration:g}s for {len(args.prompt)} prompt(s) on {model.device}")
wav = model.generate(args.prompt, progress=True)

os.makedirs(args.out, exist_ok=True)
for i, one in enumerate(wav):
    stem = os.path.join(args.out, f"audiogen-{i}")
    audio_write(stem, one.cpu(), model.sample_rate,
                strategy="loudness", loudness_compressor=True)
    print(f"  wrote {stem}.wav  — {args.prompt[i]!r}")

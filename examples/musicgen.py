#!/usr/bin/env python
"""Music from a written description, with MusicGen.

    ~/.audiocraft/bin/python examples/musicgen.py "lo-fi piano, rain outside"

The first run with a given model downloads its weights — small is about 2 GB,
medium about 6 GB — into ~/.cache/huggingface, and every run after that is
offline. Nothing here asks for a GPU: on a Mac audiocraft runs this on the CPU,
so a few seconds of audio takes a few minutes of wall clock. Start with
--duration 2 to confirm it works before asking for anything long.
"""
import argparse
import os
import warnings

warnings.filterwarnings("ignore")

import torch
from audiocraft.data.audio import audio_write
from audiocraft.models import MusicGen

p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
p.add_argument("prompt", nargs="+", help="one or more descriptions; each becomes its own file")
p.add_argument("--duration", type=float, default=8, help="seconds (default 8)")
p.add_argument("--model", default="facebook/musicgen-small",
               help="small | medium | large, as facebook/musicgen-NAME (default small)")
p.add_argument("--out", default="out", help="directory to write into (default ./out)")
p.add_argument("--seed", type=int, help="fix the randomness, so the same prompt gives the same audio")
p.add_argument("--temperature", type=float, default=1.0, help="higher wanders further from the prompt")
args = p.parse_args()

if args.seed is not None:
    torch.manual_seed(args.seed)

print(f"loading {args.model} — the first time, this downloads it")
model = MusicGen.get_pretrained(args.model)
model.set_generation_params(duration=args.duration, temperature=args.temperature)

print(f"generating {args.duration:g}s for {len(args.prompt)} prompt(s) on {model.device}")
wav = model.generate(args.prompt, progress=True)

os.makedirs(args.out, exist_ok=True)
for i, one in enumerate(wav):
    # audio_write takes a stem and appends the extension itself, so passing
    # "out/musicgen-0.wav" here would write "out/musicgen-0.wav.wav".
    stem = os.path.join(args.out, f"musicgen-{i}")
    audio_write(stem, one.cpu(), model.sample_rate,
                strategy="loudness", loudness_compressor=True)
    print(f"  wrote {stem}.wav  — {args.prompt[i]!r}")

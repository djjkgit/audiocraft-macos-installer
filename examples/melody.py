#!/usr/bin/env python
"""Re-scoring a tune you already have, with MusicGen's melody model.

    ~/.audiocraft/bin/python examples/melody.py hummed.wav "brass band, marching"

musicgen-melody takes a description *and* a reference recording, and follows the
reference's melodic contour while taking its instruments and mood from the text.
The reference can be anything ffmpeg reads — a hummed voice memo works — and
only the first --melody-seconds of it are used, since the conditioning is a
chroma summary rather than the audio itself.

It is the largest of the checkpoints here at roughly 1.5B parameters, so this is
the slowest of the three scripts and the longest first download. Confirm
musicgen.py works before reaching for it.
"""
import argparse
import os
import warnings

warnings.filterwarnings("ignore")

import torch
from audiocraft.data.audio import audio_read, audio_write
from audiocraft.models import MusicGen

p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
p.add_argument("melody", help="path to the reference recording")
p.add_argument("prompt", nargs="+", help="one or more descriptions; each becomes its own file")
p.add_argument("--duration", type=float, default=8, help="seconds to generate (default 8)")
p.add_argument("--melody-seconds", type=float, default=8, help="how much of the reference to read (default 8)")
p.add_argument("--model", default="facebook/musicgen-melody", help="default facebook/musicgen-melody")
p.add_argument("--out", default="out", help="directory to write into (default ./out)")
p.add_argument("--seed", type=int, help="fix the randomness, so the same prompt gives the same audio")
args = p.parse_args()

if args.seed is not None:
    torch.manual_seed(args.seed)

melody, melody_sr = audio_read(args.melody, duration=args.melody_seconds)
print(f"read {args.melody} — {melody.shape[-1] / melody_sr:.1f}s at {melody_sr} Hz")

print(f"loading {args.model} — the first time, this downloads it")
model = MusicGen.get_pretrained(args.model)
model.set_generation_params(duration=args.duration)

# One copy of the melody per description: the two lists are zipped, not
# broadcast, so a single melody against three prompts would silently generate
# only the first.
melodies = [melody] * len(args.prompt)

print(f"generating {args.duration:g}s for {len(args.prompt)} prompt(s) on {model.device}")
wav = model.generate_with_chroma(args.prompt, melodies, melody_sr, progress=True)

os.makedirs(args.out, exist_ok=True)
for i, one in enumerate(wav):
    stem = os.path.join(args.out, f"melody-{i}")
    audio_write(stem, one.cpu(), model.sample_rate,
                strategy="loudness", loudness_compressor=True)
    print(f"  wrote {stem}.wav  — {args.prompt[i]!r}")

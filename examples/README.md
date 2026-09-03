# Three things to try once it is installed

Run them with the interpreter the installer made, not whatever `python` your
shell finds — the environment at `~/.audiocraft` is where audiocraft and the
xformers stand-in live, and nothing is on your `PATH`.

```bash
PY=~/.audiocraft/bin/python        # or $PREFIX/bin/python if you moved it
```

Start with the smallest, shortest thing, because the first run of any model
downloads its weights and there is no point discovering a problem at the end of
a 6 GB download:

```bash
$PY examples/musicgen.py --duration 2 "a single piano chord"
```

That writes `out/musicgen-0.wav`. If it plays, everything below works too.

| | |
|---|---|
| `musicgen.py` | music from a description — `"lo-fi piano, rain outside"` |
| `audiogen.py` | sound effects from a description — `"a door closing in a stairwell"` |
| `melody.py` | music from a description *and* a tune you hum |

```bash
$PY examples/musicgen.py "80s synthwave, driving bassline" --duration 15 --model facebook/musicgen-medium
$PY examples/audiogen.py "rain on a tin roof" "distant thunder" --duration 5
$PY examples/melody.py hummed.m4a "brass band, marching"
```

Every script takes several prompts at once and writes one file per prompt into
`--out` (default `./out`), takes `--duration` in seconds, and takes `--seed` if
you want the same prompt to give you the same audio twice.

## What to expect

**It runs on the CPU.** audiocraft picks CUDA or CPU and there is no third
option, so on a Mac it is the CPU regardless of how good your GPU is. Expect a
few minutes of wall clock for a few seconds of audio with the small model, and
several times that with medium or melody. The progress bar is honest; nothing
is stuck.

**The first run of each model downloads it.** Roughly 2 GB for
musicgen-small, 6 GB or so for audiogen-medium and musicgen-medium, more for
melody. They go to `~/.cache/huggingface` and are shared across every script
here, so it happens once per model, not once per run.

**Descriptions do different work in the two models.** MusicGen wants genre,
instruments and mood. AudioGen wants an event — something that happens, in a
place. Asking AudioGen for a genre gets you noise that means nothing.

**Do not upgrade anything in this environment.** `pip install --upgrade` on
numpy, transformers or xformers here breaks it, each in its own quiet way — the
main [README](../README.md) explains all three. If something that used to work
stops, run `bash install.sh --verify`, which puts the stand-in back and re-checks
the arithmetic.

## Licensing

MusicGen and AudioGen weights are CC-BY-NC 4.0. Anything these scripts write is
non-commercial unless you take that up with Meta.

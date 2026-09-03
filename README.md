# AudioCraft on macOS M1(Max), in one command

Meta's [AudioCraft](https://github.com/facebookresearch/audiocraft) — MusicGen
for music, AudioGen for sound effects, both from a written description — does
not install on a Mac. `pip install audiocraft` fails, and it fails four
different ways depending on how far it gets.

This is one script that gets it working.

```bash
bash install.sh
```

That is the whole thing. It needs no Python you have to pick, no clone of
anything else, and no Node.

---

## Why it does not just install

Four reasons, all of them the same underlying one: it is a 2024 release pinned
to a dependency set that has since decayed.

| pin | what goes wrong |
|---|---|
| `av==11.0.0` | source-only on PyPI, so PyAV compiles and needs pkg-config and the ffmpeg headers |
| `torch==2.1.0`, `torchtext==0.16.0` | no wheels above cp311 |
| `spacy` | no wheels below cp310 — which leaves a window exactly two versions wide |
| `xformers<0.0.23` | **no macOS wheel at any version**, and building it needs torch importable before the build starts |

The first three are version-window problems, and the script solves them by
finding an interpreter in the window — or fetching a standalone 3.11 with
[uv](https://astral.sh/uv) if your machine has none.

The fourth is different in kind, and it is the one that used to make this
impossible rather than merely annoying.

## The xformers stand-in

xformers has never published a macOS wheel — Intel or Apple Silicon, any
release. That was read off PyPI's index rather than recalled. And audiocraft
does not import it conditionally: `transformer.py:23` is a bare
`from xformers import ops` at module scope, so without it, `import audiocraft`
fails outright.

But what audiocraft actually *reaches for* is two functions:

```
unbind                      a faster torch.unbind, same semantics
memory_efficient_attention  attention with a smarter memory schedule
```

Both are **optimisations of operations PyTorch already provides**. So the
script writes a small stand-in supplying the plain versions. The results are
the same; the speed is not. That is the whole trade, and it is a good one on a
machine that would otherwise have no local audio generation at all.

### The half that is easy to miss

Copying a package into `site-packages` does **not** make pip believe it is
installed. pip reads `.dist-info` metadata, not the import system — so without
writing that too, the files sit there unused while pip goes off and compiles
the real xformers anyway. Which looks exactly like the script having done
nothing.

So the stand-in ships with `METADATA`, `WHEEL`, `INSTALLER` and `RECORD`, and
declares version `0.0.22.post7` — a number chosen because audiocraft asks for
`xformers<0.0.23` and this satisfies the resolver. `pip uninstall xformers`
removes it cleanly.

## It refuses early rather than failing deep

No pkg-config and no ffmpeg gets you one line:

```
brew install pkg-config ffmpeg
```

not twenty pages of a PyAV build log with the real cause somewhere in the
middle.

An interpreter outside 3.10–3.11 is refused by name rather than discovered as a
resolver error. And uv is asked directly with `uv python find`, because a
uv-managed build is deliberately **not** on `PATH` — a search that only walks
`PATH` steps straight past one that is already installed.

## It checks its own work

Attention that is subtly wrong **does not raise**. Transpose the heads the
wrong way and every shape still lines up, the model still runs, and what comes
back is audio that sounds like nothing in particular. No error anywhere — just
a feature that quietly does not work.

So the script compares the stand-in's attention against attention written out
longhand in float64, causal and non-causal. Measured disagreement: about
**1e-16**, which is rounding. It also crosses the torch/NumPy bridge once,
because torch built against NumPy 1.x with NumPy 2 installed imports perfectly
and has a dead bridge.

```bash
bash install.sh --generate   # and render a second of audio, end to end
```

## Options

| | |
|---|---|
| `--prefix DIR` | where the environment goes (default `~/.audiocraft`) |
| `--generate` | render one second of audio too, which downloads about 2 GB |
| `--force` | rebuild an environment that already exists |
| `--verify` | skip the install, only check one that exists |

`--verify` is the one worth remembering. The stand-in is a handful of files pip
does not manage, so an unrelated `pip install --upgrade` is exactly the thing
that quietly removes it. Run `--verify` after any upgrade in that environment
and it puts the stand-in back and re-runs the arithmetic.

## Something to run afterwards

`examples/` has three scripts, one per thing audiocraft does. They take the
prompt on the command line and write a `.wav`:

```bash
PY=~/.audiocraft/bin/python

$PY examples/musicgen.py --duration 2 "a single piano chord"   # start here
$PY examples/audiogen.py "rain on a tin roof"
$PY examples/melody.py hummed.m4a "brass band, marching"
```

The first is deliberately tiny — two seconds from the smallest model — because
the first run of any model downloads its weights, and it is better to find a
problem before 6 GB than after. [examples/README.md](examples/README.md) covers
the rest: what each model wants to be asked for, what the downloads cost, and
why it all runs on the CPU no matter what GPU is in the machine.

## Two pins that are load bearing

The script installs `numpy<2` and `transformers<4.56` alongside audiocraft.
Neither is cosmetic, and neither is obvious from the error it prevents:

- **`numpy<2`** — torch 2.1.0's wheels were compiled against NumPy 1.x. With
  NumPy 2 installed torch still imports, but its NumPy bridge silently does not
  initialise, and the failure surfaces much later as something unrelated.
- **`transformers<4.56`** — every version up to 4.55 guards its use of
  `torch.utils._pytree.register_pytree_node` behind a torch ≥ 2.2 check. 4.56
  deleted the guard, and torch 2.1.0 has only the private
  `_register_pytree_node`. The symptom is either *"requires the PyTorch library
  but it was not found"* — which is false, torch is right there — or an
  `AttributeError` halfway through a generation.

Read one version at a time out of the wheels, not recalled.

So: do not `pip install --upgrade numpy transformers` in this environment.

## Where it came from

Extracted from [Soundstage 77](https://github.com/djjkgit/Metube), which does
the same substitution in its own installer. The script is byte-identical to the
copy there, and a test in that repository pins the two together — the stand-in
source, the shim version, and both caps — so this one cannot quietly fall
behind.

Verified on Debian aarch64 (AudioGen loads and generates end to end) and on
macOS (the install completes, which is itself the proof the stand-in works —
the installer only reports success once `import audiocraft` succeeds, and that
import *is* the unguarded `from xformers import ops`).

## Licensing

This script is yours. What it installs is not: AudioCraft's **code** is MIT,
but its **model weights are CC-BY-NC 4.0** — non-commercial. If you are
planning to sell anything made with MusicGen or AudioGen, read Meta's terms
first.

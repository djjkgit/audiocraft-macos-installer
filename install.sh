#!/usr/bin/env bash
#
# audiocraft on macOS, in one command.
#
# Meta's AudioCraft — MusicGen and AudioGen, music and sound effects from a
# written description — is a 2024 release pinned to a dependency set that has
# decayed, and `pip install audiocraft` does not finish on a Mac. Four separate
# reasons, all of them found the hard way:
#
#   av==11.0.0        source-only on PyPI, so PyAV compiles and needs pkg-config
#                     and the ffmpeg headers
#   torch==2.1.0      no wheels above cp311
#   spacy             no wheels below cp310 — a one-version window, 3.10–3.11
#   xformers<0.0.23   no wheel outside x86_64 Linux and Windows, at any version,
#                     and the C++ build wants torch importable before it starts
#
# The first three are version-window problems and this script solves them by
# finding an interpreter in the window. The fourth is different in kind, and it
# is what used to make this impossible rather than merely awkward.
#
# What audiocraft actually reaches for from xformers is two functions — `unbind`
# and `memory_efficient_attention` — and both are optimisations of operations
# PyTorch already provides. So this writes a stand-in supplying the plain
# versions, complete with the `.dist-info` metadata that makes pip believe it is
# installed, *before* pip resolves anything. pip then leaves the real package
# alone and the C++ build never starts.
#
# The results are the same; the speed is not. That is the whole trade, and it is
# a good one on a machine that would otherwise have no local audio generation.
#
# This is the same substitution Soundstage 77 makes in `scripts/setup-tools.mjs`,
# extracted so it can be run on its own — no checkout, no Node, no database.
#
#   curl -fsSL <this file> -o install-audiocraft-macos.sh
#   bash install-audiocraft-macos.sh
#
# Options:
#   --prefix DIR   where the environment goes (default: ~/.audiocraft)
#   --generate     also render one second of audio, which downloads ~2 GB
#   --force        rebuild an environment that is already there
#   --verify       skip the install and only check an environment that exists,
#                  which is what to run after any pip upgrade in it
#
set -eou pipefail

PREFIX="${HOME}/.audiocraft"
GENERATE=0
FORCE=0
VERIFY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix needs a directory}"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    --generate) GENERATE=1; shift ;;
    --force) FORCE=1; shift ;;
    --verify) VERIFY=1; shift ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

SHIM_VERSION='0.0.22.post7'

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
bold 'Checking the machine'

[ "$(uname -s)" = 'Darwin' ] || warn "This is written for macOS; $(uname -s) may still work."
ok "$(uname -s) $(uname -m)"

# PyAV compiles from source at the version audiocraft pins, and its build reads
# the ffmpeg headers through pkg-config. Both missing is the single most common
# way this fails, and it fails deep inside a build log rather than up front.
missing=''
command -v pkg-config >/dev/null 2>&1 || missing="$missing pkg-config"
command -v ffmpeg     >/dev/null 2>&1 || missing="$missing ffmpeg"
if [ -n "$missing" ]; then
  echo
  die "Missing:$missing

PyAV is compiled from source here — audiocraft pins av==11.0.0, which
publishes no wheel — and its build needs the ffmpeg headers through
pkg-config. Install them first:

    brew install pkg-config ffmpeg

Then run this again."
fi
ok 'pkg-config and ffmpeg are here'

# ---------------------------------------------------------------------------
bold 'Finding a Python it will accept'

# Not under --verify: the environment already has an interpreter, and going
# looking for a system one there could fetch a standalone 3.11 nobody asked for.
if [ "$VERIFY" -eq 1 ]; then
  [ -x "$PREFIX/bin/python" ] || die "Nothing to verify at $PREFIX — run without --verify first"
  PYTHON="$PREFIX/bin/python"
  ok "using the one in $PREFIX"
else

# 3.10 or 3.11, and nothing else. Above it torch 2.1.0 and torchtext 0.16.0 have
# no wheels; below it spacy has none. The window is two versions wide and this
# is not a preference.
PYTHON=''
for candidate in python3.11 python3.10; do
  if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$(command -v "$candidate")"; break; fi
done

# Homebrew installs the interpreter but does not always put it on PATH.
if [ -z "$PYTHON" ]; then
  for candidate in /opt/homebrew/bin/python3.11 /usr/local/bin/python3.11 \
                   /opt/homebrew/bin/python3.10 /usr/local/bin/python3.10; do
    [ -x "$candidate" ] && { PYTHON="$candidate"; break; }
  done
fi

# uv's own builds are deliberately *not* on PATH, so a search that only walks
# PATH steps straight past one that is already installed. Ask uv directly.
if [ -z "$PYTHON" ] && command -v uv >/dev/null 2>&1; then
  PYTHON="$(uv python find 3.11 2>/dev/null || true)"
  [ -n "$PYTHON" ] && [ -x "$PYTHON" ] || PYTHON=''
fi

# Still nothing: fetch one. A standalone build in uv's own directory — no root,
# nothing shadowing the system python3, and nothing for anybody to undo later.
if [ -z "$PYTHON" ]; then
  warn 'No Python 3.10 or 3.11 found. Fetching a standalone 3.11 with uv.'
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # The installer puts it here and prints a line about your shell profile,
    # which has not been re-read by this process.
    export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"
  fi
  command -v uv >/dev/null 2>&1 || die 'uv did not install. See https://astral.sh/uv'
  uv python install 3.11
  PYTHON="$(uv python find 3.11)"
fi

[ -n "$PYTHON" ] && [ -x "$PYTHON" ] || die 'No usable Python 3.10 or 3.11'
fi

VERSION="$("$PYTHON" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
case "$VERSION" in
  3.10|3.11) ok "Python $VERSION at $PYTHON" ;;
  *) die "Python $VERSION is outside the 3.10–3.11 window audiocraft's pins allow" ;;
esac

# ---------------------------------------------------------------------------
bold 'Making the environment'

if [ "$VERIFY" -eq 1 ]; then
  [ -x "$PREFIX/bin/python" ] || die "Nothing to verify at $PREFIX — run without --verify first"
  ok "checking the environment already at $PREFIX"
elif [ -d "$PREFIX" ] && [ "$FORCE" -eq 1 ]; then
  echo "  removing $PREFIX"
  rm -rf "$PREFIX"
  "$PYTHON" -m venv "$PREFIX"
  ok "created $PREFIX"
elif [ -x "$PREFIX/bin/python" ]; then
  ok "reusing $PREFIX"
else
  "$PYTHON" -m venv "$PREFIX"
  ok "created $PREFIX"
fi

VENV_PY="$PREFIX/bin/python"
if [ "$VERIFY" -eq 0 ]; then
  "$VENV_PY" -m pip install --quiet --upgrade pip setuptools wheel
  ok 'pip is current'
fi

# ---------------------------------------------------------------------------
bold 'Writing the xformers stand-in'

# Rewritten even under --verify. The stand-in is a handful of files pip does not
# manage, so it is exactly the thing an unrelated upgrade quietly clobbers, and
# putting it back is cheaper than working out whether it needed putting back.

PURELIB="$("$VENV_PY" -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
[ -n "$PURELIB" ] || die "could not find the environment's site-packages"

rm -rf "$PURELIB/xformers" "$PURELIB/xformers-${SHIM_VERSION}.dist-info"
mkdir -p "$PURELIB/xformers"

cat > "$PURELIB/xformers/__init__.py" <<'PY'
"""A stand-in for xformers, which has never published a wheel for this machine.

audiocraft pins `xformers<0.0.23` and imports `xformers.ops` at module scope,
so without something here it cannot be imported at all — and compiling the real
one is a large C++ build that wants torch importable before it starts. Checked
rather than assumed: PyPI has no macOS wheel, Intel or Apple Silicon, across
every release of xformers including the current one.

What audiocraft actually uses from it is two things, and both are
*optimisations* of operations PyTorch itself provides:

  unbind                      a faster torch.unbind, same semantics
  memory_efficient_attention  attention with a smarter memory schedule

So this supplies the plain versions. The results are the same; the speed is
not.

The version below is what makes pip's resolver leave the real package alone:
audiocraft asks for `xformers<0.0.23` and this satisfies it.
"""
from . import ops  # noqa: F401

__version__ = '0.0.22.post7'
PY

cat > "$PURELIB/xformers/ops.py" <<'PY'
"""The two entry points audiocraft reaches for. See `__init__.py` for why."""
import torch
import torch.nn.functional as F


class LowerTriangularMask:
    """Causal masking. xformers passes an instance; the type is the signal."""


def unbind(x, dim=0):
    """xformers' unbind is a faster torch.unbind with identical semantics."""
    return torch.unbind(x, dim)


def memory_efficient_attention(query, key, value, attn_bias=None, p=0.0, scale=None):
    """Scaled dot-product attention, in xformers' layout.

    xformers takes [B, M, H, K]; PyTorch's fused kernel takes [B, H, M, K], so
    the heads are swapped in and back out. `scaled_dot_product_attention` picks
    a flash or memory-efficient backend itself, so this is the same idea
    reached through a different door rather than a naive fallback.
    """
    q, k, v = (t.transpose(1, 2) for t in (query, key, value))
    is_causal = isinstance(attn_bias, LowerTriangularMask) or attn_bias is LowerTriangularMask
    mask = None if (attn_bias is None or is_causal) else attn_bias
    out = F.scaled_dot_product_attention(
        q, k, v, attn_mask=mask, dropout_p=p, is_causal=is_causal, scale=scale)
    return out.transpose(1, 2)
PY

# The metadata is the half that matters, and the half that is easy to skip.
#
# Copying a package into site-packages does not make pip believe it is
# installed: pip reads `.dist-info` directories, not the import system. Without
# this the files sit there unused while pip goes off and compiles the real
# xformers anyway — which is the exact failure this script exists to prevent,
# arriving in a form that looks like the script did nothing.
#
# RECORD lists what was written so `pip uninstall xformers` can remove it again.
# Hashes are optional in the format and omitted: they exist to detect tampering
# with a downloaded wheel, and nothing was downloaded.
DIST="$PURELIB/xformers-${SHIM_VERSION}.dist-info"
mkdir -p "$DIST"
cat > "$DIST/METADATA" <<META
Metadata-Version: 2.1
Name: xformers
Version: ${SHIM_VERSION}
Summary: Stand-in for xformers, which publishes no wheel for this platform
META
cat > "$DIST/WHEEL" <<'META'
Wheel-Version: 1.0
Generator: install-audiocraft-macos
Root-Is-Purelib: true
Tag: py3-none-any
META
echo 'install-audiocraft-macos' > "$DIST/INSTALLER"
{
  echo 'xformers/__init__.py,,'
  echo 'xformers/ops.py,,'
  echo "xformers-${SHIM_VERSION}.dist-info/METADATA,,"
  echo "xformers-${SHIM_VERSION}.dist-info/WHEEL,,"
  echo "xformers-${SHIM_VERSION}.dist-info/INSTALLER,,"
  echo "xformers-${SHIM_VERSION}.dist-info/RECORD,,"
} > "$DIST/RECORD"

"$VENV_PY" -m pip show xformers >/dev/null 2>&1 \
  || die 'pip does not see the stand-in — it would try to build the real one'
ok "pip reports xformers ${SHIM_VERSION} installed"

# ---------------------------------------------------------------------------
if [ "$VERIFY" -eq 1 ]; then
  bold 'Skipping the install'
  ok 'checking what is already here'
else
bold 'Installing audiocraft'
echo '  This is gigabytes and compiles PyAV. Ten minutes is normal.'
echo

# Two caps beyond audiocraft's own pins, both found by watching this fail:
#
#   numpy<2          torch 2.1.0's wheels are built against NumPy 1.x. With
#                    NumPy 2 installed torch still imports, but its NumPy
#                    bridge is dead — "_ARRAY_API not found" — and the failure
#                    surfaces much later as something unrelated.
#
#   transformers<4.56  every version up to 4.55 guards its use of
#                    `torch.utils._pytree.register_pytree_node` behind a
#                    torch>=2.2 check. 4.56 removed the guard, and torch 2.1.0
#                    has only the private `_register_pytree_node`. The symptom
#                    is either "requires the PyTorch library but it was not
#                    found" or an AttributeError halfway through a generation.
"$VENV_PY" -m pip install --upgrade --upgrade-strategy only-if-needed \
  audiocraft 'numpy<2' 'transformers<4.56'
fi

# ---------------------------------------------------------------------------
bold 'Checking it'

# Importing audiocraft is itself the test of the substitution: the unguarded
# `from xformers import ops` at transformer.py:23 is what used to be the wall.
"$VENV_PY" - <<'PY'
import sys
import audiocraft
from audiocraft.models import AudioGen, MusicGen  # noqa: F401
print(f"  \033[32m✓\033[0m audiocraft {audiocraft.__version__} imports, AudioGen and MusicGen included")

import torch, numpy, transformers
print(f"  \033[32m✓\033[0m torch {torch.__version__}, numpy {numpy.__version__}, transformers {transformers.__version__}")

# torch built against NumPy 1.x with NumPy 2 installed imports fine and has a
# dead NumPy bridge. Crossing it once here is the whole check.
try:
    torch.from_numpy(numpy.zeros(4, dtype="float32")).numpy()
    print("  \033[32m✓\033[0m torch and numpy agree")
except Exception as e:
    sys.exit(f"  torch cannot talk to numpy: {e}")

# The one that matters, because attention that is subtly wrong does not raise.
# Transpose the heads the wrong way and every shape still lines up, the model
# still runs, and what comes back is audio that sounds like nothing in
# particular. Compared against attention written out longhand in float64.
import xformers.ops as xops

torch.manual_seed(7)
B, M, H, K = 2, 6, 3, 8
q, k, v = (torch.randn(B, M, H, K, dtype=torch.float64) for _ in range(3))

def longhand(q, k, v, causal):
    q, k, v = (t.transpose(1, 2) for t in (q, k, v))
    scores = q @ k.transpose(-2, -1) / (K ** 0.5)
    if causal:
        m = torch.ones(M, M, dtype=torch.bool).tril()
        scores = scores.masked_fill(~m, float("-inf"))
    return (scores.softmax(-1) @ v).transpose(1, 2)

for causal in (False, True):
    bias = xops.LowerTriangularMask() if causal else None
    got = xops.memory_efficient_attention(q, k, v, attn_bias=bias)
    want = longhand(q, k, v, causal)
    err = (got - want).abs().max().item()
    if err > 1e-9:
        sys.exit(f"  the stand-in's attention disagrees by {err:.2e} (causal={causal})")
    print(f"  \033[32m✓\033[0m attention matches longhand float64 to {err:.1e} (causal={causal})")

# Element by element, because `!=` on two tuples of tensors asks each pair for
# a truth value and a multi-element tensor refuses to give one. Comparing them
# the obvious way raises rather than answers.
mine, theirs = xops.unbind(q, 1), torch.unbind(q, 1)
if len(mine) != len(theirs) or any(not torch.equal(a, b) for a, b in zip(mine, theirs)):
    sys.exit("  unbind disagrees with torch.unbind")
print("  \033[32m✓\033[0m unbind matches torch.unbind")
PY

if [ "$GENERATE" -eq 1 ]; then
  bold 'Rendering one second, end to end'
  echo '  The first run downloads about 2 GB of weights.'
  "$VENV_PY" - <<'PY'
import warnings, tempfile, os
warnings.filterwarnings("ignore")
from audiocraft.models import AudioGen
from audiocraft.data.audio import audio_write

model = AudioGen.get_pretrained("facebook/audiogen-medium")
model.set_generation_params(duration=1)
wav = model.generate(["a door closing"], progress=True)
stem = os.path.join(tempfile.mkdtemp(), "proof")
audio_write(stem, wav[0].cpu(), model.sample_rate, strategy="loudness", loudness_compressor=True)
print(f"  \033[32m✓\033[0m wrote {stem}.wav")
PY
fi

# ---------------------------------------------------------------------------
echo
bold 'Done'
cat <<DONE

  Use it directly:

      $PREFIX/bin/python -c 'from audiocraft.models import AudioGen'

  Or point Soundstage 77 at it, if that is why you are here — it looks for
  an environment at .tools/venvs/audiocraft in the checkout, so either
  symlink this one there or run \`npm run setup:tools -- --only=audiocraft\`,
  which does all of the above inside the project.

  Two things worth knowing. The stand-in is faster to break than to notice:
  if you ever \`pip install --upgrade xformers\` in this environment, pip will
  replace it with a source build that cannot finish. And the pins are load
  bearing — \`pip install --upgrade numpy transformers\` here will take numpy
  past 2 and transformers past 4.55, and audiocraft stops working.

DONE

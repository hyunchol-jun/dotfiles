#!/bin/sh
# Isolated local runtime; model weights stay outside the dotfiles repository.
set -eu
PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/opt/usr/bin:/usr/local/bin"
export PATH
command -v uv >/dev/null || { echo 'Install uv first: https://docs.astral.sh/uv/getting-started/installation/' >&2; exit 1; }
DATA_DIR="$HOME/.local/share/docs-to-audio"
if [ ! -x "$DATA_DIR/venv/bin/python" ]; then
  uv venv --python 3.12 "$DATA_DIR/venv"
fi
uv pip install --python "$DATA_DIR/venv/bin/python" 'kokoro-onnx==0.6.1' 'soundfile==0.14.0'
"$DATA_DIR/venv/bin/python" - <<'PY'
from pathlib import Path
from urllib.request import urlopen
import shutil
import hashlib
root = Path.home()/'.local/share/docs-to-audio/models'
root.mkdir(parents=True, exist_ok=True)
base = 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/'
checksums = {'kokoro-v1.0.onnx': 'beb0d1848dee9a49da392cc3df26958d46cfa35d321edf434f52949153f0df3a', 'voices-v1.0.bin': 'bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d'}
for name, expected in checksums.items():
    dest = root/name
    if dest.is_file() and hashlib.sha256(dest.read_bytes()).hexdigest() == expected:
        continue
    print('Downloading', name, flush=True)
    partial = dest.with_suffix(dest.suffix + '.partial')
    with urlopen(base + name, timeout=120) as response, partial.open('wb') as output:
        shutil.copyfileobj(response, output)
    if hashlib.sha256(partial.read_bytes()).hexdigest() != expected:
        raise SystemExit(f'Checksum mismatch: {name}')
    partial.replace(dest)
import onnxruntime as ort
ort.disable_telemetry_events()
from kokoro_onnx import Kokoro
engine = Kokoro(str(root/'kokoro-v1.0.onnx'), str(root/'voices-v1.0.bin'))
assert 'af_heart' in engine.get_voices()
print('Kokoro ready. Default voice: af_heart. Runtime:', root.parent/'venv/bin/python')
PY

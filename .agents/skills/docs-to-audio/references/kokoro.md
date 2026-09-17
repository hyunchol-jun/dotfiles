# Local Kokoro

Run once on each machine:

```bash
sh <skill-dir>/scripts/setup_kokoro.sh
```

Requires `uv`; installs a Python 3.12 virtual environment in `~/.local/share/docs-to-audio/venv` and downloads approximately 338 MB of model/voice files to its sibling `models/` directory. Downloads use fixed release URLs and SHA-256 validation. No model files or environments belong in Git. Rendering subsequently uses local files and requires no API key or paid service. `ffmpeg` and `ffprobe` must also be installed; the renderer searches common Homebrew prefixes.

The runtime pins `kokoro-onnx` and `soundfile`. The upstream wrapper splits long input into phoneme batches. The renderer normalizes chapter WAVs before joining them and creates separate MP3s plus `combined.mp3` and a timing index.

English voices to audition:

- `af_heart`: American female (default).
- `am_michael`: American male.
- `bf_emma`: British female; select `--lang en-gb`.

Use `--speed 0.9` for slower narration or `--speed 1.1` for faster narration; valid range is 0.5–2.0. `--rate` controls only the Mac `say` backend. This integration intentionally exposes only US/UK English; do not translate other-language documents implicitly or assume other phonemizer languages are trained Kokoro languages.

Sources:
- Model and license: https://huggingface.co/hexgrad/Kokoro-82M
- ONNX runtime wrapper and model releases: https://github.com/thewh1teagle/kokoro-onnx
- Voice catalog: https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md

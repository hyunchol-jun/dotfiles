#!/usr/bin/env python3
"""Render reviewed chapter scripts with local Kokoro or macOS say and ffmpeg."""
import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path


def run(args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def duration(path):
    value = float(run(['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
                       '-of', 'default=noprint_wrappers=1:nokey=1', str(path)]))
    if not value > 0:
        raise ValueError(f'Empty audio: {path}')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--backend', choices=['kokoro', 'say'], default='kokoro')
    parser.add_argument('--voice')
    parser.add_argument('--speed', type=float, default=1.0, help='Kokoro speed, 0.5 to 2.0')
    parser.add_argument('--lang', choices=['en-us', 'en-gb'], default='en-us')
    parser.add_argument('--models', type=Path, default=Path.home()/'.local/share/docs-to-audio/models')
    parser.add_argument('--rate', type=int, default=175, help='Words per minute')
    args = parser.parse_args()
    if args.rate <= 0:
        parser.error('--rate must be positive')
    if not 0.5 <= args.speed <= 2.0:
        parser.error('--speed must be between 0.5 and 2.0')
    os.environ['PATH'] += os.pathsep + '/opt/homebrew/bin:/opt/usr/bin:/usr/local/bin'
    for tool in (('say',) if args.backend == 'say' else ()) + ('ffmpeg', 'ffprobe'):
        if not shutil.which(tool):
            parser.error(f'Required executable missing: {tool}')
    manifest = args.manifest.resolve()
    data = json.loads(manifest.read_text(encoding='utf-8'))
    chapters = data['chapters']
    if not isinstance(chapters, list) or not chapters:
        parser.error('Manifest needs a nonempty chapters list')
    inputs = []
    for chapter in chapters:
        source = (manifest.parent / chapter['text_file']).resolve()
        if not source.read_text(encoding='utf-8').strip():
            parser.error(f'Empty narration: {source}')
        if not isinstance(chapter['title'], str) or not chapter['title'].strip():
            parser.error('Every chapter needs a title')
        inputs.append(source)
    engine = None
    if args.backend == 'kokoro':
        try:
            import onnxruntime as ort
            # Avoid telemetry background work and its macOS shutdown race.
            ort.disable_telemetry_events()
            from kokoro_onnx import Kokoro
            import soundfile as sf
        except ImportError:
            parser.error('Run setup_kokoro.sh, then use ~/.local/share/docs-to-audio/venv/bin/python')
        engine = Kokoro(str(args.models/'kokoro-v1.0.onnx'), str(args.models/'voices-v1.0.bin'))
        args.voice = args.voice or ('af_heart' if args.lang == 'en-us' else 'bf_emma')
        if args.voice not in engine.get_voices():
            parser.error('Unknown voice. Available: ' + ', '.join(engine.get_voices()))
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    entries = []
    elapsed = 0.0
    for number, (chapter, source) in enumerate(zip(chapters, inputs), 1):
        stem = f'{number:03d}'
        raw = out / f'{stem}.aiff'
        wav = out / f'{stem}.wav'
        mp3 = out / f'{stem}.mp3'
        if engine is not None:
            raw = out / f'{stem}-raw.wav'
            samples, sample_rate = engine.create(
                source.read_text(encoding='utf-8'), voice=args.voice,
                speed=args.speed, lang=args.lang)
            sf.write(str(raw), samples, sample_rate)
        else:
            command = ['say', '-r', str(args.rate), '-f', str(source), '-o', str(raw)]
            if args.voice:
                command.extend(['-v', args.voice])
            run(command)
        run(['ffmpeg', '-v', 'error', '-nostdin', '-i', str(raw),
             '-ar', '44100', '-ac', '1', '-c:a', 'pcm_s16le', str(wav)])
        run(['ffmpeg', '-v', 'error', '-nostdin', '-i', str(wav),
             '-c:a', 'libmp3lame', '-b:a', '128k', str(mp3)])
        seconds = duration(wav)
        duration(mp3)
        entries.append({'title': chapter['title'], 'file': mp3.name,
                        'script': str(source), 'start_seconds': round(elapsed, 3),
                        'duration_seconds': round(seconds, 3)})
        elapsed += seconds
        raw.unlink()
    concat = out / 'concat.txt'
    concat.write_text(''.join(f"file '{i:03d}.wav'\n" for i in range(1, len(entries)+1)))
    combined = out / 'combined.mp3'
    run(['ffmpeg', '-v', 'error', '-nostdin', '-f', 'concat', '-safe', '1',
         '-i', str(concat), '-c:a', 'libmp3lame', '-b:a', '128k', str(combined)])
    total = duration(combined)
    index = {'title': data.get('title', manifest.stem), 'backend': args.backend,
             'voice': args.voice or 'system default',
             'rate': args.rate if args.backend == 'say' else None,
             'speed': args.speed if engine else None, 'language': args.lang if engine else None,
             'duration_seconds': total, 'chapters': entries}
    (out / 'index.json').write_text(json.dumps(index, indent=2, ensure_ascii=False)+'\n')
    for number in range(1, len(entries)+1):
        (out / f'{number:03d}.wav').unlink()
    concat.unlink()
    print(json.dumps({'audio': str(combined), 'chapters': len(entries),
                      'duration_seconds': total}))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr if isinstance(error, subprocess.CalledProcessError) else str(error)
        raise SystemExit(f'Rendering failed: {detail}')

#!/usr/bin/env python3
"""End to end test for the XTTS service (voice cloning).

What it does:
  1. Connects to Gradio at http://127.0.0.1:7861
  2. Calls /predict with a short text and a reference WAV
  3. Validates that a non empty WAV came back
  4. Reports generation time

Exits 0 on success, 1 on failure.
"""

import argparse
import os
import shutil
import sys
import time
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=os.environ.get("XTTS_URL", "http://127.0.0.1:7861"))
    parser.add_argument(
        "--text",
        default="Quick brown fox jumps over the lazy dog. Voice cloning test on Apple GPU.",
    )
    parser.add_argument("--language", default="en")
    parser.add_argument(
        "--ref-audio",
        default=os.environ.get("XTTS_REF_AUDIO", str(Path.home() / "pinokio/api/xtts.pinokio.git/examples/female.wav")),
        help="Reference WAV used for cloning. Defaults to the female sample shipped with XTTS.",
    )
    parser.add_argument("--out", default="test-output.wav")
    parser.add_argument("--min-bytes", type=int, default=10_000, help="WAVs smaller than this fail the test")
    args = parser.parse_args()

    try:
        from gradio_client import Client, handle_file
    except ImportError:
        print("ERROR: gradio_client not installed. Use the Pinokio venv Python.", file=sys.stderr)
        return 1

    if not Path(args.ref_audio).exists():
        print(f"ERROR: reference audio not found: {args.ref_audio}", file=sys.stderr)
        return 1

    print(f"-> connecting to {args.url}")
    try:
        client = Client(args.url, verbose=False)
    except Exception as e:
        print(f"ERROR: could not connect: {e}", file=sys.stderr)
        return 1

    print(f"-> generating audio (lang={args.language}, ref={args.ref_audio}, {len(args.text)} chars)")
    t0 = time.perf_counter()
    try:
        result = client.predict(
            prompt=args.text,
            language=args.language,
            audio_file_pth=handle_file(args.ref_audio),
            agree=True,
            api_name="/predict",
        )
    except Exception as e:
        print(f"ERROR during call: {e}", file=sys.stderr)
        return 1
    elapsed = time.perf_counter() - t0

    # /predict returns (waveform_video, audio_filepath)
    if not result or len(result) < 2 or not result[1]:
        print(f"ERROR: response had no audio. result={result!r}", file=sys.stderr)
        return 1

    src = Path(result[1])
    if not src.exists():
        print(f"ERROR: returned audio file does not exist: {src}", file=sys.stderr)
        return 1

    size = src.stat().st_size
    if size < args.min_bytes:
        print(f"ERROR: WAV too small ({size} bytes < {args.min_bytes})", file=sys.stderr)
        return 1

    dest = Path(args.out).resolve()
    shutil.copy(src, dest)

    print()
    print(f"  OK audio:      {dest}")
    print(f"  OK size:       {size:,} bytes")
    print(f"  OK time:       {elapsed:.2f}s")
    if elapsed > 0:
        chars_per_sec = len(args.text) / elapsed
        print(f"  OK throughput: {chars_per_sec:.1f} chars/s")
    return 0


if __name__ == "__main__":
    sys.exit(main())

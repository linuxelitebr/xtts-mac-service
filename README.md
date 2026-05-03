# xtts-mac-service

Runs [Coqui XTTS v2](https://huggingface.co/coqui/XTTS-v2) as a service on macOS, on the Apple GPU (MPS), without needing Pinokio open in the background.

Sister project of [kokoro-tts-mac-service](https://github.com/linuxelitebr/kokoro-tts-mac-service). Same shape, different model. Kokoro is fixed-voice and fast; XTTS does voice cloning from a 3 to 30 second sample.

## Why this exists

The Pinokio app for XTTS works, but:

* The upstream `app.py` has a literal `device = "cpu"  # mps doesn't work yet` line. That comment is years old; MPS works fine today with the right fallback flag.
* It binds to port 7860, which collides with Kokoro. You can only run one at a time.
* Pinokio has to stay open for the service to be reachable.

This repo fixes all three with a small patch (MPS detection, port moves to 7861, plus a `torch.load` shim for PyTorch 2.6+ compatibility) and a LaunchAgent that boots at login and self-restarts on crash.

## What you get

* XTTS at `http://127.0.0.1:7861`, 24/7.
* Inference on the Apple GPU. Roughly 2x faster than CPU on Apple Silicon after warmup. Less dramatic than Kokoro because several Coqui TTS ops still fall back to CPU, but every bit helps when each call is heavy.
* Co-exists with Kokoro on 7860. Run both, address each by its own URL.
* Auto-restart if the process crashes.

## Before you start

1. **macOS** (tested on Sequoia, Apple Silicon).
2. **Pinokio + the XTTS app installed once.** This repo piggybacks on the venv that Pinokio set up. No Pinokio? Grab it from [pinokio.computer](https://pinokio.computer), install Coqui XTTS once, then come back.
3. Point at a different install via `XTTS_DIR=...`.

## Install

```bash
git clone https://github.com/linuxelitebr/xtts-mac-service.git
cd xtts-mac-service
./scripts/install.sh
```

The installer will:

1. Check the venv has `torch`, `gradio`, `TTS`.
2. Patch `app.py` (MPS + port 7861 + torch.load shim, with an automatic backup).
3. Render `com.xtts.tts.plist` with your real paths, drop it in `~/Library/LaunchAgents/`.
4. Load the LaunchAgent and wait for Gradio to answer on :7861.

Heads up: first boot can take a couple of minutes if the 1.87 GB XTTS v2 model isn't in your Coqui cache yet (`~/Library/Application Support/tts/`). After that, boot is just model-to-MPS and is much faster.

## Use it

### From the browser

Open `http://127.0.0.1:7861`. Tick the Coqui ToS checkbox (CPML license), upload a 3 to 30s reference WAV, type your prompt, generate.

### From Python

```python
from gradio_client import Client, handle_file

c = Client("http://127.0.0.1:7861")
waveform_video, audio_path = c.predict(
    prompt="Hello in my own voice, generated on the Apple GPU.",
    language="en",
    audio_file_pth=handle_file("path/to/your/voice-sample.wav"),
    agree=True,
    api_name="/predict",
)
print(audio_path)
```

`audio_file_pth` should be a clean WAV of your voice, ideally 6 to 30 seconds, mono, 22kHz or 24kHz. Background noise hurts quality.

### Languages

XTTS v2 supports: en, es, fr, de, it, pt, pl, tr, ru, nl, cs, ar, zh-cn, ja, ko, hu, hi.

## Day to day

| Thing       | Command                  | What it does                                                  |
|:------------|:-------------------------|:--------------------------------------------------------------|
| Start       | `./scripts/start.sh`     | Idempotent. Loads the agent if needed, waits for HTTP. Returns 0 instantly if already up. |
| Stop        | `./scripts/stop.sh`      | Unloads the agent for this session. Comes back at next login. |
| Status      | `./scripts/status.sh`    | Plist + LaunchAgent + HTTP, all in one screen.                |
| Tail stdout | `tail -f logs/xtts.out.log` |                                                            |
| Tail stderr | `tail -f logs/xtts.err.log` |                                                            |

`start.sh` is built for hooks: returns in milliseconds when the service is already up, and only does work when it isn't.

```bash
# Make sure both engines are alive before generating
QUIET=1 ~/path/to/kokoro-tts-mac-service/scripts/start.sh || exit 1
QUIET=1 ~/path/to/xtts-mac-service/scripts/start.sh || exit 1
./generate_tts.sh
```

## Tests

```bash
./scripts/test.sh
```

Runs four checks: launchd state, MPS in logs, HTTP, and an end to end voice cloning call using `examples/female.wav` (or whatever `XTTS_REF_AUDIO` points at).

```bash
XTTS_REF_AUDIO=/path/to/your-voice.wav ./scripts/test.sh
```

## How it works

### The patch

The patch does three things to `app.py`:

**1. Switches CPU to MPS**

```python
elif torch.backends.mps.is_available():
    device = "mps"
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
```

`PYTORCH_ENABLE_MPS_FALLBACK=1` lets ops without an MPS kernel quietly run on CPU. Coqui TTS has several of those.

**2. Drops `torch.set_default_device(device)`**

Upstream sets the default device globally so every tensor allocation lands there. With MPS that breaks helper ops inside the TTS lib that assume CPU. Just moving the model with `tts.to(device)` is enough.

**3. Restores `torch.load` to `weights_only=False`**

PyTorch 2.6+ flipped the default of `torch.load` from `weights_only=False` to `True`. Coqui TTS hasn't been updated and its checkpoints fail to load. We monkey-patch `torch.load` to default back to `False` before importing TTS. Safe because we trust the official Coqui weights.

**4. Binds to 7861**

So Kokoro can keep 7860.

Full diff in [`patches/01-mps-and-port.patch`](patches/01-mps-and-port.patch).

### The LaunchAgent

Same shape as the Kokoro one: `~/Library/LaunchAgents/com.xtts.tts.plist`, `RunAtLoad=true`, `KeepAlive` only on crash, `ThrottleInterval=10`, `PYTHONUNBUFFERED=1` so logs flush in real time, plus `COQUI_TOS_AGREED=1` to mirror what Pinokio does.

## Uninstall

```bash
./scripts/uninstall.sh           # just unloads the service
./scripts/uninstall.sh --revert  # also undoes the patch in app.py
```

## Heads up

* **First call after a cold boot is slow** because the model has to load to MPS. Subsequent calls are roughly 2x faster than CPU.
* **Voice quality** depends a lot on the reference clip. A clean 10 to 30s mono WAV beats a noisy 3s sample every time.
* **Coqui Public Model License** applies to the XTTS weights themselves (this repo only ships the wrapper code, which is MIT). See [coqui.ai/cpml](https://coqui.ai/cpml).
* **Containers on Mac can't see the Apple GPU.** That's why this repo is intentionally native.

## Credits

* Model: [coqui/XTTS-v2](https://huggingface.co/coqui/XTTS-v2)
* Original app: [Coqui XTTS Pinokio script](https://github.com/cocktailpeanut/xtts.pinokio)

## License

MIT for the wrapper code (this repo). XTTS weights are CPML.
See [LICENSE](LICENSE).

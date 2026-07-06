"""MiniPrem Host Helper — a small localhost-only privileged agent the kiosk calls
for the two things the browser/containers can't do themselves:

  1. Audio device control (PulseAudio/PipeWire via `pactl`) — list output/input
     devices and set the system DEFAULT, so the digital human's voice (which plays
     in the cross-origin UneeQ SDK iframe and therefore follows the OS default)
     routes to the device chosen in the kiosk Audio tab.

  2. NIM model install (Docker + NGC) — pull a model image by name with progress,
     list installed NIM images, and (optionally) swap the served LLM.

SECURITY: bind to 127.0.0.1 only. It is reached from the kiosk via the kiosk's
nginx `/host-admin/` proxy (same-origin). Runs on the box with:
  - the Docker socket (for `docker pull` / image list / swap), and
  - the kiosk user's PulseAudio socket (for `pactl`).
Both are privileged; the deploy script documents exactly what's mounted.

Endpoints:
  GET  /health
  GET  /audio/devices                      -> { sinks:[...], sources:[...], default_sink, default_source }
  POST /audio/default  {sink?, source?}     -> set default output/input
  GET  /models                              -> installed NIM images
  POST /models/pull   {image}               -> start an NGC pull (background)
  GET  /models/pull/status                  -> { state, image, log_tail }
"""
from __future__ import annotations

import os
import re
import json
import time
import subprocess
import threading
from typing import Optional

# When a model switch/activation starts we record its timestamp here, so /llm/status
# can report ELAPSED seconds (the kiosk shows a live "loading for 42s" counter) and the
# UI can tell a slow-but-progressing load apart from a stuck one.
_SWITCH_STARTED: dict = {}

from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel

app = FastAPI(title="MiniPrem Host Helper", version="0.1.0")

# --------------------------------------------------------------------------- #
# Audio (pactl)
# --------------------------------------------------------------------------- #

def _pactl(*args: str) -> str:
    env = dict(os.environ)
    # Honor a kiosk-user PulseAudio server if provided by the deploy script.
    return subprocess.run(["pactl", *args], capture_output=True, text=True, timeout=8, env=env).stdout


def _descriptions(kind: str) -> dict:
    # `pactl list sinks|sources` (long form) pairs each Name: with a friendly
    # Description: — map name -> description so the kiosk can show clean labels.
    out = _pactl("list", kind)
    desc: dict[str, str] = {}
    cur_name = None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("Name:"):
            cur_name = s.split("Name:", 1)[1].strip()
        elif s.startswith("Description:") and cur_name:
            desc[cur_name] = s.split("Description:", 1)[1].strip()
            cur_name = None
    return desc


def _list(kind: str) -> list[dict]:
    # `pactl list short sinks|sources` -> "<id>\t<name>\t<driver>\t<spec>\t<state>"
    out = _pactl("list", "short", kind)
    descs = _descriptions(kind)
    devs = []
    for line in out.strip().splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            # Skip PulseAudio/PipeWire monitor sources — they're a loopback of an
            # OUTPUT, not a real capture device (mic / line-in / USB mic). Listing
            # "Monitor of …" as a microphone is misleading on a kiosk.
            if kind == "sources" and parts[1].endswith(".monitor"):
                continue
            devs.append({"id": parts[0], "name": parts[1], "state": parts[-1],
                         "description": descs.get(parts[1], "")})
    return devs


def _default(kind: str) -> str:
    info = _pactl("info")
    key = "Default Sink:" if kind == "sink" else "Default Source:"
    for line in info.splitlines():
        if line.startswith(key):
            return line.split(":", 1)[1].strip()
    return ""


def _volume(target: str) -> Optional[int]:
    # target = sink|source. `pactl get-<t>-volume @DEFAULT_<T>@` -> "... 65% ..."
    try:
        out = _pactl(f"get-{target}-volume", f"@DEFAULT_{target.upper()}@")
        import re
        m = re.search(r"(\d+)%", out)
        return int(m.group(1)) if m else None
    except Exception:
        return None


def _muted(target: str) -> Optional[bool]:
    try:
        out = _pactl(f"get-{target}-mute", f"@DEFAULT_{target.upper()}@")
        return "yes" in out.lower()
    except Exception:
        return None


def _available_source_names() -> set:
    """Source names with a usable (plugged-in) input — at least one port marked
    available, or no port info at all (some USB mics). Lets the kiosk hide the
    onboard analog jack when nothing is plugged in, so the mic list shows only real,
    connected microphones (USB / analog mic / line-in), like Zoom/Teams effectively
    do — but with jack-presence so an empty kiosk reads clean."""
    try:
        out = _pactl("list", "sources")
    except Exception:
        return set()
    avail: set = set()
    name = None
    saw_port = False
    has_avail = False
    def flush():
        nonlocal name, saw_port, has_avail
        if name is not None and ((not saw_port) or has_avail):
            avail.add(name)
        name, saw_port, has_avail = None, False, False
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("Source #"):
            flush()
        elif s.startswith("Name:"):
            name = s.split(":", 1)[1].strip()
        elif "priority:" in s and "available" in s.lower():
            saw_port = True
            if "available: yes" in s.lower():
                has_avail = True
    flush()
    return avail


@app.get("/audio/devices")
def audio_devices():
    try:
        avail = _available_source_names()
        # Only real, CONNECTED mics: _list already drops monitors; here we also drop
        # inputs whose jack is empty (no available port — e.g. the onboard analog
        # mic/line-in jack with nothing plugged in). Empty list = no mic connected.
        sources = [s for s in _list("sources") if s["name"] in avail]
        default_source = _default("source")
        # Default capture may be a monitor or an unplugged jack — point at the first
        # real, available input instead.
        if default_source.endswith(".monitor") or default_source not in {s["name"] for s in sources}:
            default_source = sources[0]["name"] if sources else ""
        return {
            "sinks": _list("sinks"),
            "sources": sources,
            "default_sink": _default("sink"),
            "default_source": default_source,
            # Current volume (%) + mute of the default output/input, so the kiosk
            # can render sliders + mute toggles for the digital-human voice & mic.
            "sink_volume": _volume("sink"),
            "sink_muted": _muted("sink"),
            "source_volume": _volume("source"),
            "source_muted": _muted("source"),
        }
    except Exception as exc:
        raise HTTPException(500, f"pactl failed (PulseAudio not reachable?): {exc}")


class AudioDefault(BaseModel):
    sink: Optional[str] = None
    source: Optional[str] = None


@app.post("/audio/default")
def set_audio_default(body: AudioDefault):
    done = {}
    if body.sink:
        _pactl("set-default-sink", body.sink); done["sink"] = body.sink
    if body.source:
        _pactl("set-default-source", body.source); done["source"] = body.source
    if not done:
        raise HTTPException(400, "provide 'sink' and/or 'source'")
    return {"ok": True, "set": done}


class AudioVolume(BaseModel):
    target: str            # "sink" (output) | "source" (input/mic gain)
    percent: int           # 0..150


@app.post("/audio/volume")
def set_audio_volume(body: AudioVolume):
    if body.target not in ("sink", "source"):
        raise HTTPException(400, "target must be 'sink' or 'source'")
    pct = max(0, min(150, int(body.percent)))
    _pactl(f"set-{body.target}-volume", f"@DEFAULT_{body.target.upper()}@", f"{pct}%")
    return {"ok": True, "target": body.target, "percent": pct}


class AudioMute(BaseModel):
    target: str            # "sink" | "source"
    mute: bool


@app.post("/audio/mute")
def set_audio_mute(body: AudioMute):
    if body.target not in ("sink", "source"):
        raise HTTPException(400, "target must be 'sink' or 'source'")
    _pactl(f"set-{body.target}-mute", f"@DEFAULT_{body.target.upper()}@", "1" if body.mute else "0")
    return {"ok": True, "target": body.target, "muted": body.mute}


# --------------------------------------------------------------------------- #
# NIM model install (docker)
# --------------------------------------------------------------------------- #

_pull = {"state": "idle", "image": "", "log": [], "pct": 0, "done_gb": 0.0, "total_gb": 0.0}
_pull_lock = threading.Lock()


def _docker(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["docker", *args], capture_output=True, text=True, timeout=20)


# Image pull works on BOTH runtimes: docker uses `docker pull`; kubeadm/containerd
# uses `nerdctl -n k8s.io pull` against the node's containerd socket (mounted into
# this pod) so the pulled NIM image lands in the SAME namespace the kubelet/NIM
# uses. Auth for nvcr.io comes from the ngc-registry-credentials docker config
# mounted at /root/.docker/config.json.
def _pull_cmd(image: str) -> list:
    return ["docker", "pull", image] if _runtime() == "docker" else \
           ["nerdctl", "-n", "k8s.io", "pull", image]


def _img_list_cmd() -> list:
    return ["docker", "images", "--format", "{{.Repository}}:{{.Tag}}"] if _runtime() == "docker" else \
           ["nerdctl", "-n", "k8s.io", "images", "--format", "{{.Repository}}:{{.Tag}}"]


@app.get("/models")
def list_models():
    try:
        r = subprocess.run(_img_list_cmd(), capture_output=True, text=True, timeout=20)
        imgs = [l for l in r.stdout.strip().splitlines() if "nim" in l.lower() or "nvcr.io" in l.lower()]
        return {"images": imgs}
    except Exception:
        return {"images": []}


class PullReq(BaseModel):
    image: str


_UNIT = {"B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12,
         "KIB": 2**10, "MIB": 2**20, "GIB": 2**30, "TIB": 2**40}
# Per-layer progress: "<id>: ... 1.2 GiB / 5.0 GiB" (nerdctl) or "1.2GB/5GB" (docker).
_SIZE_RE = re.compile(r"([\d.]+)\s*([KMGT]?i?B)\s*/\s*([\d.]+)\s*([KMGT]?i?B)", re.I)


def _to_bytes(v: str, u: str) -> float:
    try:
        return float(v) * _UNIT.get(u.upper(), 1)
    except Exception:
        return 0.0


def _do_pull(image: str):
    with _pull_lock:
        _pull.update(state="pulling", image=image, log=[], pct=0, done_gb=0.0, total_gb=0.0, _total_bytes=0)
    layers: dict = {}   # layer id -> (downloaded_bytes, total_bytes); summed → aggregate %/GB
    try:
        proc = subprocess.Popen(_pull_cmd(image), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, bufsize=1)
        assert proc.stdout
        for line in proc.stdout:
            line = line.rstrip()
            lid = line.split(":", 1)[0].strip()[:64]
            m = _SIZE_RE.search(line)
            if m and lid:
                done, total = _to_bytes(m.group(1), m.group(2)), _to_bytes(m.group(3), m.group(4))
                if total > 0:
                    layers[lid] = (done, total)
            with _pull_lock:
                _pull["log"] = (_pull["log"] + [line])[-40:]
                td = sum(d for d, _ in layers.values())
                tt = sum(t for _, t in layers.values())
                # `docker/nerdctl pull` discovers layers progressively, so `tt` (known total)
                # GROWS as new layers appear — which would drag % backwards (e.g. 70%→3% when
                # the big model layer finally shows up). Keep `total_gb` MONOTONIC (max seen)
                # and clamp done ≤ total so the bar only ever moves forward, and don't publish
                # numbers until we actually know a real total (avoids the "0.0/0.0" flash).
                if tt > 0:
                    tt = max(tt, _pull.get("_total_bytes", 0))
                    _pull["_total_bytes"] = tt
                    td = min(td, tt)
                    _pull["done_gb"] = round(td / 1e9, 2)
                    _pull["total_gb"] = round(tt / 1e9, 2)
                    _pull["pct"] = min(99, round(td / tt * 100))
        code = proc.wait()
        with _pull_lock:
            if code == 0:
                _pull["state"] = "done"; _pull["pct"] = 100
                if _pull["total_gb"]:
                    _pull["done_gb"] = _pull["total_gb"]
            else:
                _pull["state"] = "error"
    except FileNotFoundError as exc:
        with _pull_lock:
            _pull["state"] = "error"
            _pull["log"].append(f"pull tool not available in this runtime: {exc}")
    except Exception as exc:
        with _pull_lock:
            _pull["state"] = "error"; _pull["log"].append(str(exc))


@app.post("/models/pull")
def pull_model(body: PullReq):
    if _pull["state"] == "pulling":
        raise HTTPException(409, f"already pulling {_pull['image']}")
    if not body.image.strip():
        raise HTTPException(400, "missing image")
    threading.Thread(target=_do_pull, args=(body.image.strip(),), daemon=True).start()
    return {"ok": True, "image": body.image.strip()}


@app.get("/models/pull/status")
def pull_status():
    with _pull_lock:
        return {"state": _pull["state"], "image": _pull["image"],
                "pct": _pull["pct"], "done_gb": _pull["done_gb"], "total_gb": _pull["total_gb"],
                "log_tail": _pull["log"][-12:]}


# --------------------------------------------------------------------------- #
# Display (xrandr) — monitor resolution + rotation. Needs the kiosk user's X
# socket (/tmp/.X11-unix) + DISPLAY/XAUTHORITY mounted into this container.
# --------------------------------------------------------------------------- #
def _xrandr(*args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ)
    env.setdefault("DISPLAY", ":0")
    return subprocess.run(["xrandr", *args], capture_output=True, text=True, timeout=12, env=env)


def _onboard_displays() -> list:
    """Connector names on an ONBOARD (non-NVIDIA, e.g. Intel/AMD iGPU) card that have
    a monitor plugged in. A display on the motherboard port bypasses the NVIDIA GPU
    → dropped frames / lip-sync drift, so the kiosk warns and recommends the GPU
    port. NVIDIA's proprietary driver doesn't report sysfs connection status (its own
    displays show via xrandr instead), so this reliably flags only motherboard-port
    displays (vendor 0x10de = NVIDIA GPU = good; anything else with a connected
    connector = onboard)."""
    onboard: list = []
    drm = "/sys/class/drm"
    try:
        cards = [c for c in os.listdir(drm) if re.fullmatch(r"card\d+", c)]
    except Exception:
        return onboard
    # Map each card -> PCI vendor. Vendor-based (NOT card-number based), so this is
    # correct no matter the enumeration order (NVIDIA may be card0/1/2/…).
    vendors = {}
    for card in cards:
        try:
            vendors[card] = open(f"{drm}/{card}/device/vendor").read().strip().lower()
        except Exception:
            pass
    # All kiosks REQUIRE an NVIDIA GPU. Only warn about onboard ports when an NVIDIA
    # card is actually present — avoids a false alarm on a box with no NVIDIA / with
    # onboard disabled in BIOS (no non-NVIDIA card or no connected connectors → []).
    if "0x10de" not in vendors.values():
        return onboard
    for card, vendor in vendors.items():
        if vendor == "0x10de":     # NVIDIA discrete GPU — the desired port; skip
            continue
        for entry in os.listdir(drm):
            if entry.startswith(card + "-"):
                try:
                    if open(f"{drm}/{entry}/status").read().strip() == "connected":
                        onboard.append(entry.split("-", 1)[1])   # e.g. "DP-4"
                except Exception:
                    pass
    return onboard


@app.get("/display/outputs")
def display_outputs():
    r = _xrandr("--query")
    if r.returncode != 0:
        raise HTTPException(500, f"xrandr failed (no X display?): {r.stderr.strip()}")
    outputs: list = []
    cur = None
    for line in r.stdout.splitlines():
        m = re.match(r"^(\S+) (connected|disconnected)(.*)$", line)
        if m:
            name, status, rest = m.group(1), m.group(2), m.group(3)
            pre = rest.split("(")[0]                       # text before the modes-flags list
            rot = "normal"
            for r2 in ("left", "right", "inverted"):
                if re.search(rf"\b{r2}\b", pre):
                    rot = r2
            mm = re.search(r"(\d+x\d+)\+\d+\+\d+", rest)
            cur = {
                "name": name, "connected": status == "connected",
                "primary": "primary" in rest, "current_mode": mm.group(1) if mm else None,
                "rotation": rot, "modes": [],
            }
            outputs.append(cur)
        elif cur is not None and line.startswith("   "):
            mm = re.match(r"\s+(\d+x\d+)", line)
            if mm and mm.group(1) not in cur["modes"]:
                cur["modes"].append(mm.group(1))
    # onboard_displays: monitors plugged into the motherboard (non-NVIDIA) port.
    return {"outputs": outputs, "onboard_displays": _onboard_displays()}


@app.get("/display/identify")
def display_identify():
    """Flash a big number + output name on each connected monitor for ~5s so the
    admin can tell which physical screen each card controls. Best-effort overlay via
    a detached tkinter process drawing on the host X session (needs python3-tk)."""
    r = _xrandr("--query")
    if r.returncode != 0:
        raise HTTPException(500, f"xrandr failed (no X display?): {r.stderr.strip()}")
    outs = []
    n = 0
    for line in r.stdout.splitlines():
        m = re.match(r"^(\S+) connected (?:primary )?(\d+)x(\d+)\+(\d+)\+(\d+)", line)
        if m:
            n += 1
            outs.append({"n": n, "name": m.group(1),
                         "w": int(m.group(2)), "h": int(m.group(3)),
                         "x": int(m.group(4)), "y": int(m.group(5))})
    if not outs:
        raise HTTPException(404, "no connected displays")
    script = (
        "import tkinter as tk, sys, json\n"
        "outs=json.loads(sys.argv[1])\n"
        "root=tk.Tk(); root.withdraw()\n"
        "for o in outs:\n"
        " w=tk.Toplevel(); w.overrideredirect(True); w.configure(bg='#0a0a0a')\n"
        " bw=min(o['w'],520); bh=min(o['h'],360)\n"
        " cx=o['x']+(o['w']-bw)//2; cy=o['y']+(o['h']-bh)//2\n"
        " w.geometry(f\"{bw}x{bh}+{cx}+{cy}\")\n"
        " try:\n  w.attributes('-topmost', True)\n"
        " except Exception:\n  pass\n"
        " tk.Label(w,text=str(o['n']),fg='#4a90e2',bg='#0a0a0a',font=('Helvetica',200,'bold')).pack(expand=True)\n"
        " tk.Label(w,text=o['name'],fg='#ffffff',bg='#0a0a0a',font=('Helvetica',28)).pack()\n"
        "root.after(5000, root.destroy)\n"
        "root.mainloop()\n"
    )
    env = dict(os.environ)
    env.setdefault("DISPLAY", ":0")
    try:
        subprocess.Popen(["python3", "-c", script, json.dumps(outs)], env=env)
    except Exception as e:
        raise HTTPException(500, f"identify overlay failed: {e}")
    return {"outputs": outs}


class DisplaySet(BaseModel):
    output: str
    mode: Optional[str] = None         # e.g. "1920x1080"
    rotation: Optional[str] = None     # normal | left | right | inverted


@app.post("/display/set")
def display_set(body: DisplaySet):
    if not body.output.strip():
        raise HTTPException(400, "missing output")
    args = ["--output", body.output]
    if body.mode:
        if not re.fullmatch(r"\d+x\d+", body.mode):
            raise HTTPException(400, "bad mode")
        args += ["--mode", body.mode]
    if body.rotation:
        if body.rotation not in ("normal", "left", "right", "inverted"):
            raise HTTPException(400, "bad rotation")
        args += ["--rotate", body.rotation]
    if len(args) == 2:
        raise HTTPException(400, "provide mode and/or rotation")
    r = _xrandr(*args)
    if r.returncode != 0:
        raise HTTPException(500, f"xrandr failed: {r.stderr.strip()}")
    return {"ok": True}


# --------------------------------------------------------------------------- #
# Renny renderer — logs + restart. Works whether Renny runs under Docker or
# kubeadm (docker first, then kubectl).
# --------------------------------------------------------------------------- #
def _kubectl(*args: str, timeout: int = 20) -> subprocess.CompletedProcess:
    return subprocess.run(["kubectl", *args], capture_output=True, text=True, timeout=timeout)


def _renny_container() -> Optional[str]:
    try:
        r = _docker("ps", "--format", "{{.Names}}")
        for n in r.stdout.split():
            if "renny" in n.lower():
                return n
    except Exception:
        pass
    return None


@app.get("/renny/logs")
def renny_logs(lines: int = 1500):
    lines = max(1, min(5000, int(lines)))
    name = _renny_container()
    if name:
        r = _docker("logs", "--tail", str(lines), name)
        return {"source": f"docker:{name}", "logs": (r.stdout or "") + (r.stderr or "")}
    try:
        r = _kubectl("logs", "--tail", str(lines), "-l", "app=renny", "--all-containers=true")
        if r.returncode == 0:
            return {"source": "kubectl", "logs": r.stdout}
    except Exception:
        pass
    raise HTTPException(404, "Renny renderer not found via Docker or kubectl.")


@app.post("/renny/restart")
def renny_restart():
    name = _renny_container()
    if name:
        # A heavy renderer can take a while to stop+start; allow generous time.
        r = subprocess.run(["docker", "restart", name], capture_output=True, text=True, timeout=180)
        if r.returncode != 0:
            raise HTTPException(500, f"docker restart failed: {r.stderr.strip()}")
        return {"ok": True, "via": f"docker:{name}"}
    try:
        r = _kubectl("rollout", "restart", "deploy/renny", timeout=30)
        if r.returncode == 0:
            return {"ok": True, "via": "kubectl"}
        raise HTTPException(404, f"Renny not found: {r.stderr.strip()}")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(404, f"Renny renderer not found: {exc}")


@app.get("/tts-config")
def tts_config():
    """Which TTS provider is the renderer (Renny) wired for? Lets the kiosk tell
    'Riva TTS offline (a real problem)' apart from 'Riva TTS simply isn't the
    configured provider' (operator uses ElevenLabs / Azure / other cloud TTS).

    Signal: the renny Deployment only carries a RIVA_SERVER_ADDR env when Riva is
    set as the TTS target (chart gates it on renderer.tts.rivaServerAddr). The other
    TTS env refs (ElevenLabs/Azure/Veritone) are ALWAYS templated in, so their
    presence is not a usable signal — RIVA_SERVER_ADDR presence is."""
    try:
        r = _kubectl("get", "deploy", "renny", "-o",
                     "jsonpath={range .spec.template.spec.containers[*].env[*]}{.name}={.value}\n{end}")
        if r.returncode != 0:
            return {"known": False}
        riva = False
        for line in r.stdout.splitlines():
            if line.startswith("RIVA_SERVER_ADDR=") and line.split("=", 1)[1].strip():
                riva = True
        return {"known": True, "riva_configured": riva,
                "provider": "riva" if riva else "other"}
    except Exception as exc:
        return {"known": False, "error": str(exc)}


# --------------------------------------------------------------------------- #
# Local LLM (vLLM / NIM) — reload. Restarting the container makes it re-read its
# served model; the Conversation tab polls /admin/llm-health to watch it come
# back ("LLM Reloading" -> "Online"). Docker first, then kubectl.
# --------------------------------------------------------------------------- #
def _llm_container() -> Optional[str]:
    try:
        r = _docker("ps", "--format", "{{.Names}}")
        for n in r.stdout.split():
            low = n.lower()
            if "vllm" in low or "nim-llm" in low or low.endswith("-llm"):
                return n
    except Exception:
        pass
    return None


# Owner/model tokens that mark a CHAT LLM NIM (vs the embed / rerank / OCR NIMs the
# RAG blueprint also runs). Used to auto-find "the LLM" NIMService/deploy to swap.
_LLM_HINT = re.compile(r"gemma|llama-3|llama3|nemotron-(?!embed|rerank)|mistral|qwen|phi|deepseek|mixtral", re.I)
_NOT_LLM = re.compile(r"embed|rerank|ocr|paddle|nv-ingest|nemoretriever", re.I)


NIM_NS_LLM = "nim-models"


def _adapter_llm_service() -> str:
    """The NIMService name the rag-adapter is CURRENTLY pointed at (from its LLM_URL)."""
    try:
        r = _kubectl("get", "deploy", "rag-adapter", "-n", "uneeq", "-o",
                     "jsonpath={range .spec.template.spec.containers[0].env[*]}{.name}={.value}{'\\n'}{end}", timeout=15)
        for line in r.stdout.splitlines():
            if line.startswith("LLM_URL="):
                m = re.search(r"//([^.:/]+)", line.split("=", 1)[1])
                return m.group(1) if m else ""
    except Exception:
        pass
    return ""


def _list_llm_nimservices() -> list[tuple]:
    """All chat-LLM NIMServices in nim-models as (namespace, name, repository, tag, replicas).
    Queries only nim-models (matches the scoped RBAC — `-A` would be forbidden). Filters to
    generative LLMs (skips embed/rerank/ocr/ingest)."""
    rows = []
    try:
        r = _kubectl("get", "nimservice", "-n", NIM_NS_LLM, "-o",
                     'jsonpath={range .items[*]}{.metadata.name}|{.spec.image.repository}|{.spec.image.tag}|{.spec.replicas}{"\\n"}{end}',
                     timeout=15)
        for line in r.stdout.splitlines():
            p = line.split("|")
            if len(p) < 3:
                continue
            name, repo, tag = p[0], p[1], p[2]
            rep = int(p[3].strip()) if len(p) > 3 and p[3].strip().isdigit() else 1
            if repo and _LLM_HINT.search(repo) and not _NOT_LLM.search(repo):
                rows.append((NIM_NS_LLM, name, repo, tag, rep))
    except Exception:
        pass
    return rows


def _llm_nimservice() -> Optional[tuple]:
    """(namespace, name, repository, tag) of the ACTIVE chat-LLM NIMService. PREFERS the
    service the adapter currently points at, so reload/status/scale target the running model,
    not a stale one left scaled-to-0 after a switch."""
    active = _adapter_llm_service()
    rows = _list_llm_nimservices()
    for row in rows:
        if row[1] == active:
            return row[:4]          # the one the adapter points at
    if rows:
        return rows[0][:4]
    return None


class LlmSetReq(BaseModel):
    image: str
    model: Optional[str] = None


NIM_NS = "nim-models"
NIM_AUTH_SECRET = os.getenv("NIM_AUTH_SECRET", "nim-credentials")
NIM_PULL_SECRET = os.getenv("NIM_PULL_SECRET", "ngc-registry-credentials")
NIM_NODE_TYPE = os.getenv("NIM_NODE_TYPE", "renderer")


def _svc_name_for(repo: str) -> str:
    """k8s-safe NIMService/service name from an image repo (owner/model → model-ish)."""
    base = repo.split("/")[-1]
    return re.sub(r"[^a-z0-9-]", "-", base.lower()).strip("-")[:53] or "llm"


@app.post("/llm/set")
def llm_set(body: LlmSetReq):
    """Make an (already-pulled) NIM image the SERVED LLM, fully from the kiosk. On the
    NIM-operator box we ensure a NIMCache + NIMService exist for it (auto-selected model
    profile — no hard-coded hash), scale the CURRENT LLM down to free the GPU, and repoint
    the rag-adapter's LLM_URL + LLM_MODEL. The kiosk polls /v1/models for readiness.

    Requires the host-helper SA to manage nimcaches/nimservices in nim-models (shipped in
    the host-helper chart). If that RBAC is missing, kubectl returns 'forbidden' and we
    surface a clear, actionable error instead of failing silently."""
    image = body.image.strip()
    if not image:
        raise HTTPException(400, "missing image")
    if not image.startswith("nvcr.io/nim/"):
        raise HTTPException(400, "only official NVIDIA NIM images are supported (nvcr.io/nim/...)")
    # Model SWITCHING is built on NIM Operator CRDs (NIMCache/NIMService) — kubeadm only.
    # On a Docker install, refuse with a clear reason (the kiosk also disables the button).
    if _runtime() == "docker":
        raise HTTPException(400, "model switching requires the kubeadm / NVIDIA NIM Operator "
                            "install; it is not available on a Docker install.")
    repo, _, tag = image.rpartition(":")
    if not repo:
        repo, tag = image, "latest"
    tag = tag or "latest"
    model = (body.model or repo.split("/nim/")[-1]).strip()
    name = _svc_name_for(repo)
    cache = f"{name}-cache"

    # REUSE-FIRST: if ANY NIMService in nim-models already runs this image repo (e.g. the
    # Helm-installed 'gemma' service for the gemma image), point at THAT — scale it up,
    # scale the rest down, repoint the adapter, done. Creating a second service for the
    # same model re-downloads tens of GB into a duplicate cache and can fill the disk
    # (the exact failure that took this box down). Only a genuinely new model creates
    # a NIMCache + NIMService.
    for (ns_, svc_name, r_repo, _tag, _rep) in _list_llm_nimservices():
        if r_repo == repo:
            _kubectl("patch", "nimservice", svc_name, "-n", ns_, "--type", "merge",
                     "-p", json.dumps({"spec": {"replicas": 1}}), timeout=30)
            scaled_down = []
            for (ns2, other, _r, _t, _rp) in _list_llm_nimservices():
                if other != svc_name:
                    pr = _kubectl("patch", "nimservice", other, "-n", ns2, "--type", "merge",
                                  "-p", json.dumps({"spec": {"replicas": 0}}), timeout=30)
                    if pr.returncode == 0:
                        scaled_down.append(other)
            url = f"http://{svc_name}.{NIM_NS}.svc.cluster.local:8000"
            _kubectl("set", "env", "deploy/rag-adapter", f"LLM_URL={url}", f"LLM_MODEL={model}", "-n", "uneeq", timeout=30)
            _SWITCH_STARTED[svc_name] = time.time()
            return {"ok": True, "service": f"{NIM_NS}/{svc_name}", "model": model, "url": url,
                    "reused": True, "scaled_down": scaled_down}

    # 1) NIMCache — pull/optimize the model into its own PVC. No `profiles` → the operator
    #    auto-selects a compatible profile for THIS GPU (unlike the pinned gemma cache).
    nimcache = {
        "apiVersion": "apps.nvidia.com/v1alpha1", "kind": "NIMCache",
        "metadata": {"name": cache, "namespace": NIM_NS},
        "spec": {
            "source": {"ngc": {"authSecret": NIM_AUTH_SECRET, "pullSecret": NIM_PULL_SECRET,
                                "modelPuller": f"{repo}:{tag}", "model": {}}},
            "storage": {"pvc": {"create": True, "size": "80Gi", "storageClass": "local-path",
                                "volumeAccessMode": "ReadWriteOnce"}},
            "resources": {"cpu": "0", "memory": "0"},
        },
    }
    # 2) NIMService — serve it. No NIM_MODEL_PROFILE env (auto). One GPU.
    nimservice = {
        "apiVersion": "apps.nvidia.com/v1alpha1", "kind": "NIMService",
        "metadata": {"name": name, "namespace": NIM_NS},
        "spec": {
            "image": {"repository": repo, "tag": tag, "pullPolicy": "IfNotPresent",
                      "pullSecrets": [NIM_PULL_SECRET]},
            "authSecret": NIM_AUTH_SECRET,
            "storage": {"nimCache": {"name": cache, "profile": ""}},
            "replicas": 1,
            "resources": {"limits": {"nvidia.com/gpu": 1}},
            "expose": {"service": {"port": 8000, "type": "ClusterIP"}},
            "nodeSelector": {"uneeq.io/node-type": NIM_NODE_TYPE},
            "tolerations": [{"effect": "NoSchedule", "key": "nvidia.com/gpu", "operator": "Exists"}],
        },
    }
    for obj in (nimcache, nimservice):
        r = _kubectl_apply(json.dumps(obj), timeout=45)
        if r.returncode != 0:
            err = r.stderr.strip()
            if "forbidden" in err.lower():
                raise HTTPException(403, "model switching not enabled: the host-helper needs "
                                    "permission to manage nimcaches/nimservices in nim-models "
                                    "(apply the host-helper-nim Role/RoleBinding).")
            raise HTTPException(500, f"apply {obj['kind']} failed: {err}")

    # 3) Free the GPU: scale EVERY OTHER LLM NIMService to 0. On a single-GPU box any other
    #    running LLM holds the one GPU, so the new model's pod would sit Pending forever
    #    (the "says loading but nothing on the GPU" trap). Scaling only the adapter's current
    #    target isn't enough — stale/half-switched services (a previous attempt, a failed
    #    download) also pin the GPU. Scale them all down except the one we're switching to.
    scaled_down = []
    for (ns, svc_name, _repo, _tag, _rep) in _list_llm_nimservices():
        if svc_name == name:
            continue
        pr = _kubectl("patch", "nimservice", svc_name, "-n", ns, "--type", "merge",
                      "-p", json.dumps({"spec": {"replicas": 0}}), timeout=30)
        if pr.returncode == 0:
            scaled_down.append(svc_name)

    # 4) Repoint the adapter at the new service + model id.
    url = f"http://{name}.{NIM_NS}.svc.cluster.local:8000"
    _kubectl("set", "env", "deploy/rag-adapter", f"LLM_URL={url}", f"LLM_MODEL={model}", "-n", "uneeq", timeout=30)
    # Mark the activation start so /llm/status can report a live elapsed timer.
    _SWITCH_STARTED[name] = time.time()
    return {"ok": True, "service": f"{NIM_NS}/{name}", "model": model, "url": url,
            "scaled_down": scaled_down}


@app.get("/llm/status")
def llm_status():
    """Live state of the LLM the adapter is pointed at, PLUS the detected runtime.
    The kiosk gates its kubeadm-only controls (model switching via NIM Operator CRDs)
    on `runtime` — on a Docker install those buttons are disabled with a hint instead
    of failing confusingly. stage = ready | starting | scheduling | pulling | blocked |
    stopped | error."""
    out = _llm_status_impl()
    out["runtime"] = _runtime()
    return out


def _llm_status_impl() -> dict:
    env = {}
    try:
        r = _kubectl("get", "deploy", "rag-adapter", "-n", "uneeq", "-o",
                     "jsonpath={range .spec.template.spec.containers[0].env[*]}{.name}={.value}{'\\n'}{end}", timeout=15)
        for line in r.stdout.splitlines():
            if "=" in line:
                k, v = line.split("=", 1); env[k] = v
    except Exception:
        pass
    model = env.get("LLM_MODEL", "")
    m = re.search(r"//([^.:/]+)", env.get("LLM_URL", ""))
    svc = m.group(1) if m else ""
    if not svc:
        return {"target": model, "service": "", "ready": True, "stage": "ready", "detail": ""}
    # Read the NIMService's OWN status (within the nimservices RBAC the box already has —
    # no pod/deploy read needed). state = Ready | NotReady | Failed | Pending; the
    # conditions carry a human message we can surface as the failure reason.
    state, ready_rep, cond_msg, replicas, found = "", 0, "", None, False
    try:
        sr = _kubectl("get", "nimservice", svc, "-n", NIM_NS, "-o",
                      "jsonpath={.spec.replicas}|{.status.state}|{.status.readyReplicas}|{range .status.conditions[*]}{.reason}:{.message};{end}", timeout=15)
        found = sr.returncode == 0 and bool(sr.stdout.strip())
        parts = sr.stdout.split("|")
        replicas = int(parts[0].strip()) if len(parts) > 0 and parts[0].strip().lstrip("-").isdigit() else None
        state = (parts[1] if len(parts) > 1 else "").strip()
        ready_rep = int(parts[2].strip()) if len(parts) > 2 and parts[2].strip().isdigit() else 0
        cond_msg = (parts[3] if len(parts) > 3 else "").strip()
    except Exception:
        pass
    # The adapter points at a service that no longer exists (e.g. deleted) → offline, not
    # "loading". Tell the admin to activate a model rather than spin forever.
    if not found:
        _SWITCH_STARTED.pop(svc, None)
        return {"target": model, "service": svc, "ready": False, "stage": "stopped",
                "label": "Offline", "detail": "No model service is running for this target — activate a model.",
                "progress": 0, "elapsed_s": None}
    # Scaled to 0 (Stop-all, or a manual scale-down) → STOPPED, not loading. This is the
    # fix for "I pressed Stop-all but it still says loading": a target at replicas 0 is off.
    if replicas == 0:
        _SWITCH_STARTED.pop(svc, None)
        return {"target": model, "service": svc, "ready": False, "stage": "stopped",
                "label": "Stopped", "detail": "This model is stopped (0 replicas). Activate a model to start it.",
                "progress": 0, "elapsed_s": None}
    # Elapsed since the load began. Prefer the switch timestamp; otherwise self-seed the
    # first time we see it not-ready, so the elapsed counter + estimate bar work even when
    # the load was started outside the kiosk (e.g. operator applied a NIMService directly).
    if svc not in _SWITCH_STARTED:
        _SWITCH_STARTED[svc] = time.time()
    started = _SWITCH_STARTED.get(svc)
    elapsed = int(time.time() - started) if started else None
    if ready_rep >= 1 or state.lower() == "ready":
        _SWITCH_STARTED.pop(svc, None)   # done — stop the elapsed counter
        return {"target": model, "service": svc, "ready": True, "stage": "ready",
                "label": "Ready", "detail": "", "progress": 100, "elapsed_s": 0}
    low = (state + " " + cond_msg).lower()
    # NIMCache state (download/optimize phase). host-helper-nim RBAC includes nimcaches.
    cache_state = ""
    try:
        cr = _kubectl("get", "nimcache", f"{svc}-cache", "-n", NIM_NS, "-o",
                      "jsonpath={.status.state}", timeout=12)
        cache_state = cr.stdout.strip()
    except Exception:
        pass
    cache_ready = cache_state.lower() in ("ready", "completed")
    # Is another LLM still holding the (single) GPU? If so the target pod can't schedule and
    # will sit "loading" forever — surface that as the real reason instead of a vague spinner.
    blocker = ""
    try:
        for (_ns, svc_name, _repo, _tag, rep) in _list_llm_nimservices():
            if svc_name != svc and rep and rep > 0:
                blocker = svc_name
                break
    except Exception:
        pass
    # Map to a stage + a coarse progress bar (NIM does not expose a true load %, so this is
    # a staged estimate — honest about WHICH phase, not a fake precise number) + a label.
    if "fail" in low or "error" in low or "backoff" in low or "crashloop" in low:
        stage, label, detail, progress = "error", "Failed", \
            (cond_msg[:180] or "the model service failed to start (check GPU memory / NGC image)"), 0
    elif blocker:
        stage, label, detail, progress = "blocked", "Waiting for GPU", \
            (f"'{blocker}' is still loaded and holding the GPU. Stop it (Stop all LLM processes) "
             "or wait for the switch to scale it down, then retry."), 40
    elif not cache_ready and (cache_state or "pending" in low or not state):
        stage, label, detail, progress = "pulling", "Downloading model", \
            (f"pulling / optimizing the model into cache ({cache_state or 'starting'})"), 25
    elif "pending" in low:
        stage, label, detail, progress = "scheduling", "Scheduling", \
            "cache ready — waiting for the GPU node to place the pod", 50
    else:
        stage, label, detail, progress = "starting", "Loading weights", \
            "loading weights / building the inference engine into VRAM", 80
    # A load that has run far past a sane cold-start budget is almost certainly stuck.
    stuck = elapsed is not None and elapsed > 600 and stage in ("scheduling", "starting", "pulling")
    if stuck:
        detail += " — this is taking unusually long; it may be stuck (consider Stop all LLM processes and retry)."
    return {"target": model, "service": svc, "ready": False, "stage": stage, "label": label,
            "detail": detail, "progress": progress, "elapsed_s": elapsed,
            "cache_state": cache_state, "stuck": stuck}


@app.post("/llm/reload")
def llm_reload():
    name = _llm_container()
    if name:
        # Loading a multi-billion-param model into VRAM takes a while; the restart
        # call returns once the container has been (re)started, not when ready.
        r = subprocess.run(["docker", "restart", name], capture_output=True, text=True, timeout=240)
        if r.returncode != 0:
            raise HTTPException(500, f"docker restart failed: {r.stderr.strip()}")
        return {"ok": True, "via": f"docker:{name}"}
    # kubeadm/NIM-operator: restart the ACTIVE LLM NIMService by bouncing its replicas
    # (0 → 1). We patch the NIMService (within the scoped nimservices RBAC) — NOT its
    # backing Deployment (host-helper has no deploy RBAC in nim-models), and NOT a
    # hard-coded "vllm" (which doesn't exist → the old "deployments.apps vllm not found").
    svc = _llm_nimservice()
    if not svc:
        raise HTTPException(404, "no LLM NIMService found to reload")
    ns, name, _, _ = svc
    r0 = _kubectl("patch", "nimservice", name, "-n", ns, "--type", "merge",
                  "-p", json.dumps({"spec": {"replicas": 0}}), timeout=30)
    if r0.returncode != 0:
        err = r0.stderr.strip()
        if "forbidden" in err.lower():
            raise HTTPException(403, "reload not enabled: host-helper needs nimservices permission (host-helper-nim Role).")
        raise HTTPException(500, f"scale-down failed: {err}")
    threading.Timer(2.0, lambda: _kubectl("patch", "nimservice", name, "-n", ns, "--type", "merge",
                                           "-p", json.dumps({"spec": {"replicas": 1}}), timeout=30)).start()
    return {"ok": True, "via": f"nimservice:{ns}/{name}"}


@app.post("/llm/stop-all")
def llm_stop_all():
    """KILL SWITCH — scale EVERY chat-LLM NIMService to 0 to free the GPU and recover from
    a stuck/half-loaded model. This is the "get me out of a bad state" button: after this
    nothing is served (LLM offline) until the admin activates a model again. Non-destructive
    (scales to 0, does not delete) so any model can be brought back. Docker fallback stops
    the single vLLM container."""
    name = _llm_container()
    if name:
        r = subprocess.run(["docker", "stop", name], capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            raise HTTPException(500, f"docker stop failed: {r.stderr.strip()}")
        return {"ok": True, "stopped": [f"docker:{name}"]}
    stopped, errors = [], []
    rows = _list_llm_nimservices()
    if not rows:
        return {"ok": True, "stopped": [], "detail": "no LLM NIMServices found"}
    for (ns, svc_name, _repo, _tag, _rep) in rows:
        r = _kubectl("patch", "nimservice", svc_name, "-n", ns, "--type", "merge",
                     "-p", json.dumps({"spec": {"replicas": 0}}), timeout=30)
        if r.returncode == 0:
            stopped.append(svc_name)
            _SWITCH_STARTED.pop(svc_name, None)
        else:
            err = r.stderr.strip()
            if "forbidden" in err.lower():
                raise HTTPException(403, "stop not enabled: host-helper needs nimservices permission (host-helper-nim Role).")
            errors.append(f"{svc_name}: {err}")
        # FORCE-KILL the pods too (both label conventions the operator uses) so the GPU is
        # freed IMMEDIATELY — scale-to-0 alone waits out graceful termination, which is
        # exactly when a wedged vLLM refuses to die. This is the kill-switch guarantee:
        # no console access needed to recover a stuck model.
        for sel in (f"app={svc_name}", f"app.kubernetes.io/name={svc_name}"):
            _kubectl("delete", "pods", "-n", ns, "-l", sel,
                     "--force", "--grace-period=0", "--ignore-not-found", timeout=30)
    return {"ok": not errors, "stopped": stopped, "errors": errors}


def _parse_smi(out: str) -> Optional[dict]:
    try:
        parts = [x.strip() for x in out.strip().splitlines()[0].split(",")]
        util, used, total = parts[0], parts[1], parts[2]
        used_gb = round(int(used) / 1024, 1)
        total_gb = round(int(total) / 1024, 1)
        return {"gpu_util_pct": int(util),
                "vram_used_gb": used_gb, "vram_total_gb": total_gb,
                "vram_free_gb": round(total_gb - used_gb, 1),
                "vram_pct": round(int(used) / int(total) * 100) if int(total) else 0}
    except Exception:
        return None


def _pod_by_uid() -> dict:
    """Map pod UID -> 'namespace/name' so GPU PIDs can be attributed to their pod
    (e.g. tell Riva STT's Triton apart from Riva TTS's Triton — same process name,
    different pods)."""
    try:
        r = subprocess.run(["kubectl", "get", "pods", "-A", "-o",
            'jsonpath={range .items[*]}{.metadata.uid} {.metadata.namespace}/{.metadata.name}{"\\n"}{end}'],
            capture_output=True, text=True, timeout=8)
        out = {}
        for line in r.stdout.splitlines():
            parts = line.split(" ", 1)
            if len(parts) == 2:
                out[parts[0].strip()] = parts[1].strip()
        return out
    except Exception:
        return {}


def _pod_for_pid(pid: str, pods: dict) -> str:
    """Resolve a host PID to its owning pod via /proc/<pid>/cgroup (needs hostPID)."""
    try:
        with open(f"/proc/{pid}/cgroup") as f:
            txt = f.read()
        m = re.search(r"pod([0-9a-fA-F]{8}[-_][0-9a-fA-F]{4}[-_][0-9a-fA-F]{4}[-_][0-9a-fA-F]{4}[-_][0-9a-fA-F]{12})", txt)
        if m:
            return pods.get(m.group(1).replace("_", "-"), "")
    except Exception:
        pass
    return ""


def _gpu_proc_util() -> dict:
    """Per-PID GPU compute (SM) utilization % via `nvidia-smi pmon -c 1`. Returns
    {pid: sm_pct}. This is the ONLY per-process GPU-utilization source (the process
    table + --query-compute-apps give MEMORY only, not compute). pmon takes one
    instantaneous sample; a process not computing at that instant reads 0 ('-').
    Unsupported on MIG / older drivers → empty dict, callers then fall back to
    ordering by VRAM. Layout: `# gpu  pid  type  sm  mem  enc  dec  command`."""
    try:
        r = subprocess.run(["nvidia-smi", "pmon", "-c", "1"], capture_output=True, text=True, timeout=10)
        if r.returncode != 0:
            return {}
        out = {}
        for line in r.stdout.splitlines():
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            toks = s.split()
            if len(toks) < 4 or not toks[1].isdigit():
                continue
            sm = toks[3]
            out[toks[1]] = int(sm) if sm.isdigit() else 0
        return out
    except Exception:
        return {}


def _gpu_procs(total_gb: float) -> list:
    """ALL GPU processes (compute AND graphics) from nvidia-smi's full process
    table — not just CUDA compute-apps. `--query-compute-apps` omits graphics
    (G-type) processes, so it misses Renny (Vulkan renderer), Xorg, the kiosk
    browser, etc. Each process is also attributed to its owning k8s pod (`owner`)
    so the kiosk can separate Riva STT vs Riva TTS vs LLM. Needs hostPID:true.
    Per-process GPU-util (`gpu_pct`, SM%) is folded in from pmon so the kiosk's GPU
    bar can rank by compute, not just memory."""
    try:
        r = subprocess.run(["nvidia-smi"], capture_output=True, text=True, timeout=10)
        if r.returncode != 0:
            return []
        pods = _pod_by_uid()
        util = _gpu_proc_util()
        procs = []
        in_tbl = False
        for line in r.stdout.splitlines():
            if "Processes:" in line:
                in_tbl = True
                continue
            if not in_tbl or not line.startswith("|"):
                continue
            body = line.strip().strip("|").strip()
            m = re.search(r"(\d+)\s*MiB", body)
            if not m:
                continue
            toks = body.split()
            # Layout: GPU GI CI PID TYPE NAME ... MEM. Anchor on the TYPE token
            # (C / G / C+G): PID is just before it, process name just after.
            try:
                ti = next(i for i, t in enumerate(toks) if t in ("C", "G", "C+G"))
            except StopIteration:
                continue
            pid = toks[ti - 1]
            ptype = toks[ti]
            name = toks[ti + 1] if ti + 1 < len(toks) else "?"
            mem_mib = int(m.group(1))
            gb = round(mem_mib / 1024, 1)
            pct = round(mem_mib / 1024 / total_gb * 100) if total_gb else 0
            procs.append({"pid": pid, "name": name, "type": ptype,
                          "owner": _pod_for_pid(pid, pods),
                          "vram_gb": gb, "vram_pct": pct,
                          "gpu_pct": util.get(pid, 0)})
        return procs
    except Exception:
        return []


def _gpu_basic() -> dict:
    """GPU util + VRAM dict (no procs) — merged into the STT/TTS health responses so
    the kiosk's status hover can show 'VRAM x GB free of y GB'."""
    try:
        r = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total",
                            "--format=csv,noheader,nounits"], capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            return _parse_smi(r.stdout) or {}
    except Exception:
        pass
    return {}


def _curl_ok(url: str) -> bool:
    try:
        r = subprocess.run(["curl", "-fsS", "-m", "5", "-o", "/dev/null", "-w", "%{http_code}", url],
                           capture_output=True, text=True, timeout=8)
        return r.returncode == 0 and r.stdout.strip().startswith("2")
    except Exception:
        return False


def _deploy_ready(ns: str, name: str) -> bool:
    try:
        r = subprocess.run(["kubectl", "get", "deploy", name, "-n", ns,
                            "-o", "jsonpath={.status.readyReplicas}"],
                           capture_output=True, text=True, timeout=8)
        return r.returncode == 0 and (r.stdout.strip() or "0") not in ("", "0")
    except Exception:
        return False


def _k8s_flavor() -> str:
    """Which Kubernetes distro Renny runs under — for an EXACT runtime label
    (kubeadm vs microk8s vs managed EKS/AKS/GKE). host-helper has cluster-wide pod
    read, so we sniff kube-system for distro-signature pods."""
    try:
        n = subprocess.run(["kubectl", "get", "pods", "-n", "kube-system", "-o", "name"],
                           capture_output=True, text=True, timeout=8).stdout.lower()
        if "aws-node" in n:
            return "eks"
        if "cloud-node-manager" in n or "azure-cns" in n:
            return "aks"
        if "gke-metadata" in n or "/gke-" in n:
            return "gke"
        if "kube-apiserver-" in n:        # static control-plane pod = kubeadm
            return "kubeadm"
    except Exception:
        pass
    return "kubernetes"


_RUNTIME = None
def _runtime() -> str:
    """Detect how the stack runs: 'kubeadm' (k8s, this box) or 'docker' (the legacy
    all-in-one). The kiosk supports BOTH; health/control endpoints branch on this so
    a Docker install isn't missed. Cached after first detection."""
    global _RUNTIME
    if _RUNTIME:
        return _RUNTIME
    # Running inside a k8s pod? The in-cluster service-account token is always
    # mounted — RBAC-free and definitive (kubectl get ns would need namespace RBAC
    # the host-helper doesn't have). For a Docker install this file is absent.
    if os.path.exists("/var/run/secrets/kubernetes.io/serviceaccount/token"):
        _RUNTIME = _k8s_flavor(); return _RUNTIME
    try:
        if subprocess.run(["docker", "ps", "-q"], capture_output=True, text=True, timeout=6).returncode == 0:
            _RUNTIME = "docker"; return _RUNTIME
    except Exception:
        pass
    return "unknown"


def _with_vram(out: dict) -> dict:
    v = _gpu_basic()
    if v:
        out["vram_free_gb"] = v.get("vram_free_gb")
        out["vram_total_gb"] = v.get("vram_total_gb")
    return out


def _svc_start_stage(ns: str, deploy: str, container: str = "") -> dict:
    """When a service isn't ready, report WHAT it is actually doing (from the pod's real
    state + log tail) and for HOW LONG. The kiosk shows this instead of a bare 'Offline',
    so a genuine one-time engine build isn't mistaken for a dead service — and a dead
    service isn't dressed up as 'starting'. Stages: starting | downloading | building |
    loading | error | offline."""
    try:
        r = _kubectl("get", "pods", "-n", ns, "-l", f"app={deploy}", "-o", "json", timeout=15)
        pods = [p for p in json.loads(r.stdout).get("items", [])
                if not p["metadata"].get("deletionTimestamp")]
    except Exception:
        return {}
    if not pods:
        return {"stage": "offline", "detail": "no pod running"}
    p = sorted(pods, key=lambda x: x["metadata"].get("creationTimestamp", ""))[-1]
    phase = p["status"].get("phase", "")
    elapsed = None
    try:
        from datetime import datetime, timezone
        t = datetime.strptime(p["status"].get("startTime", ""), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        elapsed = int((datetime.now(timezone.utc) - t).total_seconds())
    except Exception:
        pass
    cs = p["status"].get("containerStatuses", [])
    waiting = next((c["state"]["waiting"].get("reason", "") for c in cs if c.get("state", {}).get("waiting")), "")
    restarts = max([c.get("restartCount", 0) for c in cs] or [0])
    base = {"elapsed_s": elapsed, "restarts": restarts}
    if waiting in ("CrashLoopBackOff", "ImagePullBackOff", "ErrImagePull", "CreateContainerError"):
        return {**base, "stage": "error", "detail": waiting}
    if phase == "Pending" or waiting in ("ContainerCreating", "PodInitializing"):
        return {**base, "stage": "starting", "detail": "starting container / pulling image"}
    # Running but not ready → the log tail tells us the real phase.
    logs = ""
    try:
        args = ["logs", "-n", ns, p["metadata"]["name"], "--tail=40"]
        if container:
            args += ["-c", container]
        logs = _kubectl(*args, timeout=15).stdout
    except Exception:
        pass
    low = logs.lower()
    if "downloading" in low or ("download" in low and "%" in low):
        return {**base, "stage": "downloading", "detail": "downloading model files"}
    if "trt" in low or "tensorrt" in low or "building" in low or "engine" in low or "convert" in low:
        return {**base, "stage": "building",
                "detail": "building the speech engine (one-time after an update or interrupted start)"}
    if "loading" in low or "initializ" in low:
        return {**base, "stage": "loading", "detail": "loading models into GPU memory"}
    return {**base, "stage": "starting", "detail": "service starting"}


@app.get("/stt-health")
def stt_health():
    """Riva STT (ASR) readiness — works on BOTH runtimes. kubeadm: k8s Deployment
    readiness (the ASR NIM has no cluster HTTP svc). docker: probe the host-network
    Riva STT NIM. Reports OFFLINE truthfully when down (e.g. ImagePullBackOff)."""
    rt = _runtime()
    if rt == "docker":
        online = _curl_ok(os.environ.get("STT_DOCKER_URL", "http://127.0.0.1:9001/v1/health/ready"))
        return _with_vram({"riva_online": online, "runtime": rt, "endpoint": "127.0.0.1:9001"})
    name = os.environ.get("STT_DEPLOY", "digitalhuman-asr")
    ns = os.environ.get("STT_NS", "uneeq")
    ready = _deploy_ready(ns, name)
    out = {"riva_online": ready, "runtime": rt, "deploy": f"{ns}/{name}"}
    if not ready:
        # Real start-stage (building engine / loading / error) + elapsed, so the kiosk
        # can say WHY it's offline instead of leaving the admin guessing.
        out["start"] = _svc_start_stage(ns, name, container="nemotron-asr")
    return _with_vram(out)


@app.get("/tts-health")
def tts_health():
    """Riva TTS (Magpie) readiness — works on BOTH runtimes. kubeadm: HTTP health on
    the magpie cluster service. docker: probe the host-network Riva TTS NIM."""
    rt = _runtime()
    if rt == "docker":
        url = os.environ.get("TTS_DOCKER_URL", "http://127.0.0.1:9000/v1/health/ready")
    else:
        url = os.environ.get("TTS_HEALTH_URL", "http://magpie-tts.nim-models:9000/v1/health/ready")
    online = _curl_ok(url)
    out = {"riva_online": online, "runtime": rt, "url": url}
    if not online and rt != "docker":
        out["start"] = _svc_start_stage(os.environ.get("TTS_NS", "nim-models"),
                                        os.environ.get("TTS_DEPLOY", "magpie-tts"))
    return _with_vram(out)


@app.get("/runtime")
def runtime():
    """How the stack runs — 'kubeadm' or 'docker'. Lets the kiosk show the runtime
    (e.g. for Renny) and pick the right control path, ahead of any action."""
    return {"runtime": _runtime()}


@app.get("/rag-health")
def rag_health():
    """NVIDIA RAG retrieval reachability — works on BOTH runtimes. kubeadm: probe the
    RAG server (advanced-rag); docker: 127.0.0.1:8081. Offline when the RAG server
    isn't deployed/reachable (then the DH answers from the model's general knowledge)."""
    rt = _runtime()
    base = "http://127.0.0.1:8081" if rt == "docker" else "http://rag-server.advanced-rag.svc.cluster.local:8081"
    url = os.environ.get("RAG_HEALTH_URL", base + "/v1/health")
    return _with_vram({"rag_online": _curl_ok(url), "runtime": rt, "url": url})


RAG_NS = "advanced-rag"

# Heavy RAG sub-components an admin can disable LIVE to reclaim GPU without tearing
# down all of RAG. Matched against deployment names. `env` (optional) flips a flag
# on rag-server so it doesn't call a NIM that's been scaled to 0. query_impact tells
# the kiosk whether disabling affects live answers (reranker) or only future
# document uploads (doc-parsing is ingest-time only → safe to disable for serving).
RAG_COMPONENTS = {
    "reranker": {
        "label": "Reranker",
        "match": ["rerankqa"],
        "env": {"deploy": "rag-server", "var": "ENABLE_RERANKER", "on": "True", "off": "false"},
        "query_impact": True,
    },
    "docparse": {
        "label": "Document parsing (tables/charts/OCR)",
        "match": ["nemoretriever", "nv-ingest", "ocr", "paddleocr"],
        "env": None,
        "query_impact": False,
    },
}

def _rag_component_of(name: str):
    n = name.lower()
    for key, c in RAG_COMPONENTS.items():
        if any(m in n for m in c["match"]):
            return key
    return None


def _rag_deploys() -> list:
    """The NVIDIA RAG blueprint workloads (advanced-rag namespace) with their
    desired vs ready replica counts — so the kiosk can show enabled/disabled and
    a 'reloading' state while pods come back."""
    r = _kubectl("get", "deploy", "-n", RAG_NS, "-o",
        'jsonpath={range .items[*]}{.metadata.name} {.spec.replicas} {.status.readyReplicas}{"\\n"}{end}')
    rows = []
    if r.returncode == 0:
        for line in r.stdout.splitlines():
            p = line.split()
            if not p:
                continue
            want = int(p[1]) if len(p) > 1 and p[1].lstrip("-").isdigit() else 0
            ready = int(p[2]) if len(p) > 2 and p[2].lstrip("-").isdigit() else 0
            rows.append({"name": p[0], "want": want, "ready": ready})
    return rows


@app.get("/rag/state")
def rag_state():
    """Is NVIDIA RAG installed, and is it currently enabled (pods scaled up) or
    disabled (scaled to 0 to free GPU)? Drives the Conversation-tab toggle."""
    rt = _runtime()
    if rt in ("docker", "unknown"):
        # Docker all-in-one: no pod scaling — report reachability only.
        return {"installed": None, "enabled": _curl_ok("http://127.0.0.1:8081/v1/health"),
                "scalable": False, "runtime": rt}
    rows = _rag_deploys()
    if not rows:
        return {"installed": False, "enabled": False, "scalable": True, "runtime": rt}
    # The RAG management UI (rag-frontend) is a NodePort the blueprint assigns at
    # install time — report it so the kiosk's "Open RAG Manager" link is correct
    # without hardcoding a port that shifts on reinstall.
    fport = None
    try:
        fr = _kubectl("get", "svc", "rag-frontend", "-n", RAG_NS, "-o",
                      "jsonpath={.spec.ports[0].nodePort}")
        if fr.returncode == 0 and fr.stdout.strip().isdigit():
            fport = int(fr.stdout.strip())
    except Exception:
        pass
    # Per-component state (reranker, doc-parsing) for the live toggles.
    comps = {}
    for key, c in RAG_COMPONENTS.items():
        crows = [x for x in rows if _rag_component_of(x["name"]) == key]
        comps[key] = {"label": c["label"], "query_impact": c["query_impact"],
                      "enabled": any(x["want"] > 0 for x in crows),
                      "ready": sum(x["ready"] for x in crows), "total": len(crows)}
    return {"installed": True, "enabled": any(x["want"] > 0 for x in rows),
            "ready": sum(x["ready"] for x in rows), "total": len(rows),
            "frontend_port": fport, "components": comps, "scalable": True, "runtime": rt}


@app.post("/rag/scale")
def rag_scale(enabled: bool, component: str = ""):
    """Enable/disable NVIDIA RAG — the whole stack, or a single heavy component.

    No `component`: scales EVERY advanced-rag deployment to 1/0 (frees ~40 GB; the
    digital human then answers from general knowledge; re-enable reloads ~1–2 min).

    With `component` (reranker | docparse): scales just that group, and flips the
    matching rag-server flag (e.g. ENABLE_RERANKER) so it doesn't call a downed NIM.
    'docparse' is ingest-time only — safe to disable while serving."""
    rt = _runtime()
    if rt in ("docker", "unknown"):
        raise HTTPException(400, "RAG enable/disable is only supported on the kubeadm/CNS runtime.")
    rows = _rag_deploys()
    if not rows:
        raise HTTPException(404, "NVIDIA RAG is not installed (no advanced-rag deployments found).")
    rep = "1" if enabled else "0"
    if component:
        c = RAG_COMPONENTS.get(component)
        if not c:
            raise HTTPException(400, f"unknown RAG component '{component}'")
        targets = [x["name"] for x in rows if _rag_component_of(x["name"]) == component]
        if not targets:
            raise HTTPException(404, f"no advanced-rag deployments match component '{component}'")
        for t in targets:
            r = _kubectl("scale", "deploy", t, "-n", RAG_NS, f"--replicas={rep}", timeout=30)
            if r.returncode != 0:
                raise HTTPException(502, f"scale {t} failed: {(r.stderr or r.stdout).strip()[:200]}")
        # Coordinate the rag-server flag so it stops/starts calling the NIM.
        if c.get("env"):
            e = c["env"]
            val = e["on"] if enabled else e["off"]
            _kubectl("set", "env", f"deploy/{e['deploy']}", f"{e['var']}={val}", "-n", RAG_NS, timeout=30)
        return {"ok": True, "enabled": enabled, "component": component, "scaled": len(targets)}
    r = _kubectl("scale", "deploy", "--all", "-n", RAG_NS, f"--replicas={rep}", timeout=45)
    if r.returncode != 0:
        raise HTTPException(502, f"kubectl scale failed: {(r.stderr or r.stdout).strip()[:300]}")
    return {"ok": True, "enabled": enabled, "scaled": len(rows)}


@app.post("/tts-test")
def tts_test(text: str = "Hello. This is a test. One. Two. Three.",
             lang: str = "en-US",
             voice: str = "Magpie-Multilingual.EN-US.Mia"):
    """Synthesize a phrase on Riva TTS (Magpie) and return the WAV — works on kubeadm
    (magpie cluster svc) and docker (127.0.0.1). text/lang/voice are query params so
    the kiosk can speak the test phrase in the selected language (Magpie's multilingual
    voice + language_code). Magpie's /v1/audio/synthesize is multipart → audio/wav."""
    base = "http://127.0.0.1:9000" if _runtime() == "docker" else "http://magpie-tts.nim-models:9000"
    out = "/tmp/tts_test.wav"
    try:
        r = subprocess.run([
            "curl", "-s", "-m", "30", "-o", out, "-w", "%{http_code}",
            "-X", "POST", base + "/v1/audio/synthesize",
            "-F", f"text={text}",
            "-F", f"language={lang}",
            "-F", f"voice={voice}",
        ], capture_output=True, text=True, timeout=40)
        if r.stdout.strip() != "200":
            raise HTTPException(502, f"Riva TTS returned HTTP {r.stdout.strip() or '?'}")
        with open(out, "rb") as f:
            data = f.read()
        return Response(content=data, media_type="audio/wav")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(502, f"Riva TTS not reachable: {exc}")


_GPU_ID = None
def _gpu_identity(docker_container: str = "") -> dict:
    """Static GPU identity — card name + driver version — so the kiosk's Advanced
    GPU hover shows the admin exactly what card + driver is detected. Works on
    kubeadm (direct nvidia-smi) and docker (exec into a GPU container). Cached."""
    global _GPU_ID
    if _GPU_ID:
        return _GPU_ID
    q = ["nvidia-smi", "--query-gpu=name,driver_version", "--format=csv,noheader"]
    try:
        r = _docker("exec", docker_container, *q) if docker_container else \
            subprocess.run(q, capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            name, _, drv = r.stdout.strip().splitlines()[0].partition(",")
            info = {"gpu_name": name.strip(), "driver_version": drv.strip()}
            if info["gpu_name"]:
                _GPU_ID = info
            return info
    except Exception:
        pass
    return {}


@app.get("/gpu")
def gpu_stats():
    """GPU utilization % + VRAM (GB) + card name/driver. Powers the kiosk's Live
    Resource Usage GPU bars and STT/TTS/LLM VRAM hovers. Tries nvidia-smi DIRECTLY
    first (kubeadm: this pod gets a GPU via nvidia.com/gpu, so nvidia-smi is
    present), then falls back to `docker exec` into a GPU container (Docker box)."""
    SMI = ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total", "--format=csv,noheader,nounits"]
    # 1) direct (kubeadm GPU pod)
    try:
        r = subprocess.run(SMI, capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and r.stdout.strip():
            d = _parse_smi(r.stdout)
            if d:
                d["procs"] = _gpu_procs(d.get("vram_total_gb") or 0)
                d.update(_gpu_identity())
                return d
    except Exception:
        pass
    # 2) docker exec into a GPU container (Docker host)
    for c in ("vllm-gemma4-12b", "vllm", "riva-tts", "digitalhuman-asr", "renny"):
        try:
            r = _docker("exec", c, *SMI)
        except Exception:
            continue
        if r.returncode == 0 and r.stdout.strip():
            d = _parse_smi(r.stdout)
            if d:
                d.update(_gpu_identity(c))
                return d
    raise HTTPException(404, "nvidia-smi unavailable (no GPU in this pod and no GPU container to exec)")


@app.get("/health")
def health():
    return {"status": "ok"}


# --------------------------------------------------------------------------- #
# Self-hosted remote-mic relay  ("Install Remote Mic Proxy Service" button).
# Deploys an on-box WebSocket relay so phones can pair with the kiosk without
# UneeQ's hosted relay. The relay is dependency-free and runs on a stock
# node:20-alpine image from a ConfigMap (nothing to build or pull from a registry).
# --------------------------------------------------------------------------- #
import base64 as _b64
MIC_RELAY_NS = "uneeq"
MIC_RELAY_NAME = "mic-relay"
RELAY_SERVER_JS_B64 = "LyoKICogU2VsZi1ob3N0ZWQgcmVtb3RlLW1pYyByZWxheSDigJQgZGVwZW5kZW5jeS1mcmVlLgogKgogKiBBIGRyb3AtaW4sIG9uLWJveCByZXBsYWNlbWVudCBmb3IgVW5lZVEncyBob3N0ZWQgV2ViU29ja2V0IHJlbGF5LiBJdCBwYWlycyBhCiAqIHZpc2l0b3IncyBwaG9uZSAodGhlIC9yZW1vdGUgcGFnZSkgd2l0aCBhIGtpb3NrIGJ5IGNvbm5lY3Rpb25JZCBhbmQgZm9yd2FyZHMKICogbWVzc2FnZXMgYmV0d2VlbiB0aGVtLiBJbXBsZW1lbnRzIE9OTFkgdGhlIG1lc3NhZ2UgcHJvdG9jb2wgdGhlIGtpb3NrCiAqIChBY3Rpb25GYWN0b3J5KSBhbmQgdGhlIHJlbW90ZSBwYWdlIGFscmVhZHkgc3BlYWsg4oCUIHNlZSB0aGUgQVdTIHJlbGF5J3MKICogc3JjL2FjdGlvbnMvKiBmb3IgdGhlIHJlZmVyZW5jZSBzaGFwZXM6CiAqICAgLSBjbGllbnQgIHt0eXBlOidnZXRDb25uZWN0aW9uSWQnfSAgICAgICAgICAgICAgICAgICAgICAtPiB7dHlwZTonY29ubmVjdGlvbklkJywgY29ubmVjdGlvbklkfQogKiAgIC0gY2xpZW50ICB7dHlwZToncGVlckNvbm5lY3QnLCBwZWVySWQsIHJlbW90ZUluZm99ICAgICAgLT4gcGVlcjoge3R5cGU6J1JlZ2lzdGVyUmVtb3RlJywgcmVtb3RlSWQsIHJlbW90ZUluZm99CiAqICAgLSBjbGllbnQgIHt0eXBlOidDaGVja1BlZXJDb25uZWN0aW9uJywgcGVlcklkfSAgICAgICAgICAtPiBwZWVyOiB7dHlwZTonUGVlckNoZWNrZWQnLCBPcmlnaW4sIERlc3RpbmF0aW9ufQogKiAgIC0gY2xpZW50ICB7dHlwZToncGVlck1lc3NhZ2UnLCBwZWVySWQsIHBheWxvYWR9ICAgICAgICAgLT4gcGVlcjoge3R5cGU6J3BlZXJNZXNzYWdlJywgZGF0YTogcGF5bG9hZH0KICogICAtIGNsaWVudCAge3R5cGU6J2Nsb3NlU2Vzc2lvbid9IC8gc29ja2V0IGNsb3NlICAgICAgICAgIC0+IHBlZXJzOiB7dHlwZTonUGVlckRpc2Nvbm5lY3RlZCd9IC8ge3R5cGU6J0Nsb3NlU2Vzc2lvbid9CiAqCiAqIE5vIG5wbSBkZXBzOiBpbXBsZW1lbnRzIHRoZSBSRkMgNjQ1NSBoYW5kc2hha2UgKyB0ZXh0L2Nsb3NlL3BpbmcgZnJhbWluZyB3aXRoCiAqIE5vZGUgYnVpbHQtaW5zLCBzbyBpdCBydW5zIG9uIGEgc3RvY2sgbm9kZToyMC1hbHBpbmUgaW1hZ2UgKG1vdW50ZWQgZnJvbSBhCiAqIENvbmZpZ01hcCkgd2l0aCBub3RoaW5nIHRvIGJ1aWxkIG9yIHB1bGwgZnJvbSBhIHJlZ2lzdHJ5LgogKgogKiBOT1RFIG9uIHJlYWNoYWJpbGl0eTogYSBwaG9uZSBvbiB0aGUgU0FNRSBXaS1GaS9MQU4gcmVhY2hlcyB0aGlzIGRpcmVjdGx5LiBBCiAqIHBob25lIG9uIGNlbGx1bGFyIG5lZWRzIGEgcHVibGljIEhUVFBTL3dzcyB0dW5uZWwgdG8gdGhlIGJveCDigJQgdGhhdCdzIHRoZQogKiBvcGVyYXRvcidzIG5ldHdvcmsgc2V0dXAgKHNob3duIGluIHRoZSBraW9zaydzIFNlbGYtSG9zdGVkIGRpc2NsYWltZXIpLgogKi8KJ3VzZSBzdHJpY3QnOwpjb25zdCBodHRwID0gcmVxdWlyZSgnaHR0cCcpOwpjb25zdCBjcnlwdG8gPSByZXF1aXJlKCdjcnlwdG8nKTsKCmNvbnN0IFBPUlQgPSBwYXJzZUludChwcm9jZXNzLmVudi5QT1JUIHx8ICc4MDgwJywgMTApOwpjb25zdCBHVUlEID0gJzI1OEVBRkE1LUU5MTQtNDdEQS05NUNBLUM1QUIwREM4NUIxMSc7IC8vIFJGQyA2NDU1IG1hZ2ljCgovKiogY29ubmVjdGlvbklkIC0+IHsgc29ja2V0LCBwZWVyczpTZXQ8Y29ubklkPiB9ICovCmNvbnN0IGNvbm5zID0gbmV3IE1hcCgpOwpjb25zdCBuZXdJZCA9ICgpID0+IGNyeXB0by5yYW5kb21VVUlEKCk7CgpmdW5jdGlvbiBsb2coLi4uYSkgeyBjb25zb2xlLmxvZygnW3JlbGF5XScsIG5ldyBEYXRlKCkudG9JU09TdHJpbmcoKSwgLi4uYSk7IH0KCi8vIC0tLSBXZWJTb2NrZXQgZnJhbWUgZW5jb2RlIChzZXJ2ZXItPmNsaWVudCwgdW5tYXNrZWQpIC0tLS0tLS0tLS0tLS0tLS0tLS0tLQpmdW5jdGlvbiBlbmNvZGVGcmFtZShzdHIpIHsKICBjb25zdCBwYXlsb2FkID0gQnVmZmVyLmZyb20oc3RyLCAndXRmOCcpOwogIGNvbnN0IGxlbiA9IHBheWxvYWQubGVuZ3RoOwogIGxldCBoZWFkZXI7CiAgaWYgKGxlbiA8IDEyNikgewogICAgaGVhZGVyID0gQnVmZmVyLmZyb20oWzB4ODEsIGxlbl0pOwogIH0gZWxzZSBpZiAobGVuIDwgNjU1MzYpIHsKICAgIGhlYWRlciA9IEJ1ZmZlci5hbGxvYyg0KTsKICAgIGhlYWRlclswXSA9IDB4ODE7IGhlYWRlclsxXSA9IDEyNjsgaGVhZGVyLndyaXRlVUludDE2QkUobGVuLCAyKTsKICB9IGVsc2UgewogICAgaGVhZGVyID0gQnVmZmVyLmFsbG9jKDEwKTsKICAgIGhlYWRlclswXSA9IDB4ODE7IGhlYWRlclsxXSA9IDEyNzsgaGVhZGVyLndyaXRlQmlnVUludDY0QkUoQmlnSW50KGxlbiksIDIpOwogIH0KICByZXR1cm4gQnVmZmVyLmNvbmNhdChbaGVhZGVyLCBwYXlsb2FkXSk7Cn0KZnVuY3Rpb24gY29udHJvbEZyYW1lKG9wY29kZSkgeyByZXR1cm4gQnVmZmVyLmZyb20oWzB4ODAgfCBvcGNvZGUsIDB4MDBdKTsgfSAvLyBGSU4gKyBvcGNvZGUsIG5vIHBheWxvYWQKCmZ1bmN0aW9uIHNlbmRUbyhjb25uSWQsIG9iaikgewogIGNvbnN0IGMgPSBjb25ucy5nZXQoY29ubklkKTsKICBpZiAoIWMgfHwgYy5zb2NrZXQuZGVzdHJveWVkKSByZXR1cm4gZmFsc2U7CiAgdHJ5IHsgYy5zb2NrZXQud3JpdGUoZW5jb2RlRnJhbWUoSlNPTi5zdHJpbmdpZnkob2JqKSkpOyByZXR1cm4gdHJ1ZTsgfQogIGNhdGNoIChlKSB7IGxvZygnc2VuZCBlcnJvcicsIGUubWVzc2FnZSk7IHJldHVybiBmYWxzZTsgfQp9CgpmdW5jdGlvbiBwYWlyKGEsIGIpIHsKICBjb25ucy5nZXQoYSk/LnBlZXJzLmFkZChiKTsKICBjb25ucy5nZXQoYik/LnBlZXJzLmFkZChhKTsKfQoKZnVuY3Rpb24gaGFuZGxlTWVzc2FnZShjb25uSWQsIG1zZykgewogIGxldCBtOyB0cnkgeyBtID0gSlNPTi5wYXJzZShtc2cpOyB9IGNhdGNoIHsgcmV0dXJuOyB9CiAgc3dpdGNoIChtLnR5cGUpIHsKICAgIGNhc2UgJ2dldENvbm5lY3Rpb25JZCc6CiAgICAgIHNlbmRUbyhjb25uSWQsIHsgdHlwZTogJ2Nvbm5lY3Rpb25JZCcsIGNvbm5lY3Rpb25JZDogY29ubklkIH0pOwogICAgICBicmVhazsKICAgIGNhc2UgJ3BlZXJDb25uZWN0JzoKICAgICAgcGFpcihjb25uSWQsIG0ucGVlcklkKTsKICAgICAgc2VuZFRvKG0ucGVlcklkLCB7IHR5cGU6ICdSZWdpc3RlclJlbW90ZScsIHJlbW90ZUlkOiBjb25uSWQsIHJlbW90ZUluZm86IG0ucmVtb3RlSW5mbyB9KTsKICAgICAgYnJlYWs7CiAgICBjYXNlICdDaGVja1BlZXJDb25uZWN0aW9uJzoKICAgICAgc2VuZFRvKG0ucGVlcklkLCB7IHR5cGU6ICdQZWVyQ2hlY2tlZCcsIE9yaWdpbjogY29ubklkLCBEZXN0aW5hdGlvbjogbS5wZWVySWQgfSk7CiAgICAgIGJyZWFrOwogICAgY2FzZSAncGVlck1lc3NhZ2UnOgogICAgICBwYWlyKGNvbm5JZCwgbS5wZWVySWQpOwogICAgICBzZW5kVG8obS5wZWVySWQsIHsgdHlwZTogJ3BlZXJNZXNzYWdlJywgZGF0YTogbS5wYXlsb2FkIH0pOwogICAgICBicmVhazsKICAgIGNhc2UgJ2Nsb3NlU2Vzc2lvbic6CiAgICAgIC8vIG1pcnJvciBBV1M6IHRlbGwgcGFpcmVkIHBlZXJzIHRoZSBzZXNzaW9uIGNsb3NlZAogICAgICBmb3IgKGNvbnN0IHAgb2YgY29ubnMuZ2V0KGNvbm5JZCk/LnBlZXJzIHx8IFtdKSBzZW5kVG8ocCwgeyB0eXBlOiAnQ2xvc2VTZXNzaW9uJyB9KTsKICAgICAgYnJlYWs7CiAgICBjYXNlICdwZWVyQXVkaW9UcmFuc2NyaWJlJzoKICAgICAgLy8gTm90IHN1cHBvcnRlZCBvbi1ib3g6IE1pbmlQcmVtIHVzZXMgdGhlIGtpb3NrJ3Mgb3duIFJpdmEgU1RULCBub3QgdGhlCiAgICAgIC8vIHJlbGF5J3MgRGVlcGdyYW0gdG9rZW4gcGF0aC4gSWdub3JlIHF1aWV0bHkuCiAgICAgIGJyZWFrOwogICAgZGVmYXVsdDoKICAgICAgYnJlYWs7CiAgfQp9CgpmdW5jdGlvbiBkcm9wQ29ubihjb25uSWQpIHsKICBjb25zdCBjID0gY29ubnMuZ2V0KGNvbm5JZCk7CiAgaWYgKCFjKSByZXR1cm47CiAgZm9yIChjb25zdCBwIG9mIGMucGVlcnMpIHNlbmRUbyhwLCB7IHR5cGU6ICdQZWVyRGlzY29ubmVjdGVkJyB9KTsKICBjb25ucy5kZWxldGUoY29ubklkKTsKICBsb2coJ2Rpc2Nvbm5lY3QnLCBjb25uSWQsICdsaXZlOicsIGNvbm5zLnNpemUpOwp9CgovLyAtLS0gUGVyLXNvY2tldCBmcmFtZSBwYXJzZXIgKGhhbmRsZXMgbWFza2luZyArIGZyYWdtZW50YXRpb24gYnVmZmVyKSAtLS0tLS0KZnVuY3Rpb24gYXR0YWNoUGFyc2VyKGNvbm5JZCwgc29ja2V0KSB7CiAgbGV0IGJ1ZiA9IEJ1ZmZlci5hbGxvYygwKTsKICBzb2NrZXQub24oJ2RhdGEnLCAoY2h1bmspID0+IHsKICAgIGJ1ZiA9IEJ1ZmZlci5jb25jYXQoW2J1ZiwgY2h1bmtdKTsKICAgIHdoaWxlIChidWYubGVuZ3RoID49IDIpIHsKICAgICAgY29uc3QgZmluID0gKGJ1ZlswXSAmIDB4ODApICE9PSAwOwogICAgICBjb25zdCBvcGNvZGUgPSBidWZbMF0gJiAweDBmOwogICAgICBjb25zdCBtYXNrZWQgPSAoYnVmWzFdICYgMHg4MCkgIT09IDA7CiAgICAgIGxldCBsZW4gPSBidWZbMV0gJiAweDdmOwogICAgICBsZXQgb2Zmc2V0ID0gMjsKICAgICAgaWYgKGxlbiA9PT0gMTI2KSB7IGlmIChidWYubGVuZ3RoIDwgNCkgcmV0dXJuOyBsZW4gPSBidWYucmVhZFVJbnQxNkJFKDIpOyBvZmZzZXQgPSA0OyB9CiAgICAgIGVsc2UgaWYgKGxlbiA9PT0gMTI3KSB7IGlmIChidWYubGVuZ3RoIDwgMTApIHJldHVybjsgbGVuID0gTnVtYmVyKGJ1Zi5yZWFkQmlnVUludDY0QkUoMikpOyBvZmZzZXQgPSAxMDsgfQogICAgICBjb25zdCBtYXNrTGVuID0gbWFza2VkID8gNCA6IDA7CiAgICAgIGlmIChidWYubGVuZ3RoIDwgb2Zmc2V0ICsgbWFza0xlbiArIGxlbikgcmV0dXJuOyAvLyB3YWl0IGZvciBmdWxsIGZyYW1lCiAgICAgIGNvbnN0IG1hc2sgPSBtYXNrZWQgPyBidWYuc2xpY2Uob2Zmc2V0LCBvZmZzZXQgKyBtYXNrTGVuKSA6IG51bGw7CiAgICAgIGNvbnN0IGRhdGFTdGFydCA9IG9mZnNldCArIG1hc2tMZW47CiAgICAgIGNvbnN0IGRhdGEgPSBidWYuc2xpY2UoZGF0YVN0YXJ0LCBkYXRhU3RhcnQgKyBsZW4pOwogICAgICBpZiAobWFzaykgZm9yIChsZXQgaSA9IDA7IGkgPCBkYXRhLmxlbmd0aDsgaSsrKSBkYXRhW2ldIF49IG1hc2tbaSAmIDNdOwogICAgICBidWYgPSBidWYuc2xpY2UoZGF0YVN0YXJ0ICsgbGVuKTsKCiAgICAgIGlmIChvcGNvZGUgPT09IDB4OCkgeyBzb2NrZXQuZW5kKGNvbnRyb2xGcmFtZSgweDgpKTsgZHJvcENvbm4oY29ubklkKTsgcmV0dXJuOyB9IC8vIGNsb3NlCiAgICAgIGVsc2UgaWYgKG9wY29kZSA9PT0gMHg5KSB7IHNvY2tldC53cml0ZShjb250cm9sRnJhbWUoMHhBKSk7IH0gICAgICAgICAgICAgICAgICAgIC8vIHBpbmcgLT4gcG9uZwogICAgICBlbHNlIGlmIChvcGNvZGUgPT09IDB4MSAmJiBmaW4pIHsgaGFuZGxlTWVzc2FnZShjb25uSWQsIGRhdGEudG9TdHJpbmcoJ3V0ZjgnKSk7IH0gLy8gdGV4dAogICAgICAvLyAoYmluYXJ5L2NvbnRpbnVhdGlvbiBmcmFtZXMgYXJlIG5vdCB1c2VkIGJ5IHRoaXMgcHJvdG9jb2wpCiAgICB9CiAgfSk7Cn0KCmNvbnN0IHNlcnZlciA9IGh0dHAuY3JlYXRlU2VydmVyKChyZXEsIHJlcykgPT4gewogIC8vIFBsYWluIEhUVFAgaGVhbHRoIGNoZWNrIChmb3IgazhzIHByb2JlcykuCiAgaWYgKHJlcS51cmwgPT09ICcvaGVhbHRoJyB8fCByZXEudXJsID09PSAnLycpIHsgcmVzLndyaXRlSGVhZCgyMDAsIHsgJ0NvbnRlbnQtVHlwZSc6ICd0ZXh0L3BsYWluJyB9KTsgcmVzLmVuZCgnb2snKTsgcmV0dXJuOyB9CiAgcmVzLndyaXRlSGVhZCg0MDQpOyByZXMuZW5kKCk7Cn0pOwoKc2VydmVyLm9uKCd1cGdyYWRlJywgKHJlcSwgc29ja2V0KSA9PiB7CiAgY29uc3Qga2V5ID0gcmVxLmhlYWRlcnNbJ3NlYy13ZWJzb2NrZXQta2V5J107CiAgaWYgKCFrZXkpIHsgc29ja2V0LmRlc3Ryb3koKTsgcmV0dXJuOyB9CiAgY29uc3QgYWNjZXB0ID0gY3J5cHRvLmNyZWF0ZUhhc2goJ3NoYTEnKS51cGRhdGUoa2V5ICsgR1VJRCkuZGlnZXN0KCdiYXNlNjQnKTsKICBzb2NrZXQud3JpdGUoCiAgICAnSFRUUC8xLjEgMTAxIFN3aXRjaGluZyBQcm90b2NvbHNcclxuJyArCiAgICAnVXBncmFkZTogd2Vic29ja2V0XHJcbicgKwogICAgJ0Nvbm5lY3Rpb246IFVwZ3JhZGVcclxuJyArCiAgICBgU2VjLVdlYlNvY2tldC1BY2NlcHQ6ICR7YWNjZXB0fVxyXG5cclxuYAogICk7CiAgc29ja2V0LnNldE5vRGVsYXkodHJ1ZSk7CiAgY29uc3QgY29ubklkID0gbmV3SWQoKTsKICBjb25ucy5zZXQoY29ubklkLCB7IHNvY2tldCwgcGVlcnM6IG5ldyBTZXQoKSB9KTsKICBsb2coJ2Nvbm5lY3QnLCBjb25uSWQsICdsaXZlOicsIGNvbm5zLnNpemUpOwogIGF0dGFjaFBhcnNlcihjb25uSWQsIHNvY2tldCk7CiAgc29ja2V0Lm9uKCdjbG9zZScsICgpID0+IGRyb3BDb25uKGNvbm5JZCkpOwogIHNvY2tldC5vbignZXJyb3InLCAoKSA9PiBkcm9wQ29ubihjb25uSWQpKTsKfSk7CgpzZXJ2ZXIubGlzdGVuKFBPUlQsICcwLjAuMC4wJywgKCkgPT4gbG9nKGByZW1vdGUtbWljIHJlbGF5IGxpc3RlbmluZyBvbiA6JHtQT1JUfWApKTsK"

_MIC_RELAY_MANIFESTS = """
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mic-relay
  namespace: uneeq
  labels: { app: mic-relay }
spec:
  replicas: 1
  selector: { matchLabels: { app: mic-relay } }
  template:
    metadata: { labels: { app: mic-relay } }
    spec:
      containers:
      - name: relay
        image: node:20-alpine
        command: ["node", "/app/server.js"]
        env:
        - { name: PORT, value: "8080" }
        ports: [{ containerPort: 8080 }]
        volumeMounts: [{ name: src, mountPath: /app }]
        readinessProbe: { httpGet: { path: /health, port: 8080 }, initialDelaySeconds: 3, periodSeconds: 5 }
        livenessProbe: { httpGet: { path: /health, port: 8080 }, initialDelaySeconds: 10, periodSeconds: 20 }
      volumes:
      - name: src
        configMap: { name: mic-relay-src }
---
apiVersion: v1
kind: Service
metadata:
  name: mic-relay
  namespace: uneeq
  labels: { app: mic-relay }
spec:
  type: NodePort
  selector: { app: mic-relay }
  ports: [{ name: ws, port: 8080, targetPort: 8080 }]
"""


def _kubectl_apply(manifest, timeout=30):
    return subprocess.run(["kubectl", "apply", "-f", "-"], input=manifest,
                          capture_output=True, text=True, timeout=timeout)


def _node_ip():
    try:
        r = _kubectl("get", "nodes", "-o",
                     "jsonpath={.items[0].status.addresses[?(@.type==\'InternalIP\')].address}")
        return r.stdout.strip().split()[0] if r.stdout.strip() else ""
    except Exception:
        return ""


@app.get("/node-ip")
def node_ip():
    """The box's LAN InternalIP, so the kiosk can build a phone-reachable remote-mic
    QR URL instead of falling back to localhost (which a phone can't reach)."""
    return {"ip": _node_ip()}


def _mic_relay_nodeport():
    try:
        r = _kubectl("get", "svc", MIC_RELAY_NAME, "-n", MIC_RELAY_NS, "-o",
                     "jsonpath={.spec.ports[0].nodePort}")
        if r.returncode == 0 and r.stdout.strip().isdigit():
            return int(r.stdout.strip())
    except Exception:
        pass
    return None


@app.post("/mic-proxy/install")
def mic_proxy_install():
    """Deploy the on-box remote-mic relay (ConfigMap + Deployment + NodePort)."""
    if _runtime() in ("docker", "unknown"):
        raise HTTPException(400, "The on-box relay install requires the kubeadm/CNS runtime.")
    js = _b64.b64decode(RELAY_SERVER_JS_B64).decode("utf-8")
    with open("/tmp/mic-relay-server.js", "w") as f:
        f.write(js)
    cm = subprocess.run(["kubectl", "create", "configmap", "mic-relay-src", "-n", MIC_RELAY_NS,
                         "--from-file=server.js=/tmp/mic-relay-server.js",
                         "--dry-run=client", "-o", "yaml"], capture_output=True, text=True, timeout=20)
    if cm.returncode != 0:
        raise HTTPException(500, f"configmap render failed: {cm.stderr.strip()}")
    ap = _kubectl_apply(cm.stdout)
    if ap.returncode != 0:
        raise HTTPException(500, f"configmap apply failed: {ap.stderr.strip()}")
    ap2 = _kubectl_apply(_MIC_RELAY_MANIFESTS)
    if ap2.returncode != 0:
        raise HTTPException(500, f"relay apply failed: {ap2.stderr.strip()}")
    _kubectl("rollout", "restart", "deploy", MIC_RELAY_NAME, "-n", MIC_RELAY_NS, timeout=20)
    return {"ok": True, "state": "installing"}


@app.get("/mic-proxy/status")
def mic_proxy_status():
    """Report whether the on-box relay is running + its ws:// URL for the kiosk."""
    if _runtime() in ("docker", "unknown"):
        return {"state": "unsupported"}
    g = _kubectl("get", "deploy", MIC_RELAY_NAME, "-n", MIC_RELAY_NS, "-o",
                 "jsonpath={.status.readyReplicas}/{.status.replicas}")
    if g.returncode != 0 or not g.stdout.strip() or g.stdout.strip().startswith("/"):
        return {"state": "absent"}
    ready, _, total = g.stdout.strip().partition("/")
    np = _mic_relay_nodeport()
    ip = _node_ip()
    url = f"ws://{ip}:{np}" if (ip and np) else None
    running = ready.isdigit() and int(ready) >= 1
    return {"state": "running" if running else "pending",
            "ready": ready, "total": total, "url": url, "nodePort": np, "nodeIp": ip}

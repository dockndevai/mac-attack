"""Mac Attack Laya sidecar: abstract game state in, calibrated typed decisions out.

Local only (127.0.0.1). Receives JSON describing anonymous people (normalized boxes, motion,
dwell time). Never receives or stores camera frames. The Swift app samples the returned
probabilities; this server does not pick the final action.

    python server.py [--port 8777] [--parent-pid PID]
"""

import argparse
import gc
import os
import signal
import threading
import time
from typing import Any, Dict, List, Optional

from fastapi import FastAPI
from pydantic import BaseModel

from questions import build_questions, situation

app = FastAPI(title="Mac Attack Laya Director")
state: Dict[str, Any] = {"state": "loading", "error": None, "device": None, "model": "english",
                         "decisions": 0, "last_latency_ms": None, "avg_latency_ms": None,
                         "memory_mb": 0, "sleeps": 0}
_router = None
_lat: List[float] = []
_last_use = time.time()
_lock = threading.Lock()

# The checkpoint costs ~2.4 GB resident. The game only needs it every few seconds while someone is
# actually on screen, so drop it when unused and load it again on demand: the game falls back to its
# local director for the few seconds a reload takes.
IDLE_UNLOAD_SECONDS = float(os.environ.get("LAYA_IDLE_UNLOAD", 180))


def _rss_mb() -> int:
    try:
        import resource
        # macOS reports maxrss in bytes
        return int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / (1024 * 1024))
    except Exception:
        return 0


def _release_memory():
    gc.collect()
    try:
        import torch
        if torch.backends.mps.is_available():
            torch.mps.empty_cache()
        elif torch.cuda.is_available():
            torch.cuda.empty_cache()
    except Exception:
        pass


def _warm_up():
    global _router
    with _lock:
        if _router is not None:
            return
        state["state"] = "loading"
        try:
            from laya import Router

            r = Router(max_loaded=1)
            agent = r.load("english")
            state["device"] = str(getattr(agent, "device", "unknown"))
            # one throwaway pass so the first real decision is not paying for kernel warm-up
            demo = {"people": [], "people_count": 0, "idle_seconds": 1}
            r.predict(situation(demo), build_questions(demo), model="english")
            _router = r
            state["state"] = "ready"
            state["memory_mb"] = _rss_mb()
        except Exception as e:  # surfaced via /status; the game falls back locally
            state["state"] = "error"
            state["error"] = repr(e)


def _sleep_when_idle():
    """Unload the checkpoint after a spell with no decisions, and hand the memory back."""
    global _router
    while True:
        time.sleep(15)
        if _router is None or IDLE_UNLOAD_SECONDS <= 0:
            continue
        if time.time() - _last_use < IDLE_UNLOAD_SECONDS:
            continue
        with _lock:
            if _router is None:
                continue
            try:
                _router.unload()
            except Exception:
                pass
            _router = None
        _release_memory()
        state["state"] = "sleeping"
        state["sleeps"] += 1
        state["memory_mb"] = _rss_mb()


class GameStateIn(BaseModel):
    people: List[Dict[str, Any]] = []
    people_count: int = 0
    scene_state: str = "idle"
    idle_seconds: float = 0
    elapsed: float = 0
    combo: int = 0
    difficulty: float = 0
    chaos: bool = False
    trigger: str = "timer"
    last_event: Optional[Dict[str, Any]] = None


@app.get("/status")
def status():
    return state


@app.post("/decide")
def decide(body: GameStateIn, delay: float = 0.0):
    global _last_use
    if delay > 0:  # debug hook to simulate a slow director
        time.sleep(min(delay, 10.0))
    _last_use = time.time()
    if _router is None:
        # asleep or still starting: wake up in the background and let the game fall back this tick
        if state["state"] in ("sleeping", "error"):
            threading.Thread(target=_warm_up, daemon=True).start()
        return {"error": "not ready", "state": state["state"]}
    game = body.model_dump()
    # Laya reads the state once per question, so a compact text summary of the abstract
    # state (not the raw JSON) roughly halves latency with no loss of information.
    text = situation(game)
    t0 = time.perf_counter()
    result = _router.predict(text, build_questions(game), model="english")
    ms = round((time.perf_counter() - t0) * 1000, 1)
    _lat.append(ms)
    del _lat[:-50]
    state["decisions"] += 1
    state["last_latency_ms"] = ms
    state["avg_latency_ms"] = round(sum(_lat) / len(_lat), 1)
    _last_use = time.time()
    return {"answers": result["answers"], "situation": text,
            "latency_ms": ms, "device": state["device"]}


def _shutdown(reason: str):
    """Exit without yanking the GPU out from under Metal: a hard os._exit() in the middle of an
    MPS encode aborts with a Metal assertion (SIGABRT) and leaves a crash report behind."""
    with _lock:
        global _router
        if _router is not None:
            try:
                _router.unload()
            except Exception:
                pass
            _router = None
    _release_memory()
    os.kill(os.getpid(), signal.SIGTERM)          # let uvicorn close its sockets
    time.sleep(5)
    os._exit(0)                                    # last resort if it hangs


def _watch_parent(pid: int):
    # If the game dies without cleaning up, don't leave a 2 GB model process running.
    while True:
        time.sleep(2)
        try:
            os.kill(pid, 0)
        except OSError:
            _shutdown("parent gone")


if __name__ == "__main__":
    import uvicorn

    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8777)
    ap.add_argument("--parent-pid", type=int, default=0)
    args = ap.parse_args()
    if args.parent_pid:
        threading.Thread(target=_watch_parent, args=(args.parent_pid,), daemon=True).start()
    threading.Thread(target=_warm_up, daemon=True).start()
    threading.Thread(target=_sleep_when_idle, daemon=True).start()
    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")

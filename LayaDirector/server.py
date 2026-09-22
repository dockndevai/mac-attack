"""Mac Attack Laya sidecar: abstract game state in, calibrated typed decisions out.

Local only (127.0.0.1). Receives JSON describing anonymous people (normalized boxes, motion,
dwell time). Never receives or stores camera frames. The Swift app samples the returned
probabilities; this server does not pick the final action.

    python server.py [--port 8777] [--parent-pid PID]
"""

import argparse
import os
import threading
import time
from typing import Any, Dict, List, Optional

from fastapi import FastAPI
from pydantic import BaseModel

from questions import build_questions, situation

app = FastAPI(title="Mac Attack Laya Director")
state: Dict[str, Any] = {"state": "loading", "error": None, "device": None, "model": "english",
                         "decisions": 0, "last_latency_ms": None, "avg_latency_ms": None}
_router = None
_lat: List[float] = []


def _warm_up():
    global _router
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
    except Exception as e:  # surfaced via /status; the game falls back locally
        state["state"] = "error"
        state["error"] = repr(e)


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
    if delay > 0:  # debug hook to simulate a slow director
        time.sleep(min(delay, 10.0))
    if _router is None:
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
    return {"answers": result["answers"], "situation": text,
            "latency_ms": ms, "device": state["device"]}


def _watch_parent(pid: int):
    # If the game dies without cleaning up, don't leave a 1 GB model process running.
    while True:
        time.sleep(2)
        try:
            os.kill(pid, 0)
        except OSError:
            os._exit(0)


if __name__ == "__main__":
    import uvicorn

    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8777)
    ap.add_argument("--parent-pid", type=int, default=0)
    args = ap.parse_args()
    if args.parent_pid:
        threading.Thread(target=_watch_parent, args=(args.parent_pid,), daemon=True).start()
    threading.Thread(target=_warm_up, daemon=True).start()
    uvicorn.run(app, host="127.0.0.1", port=args.port, log_level="warning")

import os
import time
import threading
from flask import Flask, jsonify, request

app = Flask(__name__)

# Simulated slow initialization (e.g. loading config, warming a cache, etc.)
STARTUP_DELAY_SECONDS = int(os.environ.get("STARTUP_DELAY_SECONDS", "20"))
START_TIME = time.time()

state = {
    "blocked": False,       # once True, /healthz fails forever -> liveness restart
    "unready_until": 0.0,   # timestamp until which /ready fails -> readiness only
}
state_lock = threading.Lock()


def is_starting() -> bool:
    return (time.time() - START_TIME) < STARTUP_DELAY_SECONDS


@app.route("/")
def index():
    return jsonify(
        status="ok",
        uptime_seconds=round(time.time() - START_TIME, 1),
        starting=is_starting(),
    )


@app.route("/healthz")
def healthz():
    """Used by BOTH startupProbe and livenessProbe.

    While the app is "starting", this returns 503: the startupProbe
    keeps failing (which is expected and does NOT count against liveness,
    since Kubernetes disables liveness/readiness until startup succeeds).

    Once started, this only fails if a deadlock has been simulated via
    POST /simulate/blocked. A failing /healthz here should lead to a
    container restart.
    """
    with state_lock:
        blocked = state["blocked"]

    if is_starting():
        remaining = round(STARTUP_DELAY_SECONDS - (time.time() - START_TIME), 1)
        return jsonify(status="starting", detail=f"initializing, {remaining}s left"), 503

    if blocked:
        return jsonify(status="blocked", detail="simulated deadlock, waiting for restart"), 500

    return jsonify(status="healthy"), 200


@app.route("/ready")
def ready():
    """Used ONLY by readinessProbe.

    A failure here should NOT restart the container. It should only
    remove the Pod from the Service's Endpoints until this returns 200
    again.
    """
    with state_lock:
        unready_until = state["unready_until"]

    if is_starting():
        return jsonify(status="not-ready", detail="app is still initializing"), 503

    if time.time() < unready_until:
        remaining = round(unready_until - time.time(), 1)
        return jsonify(status="not-ready", detail=f"simulated overload, {remaining}s left"), 503

    return jsonify(status="ready"), 200


@app.route("/simulate/blocked", methods=["POST"])
def simulate_blocked():
    """Simulate a stuck process: /healthz will fail forever until the
    kubelet restarts the container (livenessProbe)."""
    with state_lock:
        state["blocked"] = True
    return jsonify(status="ok", detail="app is now deadlocked, liveness will fail"), 200


@app.route("/simulate/unready", methods=["POST"])
def simulate_unready():
    """Simulate a temporary overload: /ready fails for N seconds then
    recovers on its own, WITHOUT any restart (readinessProbe only)."""
    duration = int(request.args.get("duration", "30"))
    with state_lock:
        state["unready_until"] = time.time() + duration
    return jsonify(status="ok", detail=f"not-ready for {duration}s, no restart expected"), 200


@app.route("/reset", methods=["POST"])
def reset():
    with state_lock:
        state["blocked"] = False
        state["unready_until"] = 0.0
    return jsonify(status="ok", detail="state reset"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import time
import fcntl
from pathlib import Path
from typing import Any


HOME = Path.home()
ROOT = HOME / "projects" / "cento"
CENTO = HOME / "bin" / "cento"
RUN_ROOT = ROOT / "workspace" / "runs" / "cluster-jobs"
CACHE_PATH = HOME / ".cache" / "cento" / "polybar-cluster.json"
LOCK_PATH = HOME / ".cache" / "cento" / "polybar-cluster.lock"
CODEX_WINDOW_PATH = HOME / ".local" / "state" / "cento" / "codex-window-start.json"
CODEX_HISTORY = HOME / ".codex" / "history.jsonl"

WINDOW_SECONDS = 5 * 60 * 60
CACHE_TTL_SECONDS = 25

GREEN = "#61C766"
RED = "#EC7875"
YELLOW = "#FDD835"
BLUE = "#42A5F5"
CYAN = "#4DD0E1"
PURPLE = "#BA68C8"
FG = "#93A1A1"


def color(text: str, value: str) -> str:
    return f"%{{F{value}}}{text}%{{F-}}"


def run_command(args: list[str], timeout: float) -> str:
    try:
        result = subprocess.run(
            args,
            cwd=str(ROOT),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except Exception:
        return ""
    return "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())


def read_cache() -> dict[str, Any]:
    try:
        data = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def write_cache(data: dict[str, Any]) -> None:
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        CACHE_PATH.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    except Exception:
        pass


def cluster_status(cache: dict[str, Any]) -> dict[str, bool]:
    output = run_command([str(CENTO), "cluster", "status"], timeout=6)
    statuses = {"macos": False, "linux": False, "iphone": False}
    if output:
        for raw in output.splitlines():
            parts = raw.split()
            if len(parts) < 2:
                continue
            node = parts[0].strip().lower()
            state = parts[1].strip().lower()
            if node in statuses:
                statuses[node] = state in {"connected", "online", "ok", "up", "healthy"}
        cache["nodes"] = statuses
        return statuses
    cached = cache.get("nodes")
    if isinstance(cached, dict):
        return {node: bool(cached.get(node)) for node in statuses}
    return statuses


def memory_summary(cache: dict[str, Any]) -> tuple[str, float | None]:
    output = run_command([str(CENTO), "cluster", "metric", "memory"], timeout=6)
    match = re.search(r"Cluster memory:\s*([0-9.]+)GB used\s*/\s*([0-9.]+)GB total", output)
    if match:
        used = float(match.group(1))
        total = float(match.group(2))
        text = f"{used:g}/{total:g}G"
        ratio = used / total if total else None
        cache["memory"] = {"text": text, "ratio": ratio}
        return text, ratio
    cached = cache.get("memory")
    if isinstance(cached, dict):
        text = str(cached.get("text") or "--/--G")
        ratio = cached.get("ratio")
        return text, ratio if isinstance(ratio, (int, float)) else None
    return "--/--G", None


def cache_is_fresh(cache: dict[str, Any]) -> bool:
    updated_at = cache.get("expensive_updated_at")
    return isinstance(updated_at, int) and time.time() - updated_at < CACHE_TTL_SECONDS


def refresh_expensive_cache() -> dict[str, Any]:
    cache = read_cache()
    if cache_is_fresh(cache):
        return cache

    try:
        LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
        with LOCK_PATH.open("w", encoding="utf-8") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return cache
            cache = read_cache()
            if cache_is_fresh(cache):
                return cache
            cluster_status(cache)
            memory_summary(cache)
            cache["expensive_updated_at"] = int(time.time())
            write_cache(cache)
            return cache
    except Exception:
        return cache


def cached_node_statuses(cache: dict[str, Any]) -> dict[str, bool]:
    statuses = {"macos": False, "linux": False, "iphone": False}
    cached = cache.get("nodes")
    if not isinstance(cached, dict):
        return statuses
    return {node: bool(cached.get(node)) for node in statuses}


def cached_memory_summary(cache: dict[str, Any]) -> tuple[str, float | None]:
    cached = cache.get("memory")
    if not isinstance(cached, dict):
        return "--/--G", None
    text = str(cached.get("text") or "--/--G")
    ratio = cached.get("ratio")
    return text, ratio if isinstance(ratio, (int, float)) else None


def active_task_count() -> int:
    active_statuses = {"planned", "queued", "running", "in-progress", "in_progress"}
    count = 0
    for job_path in RUN_ROOT.glob("*/job.json"):
        try:
            job = json.loads(job_path.read_text(encoding="utf-8"))
        except Exception:
            continue
        status = str(job.get("status", "planned")).lower()
        if status not in active_statuses:
            continue
        tasks = job.get("tasks", [])
        count += len(tasks) if isinstance(tasks, list) else 1
    return count


def history_window_start(now: float) -> float | None:
    if not CODEX_HISTORY.exists():
        return None
    start: float | None = None
    try:
        lines = CODEX_HISTORY.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception:
        return None
    for line in lines:
        try:
            item = json.loads(line)
            ts = float(item.get("ts"))
        except Exception:
            continue
        if 0 <= now - ts <= WINDOW_SECONDS:
            start = ts if start is None else min(start, ts)
    return start


def codex_window_remaining_percent() -> int:
    now = time.time()
    start: float | None = None
    try:
        data = json.loads(CODEX_WINDOW_PATH.read_text(encoding="utf-8"))
        raw = data.get("start_ts")
        if isinstance(raw, (int, float)) and 0 <= now - float(raw) <= WINDOW_SECONDS:
            start = float(raw)
    except Exception:
        start = None

    if start is None:
        start = history_window_start(now) or now
        try:
            CODEX_WINDOW_PATH.parent.mkdir(parents=True, exist_ok=True)
            CODEX_WINDOW_PATH.write_text(json.dumps({"start_ts": start}, indent=2) + "\n", encoding="utf-8")
        except Exception:
            pass

    remaining = max(0.0, WINDOW_SECONDS - (now - start))
    return int(round((remaining / WINDOW_SECONDS) * 100))


def dot(is_ok: bool) -> str:
    return color("●", GREEN if is_ok else RED)


def main() -> int:
    cache = refresh_expensive_cache()
    nodes = cached_node_statuses(cache)
    memory_text, memory_ratio = cached_memory_summary(cache)
    jobs = active_task_count()
    codex_pct = codex_window_remaining_percent()
    cache["updated_at"] = int(time.time())
    write_cache(cache)

    memory_color = GREEN
    if memory_ratio is not None and memory_ratio >= 0.85:
        memory_color = RED
    elif memory_ratio is not None and memory_ratio >= 0.70:
        memory_color = YELLOW

    codex_color = GREEN if codex_pct >= 50 else YELLOW if codex_pct >= 20 else RED
    jobs_color = YELLOW if jobs else FG

    parts = [
        color("", BLUE),
        dot(nodes["macos"]),
        color("", YELLOW),
        dot(nodes["linux"]),
        color("", CYAN),
        dot(nodes["iphone"]),
        color(f"{jobs} jobs", jobs_color),
        color(memory_text, memory_color),
        color(f"{codex_pct}%", codex_color),
    ]
    print(" ".join(parts))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

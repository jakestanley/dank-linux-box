#!/usr/bin/env python3

"""
Keep the dummy HDMI output active only when the primary monitor is unavailable.
This avoids refresh-rate caps while still providing a display for Sunshine streaming.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import datetime
from typing import Any

PRIMARY_OUTPUT = "DP-3"
DUMMY_OUTPUT = "HDMI-A-1"
DEBUG = os.environ.get("DISPLAY_SYNC_DEBUG") == "1"
POLL_SECONDS = 3


def log_debug(message: str) -> None:
    if DEBUG:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[display-sync] {timestamp} {message}", file=sys.stderr, flush=True)


def parse_embedded_json(text: str) -> dict[str, Any] | list[Any] | None:
    decoder = json.JSONDecoder()
    for marker in ("{", "["):
        start = text.find(marker)
        while start != -1:
            try:
                payload, _ = decoder.raw_decode(text[start:])
                if isinstance(payload, (dict, list)):
                    return payload
            except json.JSONDecodeError:
                pass
            start = text.find(marker, start + 1)
    return None


def run_kscreen_json() -> dict[str, Any] | list[Any] | None:
    commands = (["kscreen-doctor", "--json", "-o"], ["kscreen-doctor", "-j", "-o"])
    for command in commands:
        try:
            completed = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=False,
            )
            payload = parse_embedded_json(completed.stdout)
            if payload is None and completed.stderr:
                payload = parse_embedded_json(completed.stderr)
            if payload is not None:
                return payload
            if DEBUG:
                log_debug(f"no JSON payload found ({' '.join(command)})")
        except Exception as exc:  # quiet by default during session transitions
            if DEBUG:
                log_debug(f"query failed ({' '.join(command)}): {exc}")
    return None


def is_primary_enabled() -> bool:
    payload = run_kscreen_json()
    if payload is None:
        return False

    outputs = payload.get("outputs", []) if isinstance(payload, dict) else payload
    if not isinstance(outputs, list):
        return False

    for output in outputs:
        if isinstance(output, dict) and output.get("name") == PRIMARY_OUTPUT:
            return bool(output.get("enabled"))
    return False


def set_dummy_enabled(enable: bool) -> None:
    action = "enable" if enable else "disable"
    command = ["kscreen-doctor", f"output.{DUMMY_OUTPUT}.{action}"]
    try:
        if DEBUG:
            subprocess.run(command, check=True)
        else:
            subprocess.run(
                command,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    except Exception as exc:  # quiet by default during session transitions
        if DEBUG:
            log_debug(f"command failed ({' '.join(command)}): {exc}")


def main() -> None:
    last_state: str | None = None
    while True:
        primary_enabled = is_primary_enabled()
        primary_state = "enabled" if primary_enabled else "not-enabled"
        dummy_should_enable = not primary_enabled

        if primary_state != last_state:
            action = "enable" if dummy_should_enable else "disable"
            log_debug(f"primary {PRIMARY_OUTPUT} is {primary_state}; {action} {DUMMY_OUTPUT}")
            last_state = primary_state

        set_dummy_enabled(dummy_should_enable)
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Say whether one Codex command hook is enabled and trusted."""

import argparse
import json
import queue
import subprocess
import sys
import threading
import time


def send(process: subprocess.Popen, message: dict) -> None:
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()


def receive(responses: queue.Queue, response_id: int, timeout: float) -> dict:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            message = responses.get(timeout=deadline - time.monotonic())
        except queue.Empty:
            break
        if message.get("id") == response_id:
            return message
    raise TimeoutError(f"Codex app-server did not answer request {response_id}")


def hook_status(command: str, cwd: str) -> str:
    process = subprocess.Popen(
        ["codex", "app-server", "--stdio"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    responses = queue.Queue()

    def read_responses() -> None:
        for line in process.stdout:
            try:
                responses.put(json.loads(line))
            except json.JSONDecodeError:
                continue

    threading.Thread(target=read_responses, daemon=True).start()
    try:
        send(process, {
            "method": "initialize",
            "id": 0,
            "params": {
                "clientInfo": {
                    "name": "agent-rules-install",
                    "title": "Agent rules installer",
                    "version": "1",
                }
            },
        })
        receive(responses, 0, 10)
        send(process, {"method": "initialized", "params": {}})
        send(process, {"method": "hooks/list", "id": 1, "params": {"cwds": [cwd]}})
        response = receive(responses, 1, 10)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()

    hooks = [
        hook
        for entry in response.get("result", {}).get("data", [])
        for hook in entry.get("hooks", [])
        if hook.get("eventName") == "userPromptSubmit"
        and hook.get("command") == command
    ]
    if not hooks:
        return "missing"
    if any(
        hook.get("enabled") is True
        and hook.get("trustStatus") in {"trusted", "managed"}
        for hook in hooks
    ):
        return "ready"
    if any(hook.get("enabled") is False for hook in hooks):
        return "disabled"
    return "untrusted"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--command", required=True)
    parser.add_argument("--cwd", required=True)
    args = parser.parse_args()
    try:
        status = hook_status(args.command, args.cwd)
    except (OSError, TimeoutError, ValueError, json.JSONDecodeError):
        status = "unknown"
    print(status)
    return 0 if status == "ready" else 1


if __name__ == "__main__":
    sys.exit(main())

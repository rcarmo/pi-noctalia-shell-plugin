#!/usr/bin/env python3
"""Bridge Noctalia's Pi Assistant panel to `pi --mode rpc`.

This script has three roles:
- `daemon`: spawn a long-lived Pi RPC subprocess and expose a tiny Unix socket API
- `command`: send one command to the daemon and print one JSON response
- `subscribe`: stay connected and print daemon events as JSON lines
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from typing import Any


PANEL_SYSTEM_PROMPT = (
    "You are replying inside a compact QML assistant pane. "
    "The pane renders Markdown and HTML, including inline images via data: URIs. "
    "For visuals, prefer an <img src=\"data:image/svg+xml;base64,...\"> tag or a Markdown image using the same data URI. "
    "Do not emit raw inline <svg> unless explicitly asked; wrap SVG as a data URI image instead. "
    "Keep responses pane-friendly and avoid unnecessarily large blocks of markup."
)


def now() -> float:
    return time.time()


def json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False)


def send_json_line(fileobj, payload: dict) -> None:
    fileobj.write((json_dumps(payload) + "\n").encode("utf-8"))
    fileobj.flush()


def send_json_socket(sock: socket.socket, payload: dict) -> None:
    sock.sendall((json_dumps(payload) + "\n").encode("utf-8"))


class PiBridgeDaemon:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.socket_path = Path(args.socket)
        self.lock_path = self.socket_path.with_suffix(self.socket_path.suffix + ".lock")
        self.server: socket.socket | None = None
        self.pi_proc: subprocess.Popen | None = None
        self.lock_fd = None
        self.running = True
        self.subscribers: set[socket.socket] = set()
        self.pending: dict[str, socket.socket] = {}
        self.state_lock = threading.Lock()
        self.last_error = ""
        self.backend_started_at = now()
        self.current_response = ""
        self.is_generating = False
        self.last_message_at = 0.0
        self.current_model = args.model or ""
        self.current_thinking = args.thinking or "medium"
        self.current_tools_mode = args.tools_mode
        self.start_cwd = ""

    def acquire_lock(self) -> bool:
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        self.lock_fd = open(self.lock_path, "a+", encoding="utf-8")
        try:
            fcntl.flock(self.lock_fd.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.lock_fd.seek(0)
            self.lock_fd.truncate(0)
            self.lock_fd.write(str(os.getpid()))
            self.lock_fd.flush()
            return True
        except OSError:
            return False

    def build_pi_command(self) -> list[str]:
        command = [self.args.pi_command, "--mode", "rpc"]
        if not self.args.persistent_session:
            command.append("--no-session")
        if self.args.model:
            command.extend(["--model", self.args.model])
        if self.args.thinking:
            command.extend(["--thinking", self.args.thinking])
        if self.args.tools_mode == "none":
            command.append("--no-tools")
        elif self.args.tools_mode == "readonly":
            command.extend(["--tools", "read,grep,find,ls"])
        elif self.args.tools_mode == "full":
            command.extend(["--tools", "read,bash,edit,write,grep,find,ls"])
        else:
            command.append("--no-tools")
        command.extend(["--append-system-prompt", PANEL_SYSTEM_PROMPT])
        command.extend(["--name", self.args.session_name])
        return command

    def start_pi(self) -> None:
        cmd = self.build_pi_command()
        start_cwd = Path.home() / "Build"
        chosen_cwd = start_cwd if start_cwd.is_dir() else Path.home()
        self.start_cwd = str(chosen_cwd)
        self.pi_proc = subprocess.Popen(
            cmd,
            cwd=self.start_cwd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        threading.Thread(target=self._read_pi_stdout, name="pi-rpc-stdout", daemon=True).start()
        threading.Thread(target=self._read_pi_stderr, name="pi-rpc-stderr", daemon=True).start()
        self.broadcast(
            {
                "type": "ready",
                "state": self.snapshot_state(),
                "detail": "Pi RPC backend started.",
            }
        )

    def snapshot_state(self) -> dict:
        return {
            "backendReady": bool(self.pi_proc and self.pi_proc.poll() is None),
            "isGenerating": self.is_generating,
            "model": self.current_model,
            "thinkingLevel": self.current_thinking,
            "toolsMode": self.current_tools_mode,
            "cwd": self.start_cwd,
            "lastError": self.last_error,
            "startedAt": self.backend_started_at,
            "lastMessageAt": self.last_message_at,
        }

    def stop_pi(self) -> None:
        proc = self.pi_proc
        self.pi_proc = None
        if not proc:
            return
        if proc.stdin:
            try:
                proc.stdin.close()
            except OSError:
                pass
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                try:
                    proc.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass

    def cleanup(self) -> None:
        self.running = False
        self.stop_pi()
        for subscriber in list(self.subscribers):
            try:
                subscriber.close()
            except OSError:
                pass
        self.subscribers.clear()
        if self.server is not None:
            try:
                self.server.close()
            except OSError:
                pass
        try:
            if self.socket_path.exists():
                self.socket_path.unlink()
        except OSError:
            pass
        if self.lock_fd is not None:
            try:
                fcntl.flock(self.lock_fd.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
            self.lock_fd.close()

    def serve(self) -> int:
        if not self.acquire_lock():
            print(json_dumps({"ok": False, "error": "daemon-already-running"}))
            return 0

        try:
            if self.socket_path.exists():
                self.socket_path.unlink()
        except OSError:
            pass
        self.socket_path.parent.mkdir(parents=True, exist_ok=True)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(self.socket_path))
        self.server.listen(16)
        os.chmod(self.socket_path, 0o600)

        signal.signal(signal.SIGTERM, self._handle_signal)
        signal.signal(signal.SIGINT, self._handle_signal)

        self.start_pi()

        while self.running:
            try:
                conn, _ = self.server.accept()
            except OSError:
                if self.running:
                    continue
                break
            threading.Thread(target=self._handle_client, args=(conn,), daemon=True).start()

        self.cleanup()
        return 0

    def _handle_signal(self, *_args) -> None:
        self.running = False
        if self.server is not None:
            try:
                self.server.close()
            except OSError:
                pass

    def _handle_client(self, conn: socket.socket) -> None:
        try:
            fileobj = conn.makefile("rwb")
            raw = fileobj.readline()
            if not raw:
                conn.close()
                return
            request = json.loads(raw.decode("utf-8"))
            command = request.get("command")
            if command == "subscribe":
                self.subscribers.add(conn)
                send_json_socket(conn, {"type": "ready", "state": self.snapshot_state()})
                while self.running:
                    time.sleep(1)
                    if conn.fileno() < 0:
                        break
                self.subscribers.discard(conn)
                try:
                    conn.close()
                except OSError:
                    pass
                return
            if command == "shutdown":
                send_json_socket(conn, {"ok": True})
                conn.close()
                self.running = False
                if self.server is not None:
                    try:
                        self.server.close()
                    except OSError:
                        pass
                return
            if command == "ping":
                send_json_socket(conn, {"ok": True, "state": self.snapshot_state()})
                conn.close()
                return

            req_id = request.get("id") or str(uuid.uuid4())
            rpc_payload = self._translate_request(request, req_id)
            if not rpc_payload:
                send_json_socket(conn, {"ok": False, "error": "unsupported-command"})
                conn.close()
                return
            self.pending[req_id] = conn
            self._send_to_pi(rpc_payload)
        except Exception as exc:  # pragma: no cover - defensive
            try:
                send_json_socket(conn, {"ok": False, "error": str(exc)})
            except Exception:
                pass
            try:
                conn.close()
            except OSError:
                pass

    def _translate_request(self, request: dict, req_id: str) -> dict | None:
        command = request.get("command")
        if command == "send":
            payload = {"id": req_id, "type": "prompt", "message": request.get("message", "")}
            streaming_behavior = request.get("streamingBehavior")
            if streaming_behavior:
                payload["streamingBehavior"] = streaming_behavior
            return payload
        if command == "steer":
            return {"id": req_id, "type": "steer", "message": request.get("message", "")}
        if command == "follow_up":
            return {"id": req_id, "type": "follow_up", "message": request.get("message", "")}
        if command == "abort":
            return {"id": req_id, "type": "abort"}
        if command == "reset_session":
            return {"id": req_id, "type": "new_session"}
        if command == "compact":
            return {"id": req_id, "type": "compact"}
        if command == "set_model":
            provider = request.get("provider", "")
            model_id = request.get("modelId", "")
            if not provider or not model_id:
                return None
            return {"id": req_id, "type": "set_model", "provider": provider, "modelId": model_id}
        if command == "set_thinking_level":
            return {"id": req_id, "type": "set_thinking_level", "level": request.get("level", "medium")}
        if command == "get_available_models":
            return {"id": req_id, "type": "get_available_models"}
        if command == "get_state":
            return {"id": req_id, "type": "get_state"}
        if command == "get_session_stats":
            return {"id": req_id, "type": "get_session_stats"}
        if command == "get_messages":
            return {"id": req_id, "type": "get_messages"}
        if command == "set_session_name":
            return {"id": req_id, "type": "set_session_name", "name": request.get("name", "")}
        if command == "get_commands":
            return {"id": req_id, "type": "get_commands"}
        return None

    def _send_to_pi(self, payload: dict) -> None:
        proc = self.pi_proc
        if not proc or proc.poll() is not None or not proc.stdin:
            request_id = payload.get("id")
            if request_id and request_id in self.pending:
                conn = self.pending.pop(request_id)
                try:
                    send_json_socket(conn, {"ok": False, "error": "pi-backend-not-running"})
                finally:
                    try:
                        conn.close()
                    except OSError:
                        pass
            self.broadcast({"type": "error", "message": "Pi backend is not running."})
            return
        proc.stdin.write(json_dumps(payload) + "\n")
        proc.stdin.flush()

    def _reply_pending(self, request_id: str, payload: dict) -> None:
        conn = self.pending.pop(request_id, None)
        if conn is None:
            return
        try:
            send_json_socket(conn, payload)
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def broadcast(self, payload: dict) -> None:
        dead: list[socket.socket] = []
        for subscriber in list(self.subscribers):
            try:
                send_json_socket(subscriber, payload)
            except OSError:
                dead.append(subscriber)
        for subscriber in dead:
            self.subscribers.discard(subscriber)
            try:
                subscriber.close()
            except OSError:
                pass

    def _read_pi_stdout(self) -> None:
        proc = self.pi_proc
        if not proc or not proc.stdout:
            return
        try:
            for raw in proc.stdout:
                line = raw.strip()
                if not line:
                    continue
                try:
                    payload = json.loads(line)
                except json.JSONDecodeError:
                    self.last_error = f"Invalid Pi RPC output: {line[:200]}"
                    self.broadcast({"type": "error", "message": self.last_error})
                    continue
                self._handle_pi_payload(payload)
        finally:
            code = proc.poll()
            if self.running:
                self.last_error = f"Pi backend exited with code {code}."
                for request_id in list(self.pending):
                    self._reply_pending(request_id, {"ok": False, "error": self.last_error})
                self.broadcast({"type": "error", "message": self.last_error})
                self.broadcast({"type": "backend_exited", "exitCode": code})
                self.is_generating = False

    def _read_pi_stderr(self) -> None:
        proc = self.pi_proc
        if not proc or not proc.stderr:
            return
        for raw in proc.stderr:
            line = raw.strip()
            if not line:
                continue
            self.last_error = line
            self.broadcast({"type": "backend_log", "stream": "stderr", "message": line})

    def _handle_pi_payload(self, payload: dict) -> None:
        payload_type = payload.get("type")
        if payload_type == "response":
            request_id = payload.get("id")
            if payload.get("command") == "set_model" and payload.get("success") and isinstance(payload.get("data"), dict):
                self.current_model = f"{payload['data'].get('provider', '')}/{payload['data'].get('id', '')}".strip("/")
            if payload.get("command") == "set_thinking_level" and payload.get("success"):
                self.current_thinking = payload.get("data", {}).get("level", self.current_thinking) if isinstance(payload.get("data"), dict) else self.current_thinking
            if payload.get("command") == "get_state" and payload.get("success") and isinstance(payload.get("data"), dict):
                state = payload.get("data") or {}
                model = state.get("model") or {}
                if isinstance(model, dict):
                    provider = model.get("provider", "")
                    model_id = model.get("id", "")
                    self.current_model = f"{provider}/{model_id}".strip("/")
                self.current_thinking = state.get("thinkingLevel", self.current_thinking)
            reply = {"ok": bool(payload.get("success")), "response": payload}
            if not payload.get("success"):
                reply["error"] = payload.get("error") or payload.get("message") or "Command failed."
            if request_id:
                self._reply_pending(request_id, reply)
            return

        if payload_type == "agent_start":
            self.is_generating = True
            self.current_response = ""
            self.last_message_at = now()
            self.broadcast({"type": "agent_start", "state": self.snapshot_state()})
            return

        if payload_type == "message_update":
            event = payload.get("assistantMessageEvent") or {}
            if event.get("type") == "text_delta":
                delta = event.get("delta") or ""
                self.current_response += delta
                self.last_message_at = now()
                self.broadcast({"type": "text_delta", "delta": delta})
            elif event.get("type") == "thinking_delta":
                self.broadcast({"type": "thinking_delta", "delta": event.get("delta") or ""})
            return

        if payload_type == "tool_call":
            self.broadcast({
                "type": "tool_call",
                "toolName": payload.get("toolName") or "",
                "toolCallId": payload.get("toolCallId") or "",
                "input": payload.get("input"),
            })
            return

        if payload_type == "tool_result":
            self.broadcast({
                "type": "tool_result",
                "toolName": payload.get("toolName") or "",
                "toolCallId": payload.get("toolCallId") or "",
                "input": payload.get("input"),
                "content": payload.get("content"),
                "details": payload.get("details"),
                "isError": bool(payload.get("isError")),
            })
            return

        if payload_type == "tool_execution_start":
            self.broadcast({
                "type": "tool_execution_start",
                "toolName": payload.get("toolName") or "",
                "toolCallId": payload.get("toolCallId") or "",
                "args": payload.get("args"),
            })
            return

        if payload_type == "tool_execution_update":
            self.broadcast({
                "type": "tool_execution_update",
                "toolName": payload.get("toolName") or "",
                "toolCallId": payload.get("toolCallId") or "",
                "args": payload.get("args"),
                "partialResult": payload.get("partialResult"),
            })
            return

        if payload_type == "tool_execution_end":
            self.broadcast({
                "type": "tool_execution_end",
                "toolName": payload.get("toolName") or "",
                "toolCallId": payload.get("toolCallId") or "",
                "result": payload.get("result"),
                "isError": bool(payload.get("isError")),
            })
            return

        if payload_type == "message_end":
            return

        if payload_type == "agent_end":
            self.is_generating = False
            self.last_message_at = now()
            self.broadcast({"type": "done", "state": self.snapshot_state()})
            return

        if payload_type == "queue_update":
            self.broadcast({"type": "queue_update", "steering": payload.get("steering", []), "followUp": payload.get("followUp", [])})
            return

        if payload_type == "auto_retry_start":
            self.broadcast({"type": "status", "message": payload.get("errorMessage") or "Retrying request..."})
            return

        if payload_type == "auto_retry_end":
            if not payload.get("success"):
                self.broadcast({"type": "error", "message": payload.get("finalError") or "Request failed."})
            return

        if payload_type == "session":
            return

    

def connect_with_retry(socket_path: str, wait_seconds: float) -> socket.socket:
    deadline = now() + max(wait_seconds, 0)
    last_error = None
    while True:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(socket_path)
            return sock
        except OSError as exc:
            last_error = exc
            sock.close()
            if now() >= deadline:
                raise exc
            time.sleep(0.1)


def run_command(args: argparse.Namespace) -> int:
    try:
        sock = connect_with_retry(args.socket, args.wait)
    except OSError as exc:
        print(json_dumps({"ok": False, "error": f"cannot-connect: {exc}"}))
        return 1
    with sock:
        payload = json.loads(args.json)
        send_json_socket(sock, payload)
        response = sock.makefile("rb").readline()
        if not response:
            print(json_dumps({"ok": False, "error": "no-response"}))
            return 1
        sys.stdout.write(response.decode("utf-8"))
        return 0


def run_subscribe(args: argparse.Namespace) -> int:
    try:
        sock = connect_with_retry(args.socket, args.wait)
    except OSError as exc:
        print(json_dumps({"type": "error", "message": f"cannot-connect: {exc}"}))
        return 1
    with sock:
        send_json_socket(sock, {"command": "subscribe"})
        reader = sock.makefile("rb")
        while True:
            line = reader.readline()
            if not line:
                break
            sys.stdout.write(line.decode("utf-8"))
            sys.stdout.flush()
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Pi RPC bridge for Noctalia plugin integration.")
    sub = parser.add_subparsers(dest="mode", required=True)

    daemon = sub.add_parser("daemon")
    daemon.add_argument("--socket", required=True)
    daemon.add_argument("--pi-command", default="pi")
    daemon.add_argument("--model", default="")
    daemon.add_argument("--thinking", default="medium")
    daemon.add_argument("--tools-mode", default="none", choices=("none", "readonly", "full"))
    daemon.add_argument("--persistent-session", action="store_true")
    daemon.add_argument("--session-name", default="Noctalia Pi Assistant")

    command = sub.add_parser("command")
    command.add_argument("--socket", required=True)
    command.add_argument("--json", required=True)
    command.add_argument("--wait", type=float, default=5.0)

    subscribe = sub.add_parser("subscribe")
    subscribe.add_argument("--socket", required=True)
    subscribe.add_argument("--wait", type=float, default=10.0)

    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.mode == "daemon":
        return PiBridgeDaemon(args).serve()
    if args.mode == "command":
        return run_command(args)
    if args.mode == "subscribe":
        return run_subscribe(args)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

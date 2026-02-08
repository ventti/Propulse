#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
import traceback


ROOT = os.environ.get("PROPULSE_ROOT", os.getcwd())


def _resolve_path(path):
    if path is None:
        return None
    if os.path.isabs(path):
        return path
    return os.path.join(ROOT, path)


def _send(msg):
    sys.stdout.write(json.dumps(msg))
    sys.stdout.write("\n")
    sys.stdout.flush()


def _error(req_id, code, message, data=None):
    err = {"code": code, "message": message}
    if data is not None:
        err["data"] = data
    _send({"jsonrpc": "2.0", "id": req_id, "error": err})


def _result(req_id, result):
    _send({"jsonrpc": "2.0", "id": req_id, "result": result})


def _tool_list():
    return {
        "tools": [
            {
                "name": "run_ui_script",
                "description": "Run Propulse with an inline UI automation script.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "script": {"type": "string"},
                        "executable_path": {"type": "string", "default": "./Propulse"},
                        "exit_on_complete": {"type": "boolean", "default": True},
                        "timeout_seconds": {"type": "number", "default": 60},
                        "module_file": {"type": "string"},
                        "extra_args": {"type": "array", "items": {"type": "string"}},
                        "working_directory": {"type": "string"}
                    },
                    "required": ["script"]
                }
            },
            {
                "name": "run_ui_script_file",
                "description": "Run Propulse with a UI automation script file.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "script_path": {"type": "string"},
                        "executable_path": {"type": "string", "default": "./Propulse"},
                        "exit_on_complete": {"type": "boolean", "default": True},
                        "timeout_seconds": {"type": "number", "default": 60},
                        "module_file": {"type": "string"},
                        "extra_args": {"type": "array", "items": {"type": "string"}},
                        "working_directory": {"type": "string"}
                    },
                    "required": ["script_path"]
                }
            }
        ]
    }


def _run_propulse(script_path, executable_path, exit_on_complete, timeout_seconds,
                  module_file, extra_args, working_directory):
    exe = _resolve_path(executable_path or "./Propulse")
    if not os.path.exists(exe):
        raise FileNotFoundError(f"executable not found: {exe}")

    cmd = [exe, "--automation", script_path]
    if exit_on_complete:
        cmd.append("--automation-exit")
    if extra_args:
        cmd.extend(extra_args)
    if module_file:
        cmd.append(module_file)

    cwd = _resolve_path(working_directory) if working_directory else None
    result = subprocess.run(
        cmd,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout_seconds
    )
    return {
        "command": cmd,
        "exit_code": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr
    }


def _handle_tools_call(req_id, params):
    name = params.get("name")
    args = params.get("arguments") or {}

    if name == "run_ui_script":
        script = args.get("script", "")
        if not script:
            _error(req_id, -32602, "missing script")
            return
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".propulse-ui.txt") as f:
            f.write(script)
            script_path = f.name
        try:
            result = _run_propulse(
                script_path=script_path,
                executable_path=args.get("executable_path"),
                exit_on_complete=bool(args.get("exit_on_complete", True)),
                timeout_seconds=float(args.get("timeout_seconds", 60)),
                module_file=args.get("module_file"),
                extra_args=args.get("extra_args"),
                working_directory=args.get("working_directory")
            )
        finally:
            try:
                os.remove(script_path)
            except OSError:
                pass
        _result(req_id, {"content": [{"type": "text", "text": json.dumps(result, indent=2)}]})
        return

    if name == "run_ui_script_file":
        script_path = args.get("script_path")
        if not script_path:
            _error(req_id, -32602, "missing script_path")
            return
        script_path = _resolve_path(script_path)
        if not os.path.exists(script_path):
            _error(req_id, -32602, f"script not found: {script_path}")
            return
        result = _run_propulse(
            script_path=script_path,
            executable_path=args.get("executable_path"),
            exit_on_complete=bool(args.get("exit_on_complete", True)),
            timeout_seconds=float(args.get("timeout_seconds", 60)),
            module_file=args.get("module_file"),
            extra_args=args.get("extra_args"),
            working_directory=args.get("working_directory")
        )
        _result(req_id, {"content": [{"type": "text", "text": json.dumps(result, indent=2)}]})
        return

    _error(req_id, -32601, f"unknown tool: {name}")


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue

        method = msg.get("method")
        req_id = msg.get("id")

        if method == "initialize":
            _result(req_id, {
                "protocolVersion": "2024-11-05",
                "serverInfo": {"name": "propulse-ui-mcp", "version": "0.1.0"},
                "capabilities": {"tools": {}}
            })
        elif method == "tools/list":
            _result(req_id, _tool_list())
        elif method == "tools/call":
            _handle_tools_call(req_id, msg.get("params") or {})
        elif method == "shutdown":
            _result(req_id, {})
        elif method == "exit":
            break
        else:
            if req_id is not None:
                _error(req_id, -32601, f"unknown method: {method}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()

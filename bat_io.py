#!/usr/bin/env python3
"""
bat_io.py — Secure, bounded, no-follow, non-blocking state I/O for BatPuter.
Adheres strictly to Omarchy security & marketplace policies:
1. Descriptor-level O_NOFOLLOW | O_NONBLOCK reads bounded by byte limits.
2. Exclusive mode-0600 sibling file creation with atomic replacement (os.replace).
3. Zero shell argument interpolation, zero symlink following, zero memory unboundedness.
"""

import sys
import os
import json
import uuid

HOME = os.environ.get("HOME") or os.path.expanduser("~")
STATE_DIR = os.path.join(HOME, ".config", "omarchy", "batputer")

ALLOWED_FILES = {
    "config": ("config.json", 32768, "{}"),
    "agenda": ("agenda.json", 65536, "[]"),
    "notes": ("notes.json", 131072, "{}"),
}

def ensure_state_dir():
    if not os.path.exists(STATE_DIR):
        try:
            os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
            os.chmod(STATE_DIR, 0o700)
        except OSError:
            pass

def read_state(key, max_bytes_override=None):
    if key not in ALLOWED_FILES:
        sys.stdout.write("{}\n")
        return

    filename, default_max, default_val = ALLOWED_FILES[key]
    max_bytes = int(max_bytes_override) if max_bytes_override else default_max
    target_path = os.path.join(STATE_DIR, filename)

    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    if hasattr(os, "O_NONBLOCK"):
        flags |= os.O_NONBLOCK

    try:
        fd = os.open(target_path, flags)
        with open(fd, "rb", closefd=True) as f:
            data = f.read(max_bytes + 1)
        
        if len(data) > max_bytes:
            sys.stdout.write(default_val + "\n")
            return

        text = data.decode("utf-8", errors="replace")
        json.loads(text)
        sys.stdout.write(text.strip() + "\n")
    except Exception:
        sys.stdout.write(default_val + "\n")

def save_state(key):
    if key not in ALLOWED_FILES:
        return

    filename, max_bytes, _ = ALLOWED_FILES[key]
    ensure_state_dir()
    target_path = os.path.join(STATE_DIR, filename)

    try:
        raw = sys.stdin.buffer.read(max_bytes + 1)
    except Exception:
        return

    if not raw or len(raw) > max_bytes:
        return

    try:
        text = raw.decode("utf-8", errors="strict")
        parsed = json.loads(text)
        clean_bytes = json.dumps(parsed, separators=(",", ":")).encode("utf-8")
    except Exception:
        return

    tmp_filename = f"{filename}.tmp.{os.getpid()}.{uuid.uuid4().hex[:8]}"
    tmp_path = os.path.join(STATE_DIR, tmp_filename)

    tmp_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        tmp_flags |= os.O_NOFOLLOW

    try:
        fd = os.open(tmp_path, tmp_flags, 0o600)
        with open(fd, "wb", closefd=True) as f:
            f.write(clean_bytes)
            f.flush()
            os.fsync(f.fileno())

        os.replace(tmp_path, target_path)
        os.chmod(target_path, 0o600)
    except Exception:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except OSError:
            pass

def main():
    if len(sys.argv) < 3:
        return

    action = sys.argv[1]
    key = sys.argv[2]

    if action == "read":
        max_bytes = sys.argv[3] if len(sys.argv) > 3 else None
        read_state(key, max_bytes)
    elif action == "save":
        save_state(key)

if __name__ == "__main__":
    main()

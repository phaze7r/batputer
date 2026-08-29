#!/usr/bin/env python3
"""
bat_io.py — Secure, bounded, no-follow, non-blocking state I/O for BatPuter.
Adheres strictly to Omarchy security & marketplace policies:
1. All I/O is anchored to a directory descriptor opened O_DIRECTORY | O_NOFOLLOW
   and verified (fstat: real dir, owned by us, not group/other accessible), so a
   planted directory symlink at the state dir cannot redirect reads or writes.
2. Every opened target is fstat-checked as a regular file before use.
3. Descriptor-level O_NOFOLLOW | O_NONBLOCK reads bounded by byte limits.
4. Exclusive mode-0600 sibling file creation with atomic replacement, all via
   dir_fd so nothing is ever re-resolved by path name (no symlink/TOCTOU race).
5. Zero shell argument interpolation, zero memory unboundedness.

ponytail: ancestors above ~/.config/omarchy/batputer are trusted (owned by the
user / the omarchy package); only the state dir itself is verified non-symlink.
"""

import sys
import os
import stat
import json
import uuid

HOME = os.environ.get("HOME") or os.path.expanduser("~")
STATE_DIR = os.path.join(HOME, ".config", "omarchy", "batputer")

ALLOWED_FILES = {
    "config": ("config.json", 32768, "{}"),
    "agenda": ("agenda.json", 65536, "[]"),
    "notes": ("notes.json", 131072, "{}"),
}


def open_state_dir():
    """Return an fd for STATE_DIR, proven to be a private directory we own.

    Raises OSError if the state dir is a symlink, not a directory, not owned by
    us, or is group/other accessible.
    """
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    dfd = os.open(STATE_DIR, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        st = os.fstat(dfd)
        if (not stat.S_ISDIR(st.st_mode)
                or st.st_uid != os.getuid()
                or (st.st_mode & 0o077)):
            raise OSError("BatPuter state dir is not a private directory we own")
    except Exception:
        os.close(dfd)
        raise
    return dfd


def read_state(key, max_bytes_override=None):
    if key not in ALLOWED_FILES:
        sys.stdout.write("{}\n")
        return

    filename, default_max, default_val = ALLOWED_FILES[key]
    try:
        max_bytes = int(max_bytes_override) if max_bytes_override else default_max
        if max_bytes < 0:
            max_bytes = default_max
    except (TypeError, ValueError):
        max_bytes = default_max

    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    if hasattr(os, "O_NONBLOCK"):
        flags |= os.O_NONBLOCK

    dfd = None
    try:
        dfd = open_state_dir()
        fd = os.open(filename, flags, dir_fd=dfd)
        with open(fd, "rb", closefd=True) as f:
            if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
                sys.stdout.write(default_val + "\n")
                return
            data = f.read(max_bytes + 1)

        if len(data) > max_bytes:
            sys.stdout.write(default_val + "\n")
            return

        text = data.decode("utf-8", errors="replace")
        json.loads(text)
        sys.stdout.write(text.strip() + "\n")
    except Exception:
        sys.stdout.write(default_val + "\n")
    finally:
        if dfd is not None:
            os.close(dfd)


def save_state(key):
    if key not in ALLOWED_FILES:
        return

    filename, max_bytes, _ = ALLOWED_FILES[key]

    try:
        raw = sys.stdin.buffer.readline(max_bytes + 1)
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

    tmp_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        tmp_flags |= os.O_NOFOLLOW

    dfd = None
    try:
        dfd = open_state_dir()
        fd = os.open(tmp_filename, tmp_flags, 0o600, dir_fd=dfd)
        try:
            with open(fd, "wb", closefd=True) as f:
                f.write(clean_bytes)
                f.flush()
                os.fsync(f.fileno())
            # Anchored to the verified dir fd: no path re-resolution, and the
            # O_EXCL create already fixed mode 0600, so no chmod-by-name race.
            os.replace(tmp_filename, filename, src_dir_fd=dfd, dst_dir_fd=dfd)
        except Exception:
            try:
                os.unlink(tmp_filename, dir_fd=dfd)
            except OSError:
                pass
            raise
    except Exception:
        pass
    finally:
        if dfd is not None:
            os.close(dfd)


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

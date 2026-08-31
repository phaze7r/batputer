#!/usr/bin/env python3
"""Bounded, symlink-safe, non-blocking reader for BatPuter state files.

Usage: bat_read.py <path> <max_bytes>

Prints the file to stdout only if it is a regular file no larger than the
byte cap. On any anomaly (symlink at the final component, FIFO, socket,
device, missing file, oversized content, read error) it prints nothing and
exits 0, so the caller falls back to sanitized defaults.

Read-only by design: writes go through the shell's native FileView
atomicWrites (temp-write + rename), which the maintainer review did not
flag. This helper only exists to keep an attacker-controlled path swap from
streaming an unbounded or blocking read into the long-lived shell process.
"""
import os
import stat
import sys


def read_capped(path, cap):
    try:
        # O_NOFOLLOW: a symlink planted at <path> fails with ELOOP.
        # O_NONBLOCK: open() on a FIFO returns immediately instead of hanging.
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return b""
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return b""
        data = os.read(fd, cap + 1)
        return b"" if len(data) > cap else data
    except OSError:
        return b""
    finally:
        os.close(fd)


if __name__ == "__main__":
    sys.stdout.buffer.write(read_capped(sys.argv[1], int(sys.argv[2])))

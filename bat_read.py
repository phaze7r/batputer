#!/usr/bin/env python3
"""Usage: bat_read.py <path> <max_bytes>

Prints the file iff it is a regular file within the cap; prints nothing
(exit 0) on any anomaly — symlink, FIFO, missing, oversized, wrong type.
"""
import os
import stat
import sys


def read_capped(path, cap):
    try:
        # O_NOFOLLOW: a planted symlink fails. O_NONBLOCK: a FIFO won't hang.
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        return b""
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return b""
        d = os.read(fd, cap + 1)
        return d if len(d) <= cap else b""
    finally:
        os.close(fd)


if __name__ == "__main__":
    sys.stdout.buffer.write(read_capped(sys.argv[1], int(sys.argv[2])))

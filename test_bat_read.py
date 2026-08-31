"""Self-check for bat_read.read_capped. Run: python3 test_bat_read.py"""
import os
import tempfile

from bat_read import read_capped


def test():
    d = tempfile.mkdtemp()
    good = os.path.join(d, "state.json")
    with open(good, "wb") as f:
        f.write(b'{"a":1}')

    assert read_capped(good, 1024) == b'{"a":1}'          # regular file, under cap
    assert read_capped(good, 3) == b""                     # over cap -> rejected
    assert read_capped(os.path.join(d, "missing"), 1024) == b""

    link = os.path.join(d, "link.json")
    os.symlink(good, link)
    assert read_capped(link, 1024) == b""                  # symlink -> rejected

    fifo = os.path.join(d, "fifo.json")
    os.mkfifo(fifo)
    assert read_capped(fifo, 1024) == b""                  # FIFO -> no hang, non-regular rejected

    print("ok")


if __name__ == "__main__":
    test()

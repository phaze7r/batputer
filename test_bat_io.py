import os, subprocess, sys, tempfile, json, shutil

SCRIPT = os.path.expanduser("~/.config/omarchy/plugins/batputer/bat_io.py")

def run(env_home, args, stdin=None):
    e = dict(os.environ); e["HOME"] = env_home
    return subprocess.run([sys.executable, SCRIPT, *args], input=stdin,
                          capture_output=True, text=True, env=e)

base = tempfile.mkdtemp()
home = os.path.join(base, "home"); os.makedirs(home)

# 1. save then read roundtrip
r = run(home, ["save", "notes"], stdin='{"tabs":[{"title":"a","content":"hi"}]}\n')
assert r.returncode == 0, r
out = run(home, ["read", "notes", "131072"]).stdout.strip()
assert json.loads(out) == {"tabs":[{"title":"a","content":"hi"}]}, out
sd = os.path.join(home, ".config/omarchy/batputer")
assert oct(os.stat(os.path.join(sd,"notes.json")).st_mode & 0o777) == "0o600"
assert oct(os.stat(sd).st_mode & 0o777) == "0o700"
print("1 roundtrip + perms OK")

# 2. oversized payload rejected (no file written / unchanged)
r = run(home, ["save", "config"], stdin='{"x":"' + "A"*40000 + '"}\n')
out = run(home, ["read", "config"]).stdout.strip()
assert out == "{}", repr(out)   # nothing was saved
print("2 oversized rejected OK")

# 3. planted directory symlink at state dir -> read falls back, save refuses
home2 = os.path.join(base, "home2"); os.makedirs(os.path.join(home2, ".config/omarchy"))
evil = os.path.join(base, "evil"); os.makedirs(evil)
os.symlink(evil, os.path.join(home2, ".config/omarchy/batputer"))
out = run(home2, ["read", "notes"]).stdout.strip()
assert out == "{}", repr(out)
r = run(home2, ["save", "notes"], stdin='{"tabs":[]}\n')
assert not os.path.exists(os.path.join(evil, "notes.json")), "write leaked through symlink!"
print("3 dir-symlink blocked OK")

# 4. non-regular target (fifo) -> read falls back
home3 = os.path.join(base, "home3")
sd3 = os.path.join(home3, ".config/omarchy/batputer"); os.makedirs(sd3, 0o700)
os.mkfifo(os.path.join(sd3, "config.json"))
out = run(home3, ["read", "config"]).stdout.strip()
assert out == "{}", repr(out)
print("4 fifo target blocked OK")

# 5. bad key
assert run(home, ["read", "bogus"]).stdout.strip() == "{}"
print("5 bad key OK")

shutil.rmtree(base)
print("ALL PASS")

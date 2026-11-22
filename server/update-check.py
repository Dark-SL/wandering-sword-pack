#!/usr/bin/env python3
"""Runs every 3 minutes on the server. If a new Wandering Sword version was published, restart the server so it
installs it: immediately when nobody is online, otherwise after a 60-second warning in chat.
Also makes the owner an operator once the server is up (pending-op.txt from setup)."""
import hashlib
import os
import re
import socket
import struct
import subprocess
import sys
import time
import urllib.request

DIR = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(DIR, ".last-pack-hash")


def props():
    out = {}
    with open(os.path.join(DIR, "server.properties"), encoding="utf-8") as f:
        for line in f:
            if "=" in line and not line.startswith("#"):
                k, v = line.rstrip("\n").split("=", 1)
                out[k] = v
    return out


def rcon(cmd):
    p = props()
    s = socket.create_connection(("127.0.0.1", int(p.get("rcon.port", 25575))), timeout=5)

    def send(kind, body, rid):
        data = struct.pack("<ii", rid, kind) + body.encode("utf-8") + b"\x00\x00"
        s.sendall(struct.pack("<i", len(data)) + data)

    def recv():
        length = struct.unpack("<i", s.recv(4))[0]
        data = b""
        while len(data) < length:
            data += s.recv(length - len(data))
        return struct.unpack("<ii", data[:8])[0], data[8:-2].decode("utf-8", "replace")

    send(3, p.get("rcon.password", ""), 1)
    if recv()[0] == -1:
        raise RuntimeError("rcon login failed")
    send(2, cmd, 2)
    reply = recv()[1]
    s.close()
    return reply


def online_players():
    m = re.search(r"There are (\d+)", rcon("list"))
    return int(m.group(1)) if m else 0


def restart():
    subprocess.run(["sudo", "/usr/bin/systemctl", "restart", "wandering-sword"], check=False)


def main():
    # one-time: make the owner an operator once the server answers
    op_file = os.path.join(DIR, "pending-op.txt")
    if os.path.exists(op_file):
        try:
            rcon("op " + open(op_file, encoding="utf-8").read().strip())
            os.remove(op_file)
        except OSError:
            pass

    with urllib.request.urlopen(sys.argv[1], timeout=20) as r:
        remote = hashlib.sha256(r.read()).hexdigest()
    last = open(STATE).read().strip() if os.path.exists(STATE) else None
    if last is None:
        open(STATE, "w").write(remote)
        return
    if remote == last:
        return
    try:
        players = online_players()
    except OSError:
        players = 0  # server is down or still starting: just restart it
    if players > 0:
        try:
            rcon("say §6A new Wandering Sword update is ready. The server restarts in 60 seconds - "
                 "rejoin after, and your launcher will update you.")
            time.sleep(50)
            rcon("say §cRestarting in 10 seconds...")
            time.sleep(10)
        except OSError:
            pass
    open(STATE, "w").write(remote)
    restart()


if __name__ == "__main__":
    main()

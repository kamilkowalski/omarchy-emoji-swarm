#!/usr/bin/env python3
"""kamil.swarm agent — LAN presence + emoji transport over UDP broadcast.

Daemon mode (default): beacons presence every 2s on UDP 47474, listens for
peer beacons and emoji packets, prints one JSON event per line to stdout.

Send mode: `agent.py send <ip> <emoji> <from>` emits one emoji packet, exits.
"""
import json
import os
import socket
import sys
import time
import uuid

PORT = 47474
BEACON_INTERVAL = 2.0


def identity():
    try:
        with open("/etc/machine-id") as f:
            mid = f.read().strip()[:12]
    except OSError:
        mid = "%012x" % uuid.getnode()
    name = os.uname().nodename.split(".")[0] or os.environ.get("USER", "laptop")
    return mid, name


def broadcast_addrs():
    addrs = {"255.255.255.255"}
    try:
        out = os.popen("ip -o -4 addr show scope global 2>/dev/null").read()
        for line in out.splitlines():
            parts = line.split()
            if len(parts) >= 4 and "brd" in parts:
                addrs.add(parts[parts.index("brd") + 1])
    except OSError:
        pass
    # macOS / BSD: ifconfig prints "... inet 192.168.0.5 netmask 0xffffff00 broadcast 192.168.0.255"
    try:
        out = os.popen("ifconfig 2>/dev/null").read()
        for line in out.splitlines():
            parts = line.split()
            if "inet" in parts and "broadcast" in parts:
                addrs.add(parts[parts.index("broadcast") + 1])
    except OSError:
        pass
    addrs.discard("")
    return sorted(addrs)


def emit(obj):
    try:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        sys.exit(0)


def serve():
    mid, name = identity()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except OSError:
        pass
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind(("0.0.0.0", PORT))
    sock.settimeout(1.0)

    emit({"event": "hello", "id": mid, "name": name})

    last_beacon = 0.0
    while True:
        now = time.time()
        if now - last_beacon >= BEACON_INTERVAL:
            last_beacon = now
            hello = json.dumps({"type": "hello", "id": mid, "name": name}).encode()
            for addr in broadcast_addrs():
                try:
                    sock.sendto(hello, (addr, PORT))
                except OSError:
                    pass
        try:
            data, sender = sock.recvfrom(2048)
        except socket.timeout:
            continue
        except OSError:
            continue
        try:
            msg = json.loads(data.decode("utf-8", "replace"))
        except ValueError:
            continue
        if msg.get("type") == "hello":
            emit({"event": "peer", "id": msg.get("id", ""),
                  "name": msg.get("name", "?"), "ip": sender[0]})
        elif msg.get("type") == "emoji":
            emit({"event": "emoji", "emoji": str(msg.get("emoji", ""))[:16],
                  "from": str(msg.get("from", "?"))[:32]})


def send(ip, emoji, from_):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    payload = json.dumps({"type": "emoji", "emoji": emoji, "from": from_}).encode()
    sock.sendto(payload, (ip, PORT))
    sock.close()


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == "send":
        send(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "?")
        return
    serve()


if __name__ == "__main__":
    main()

# omarchy-emoji-swarm

Spot nearby Omarchy laptops and hurl emojis at them. Emojis float up the
screen of every machine in the swarm, sender name attached.

Everything runs over one UDP port (47474) — presence beacons + emoji
datagrams. No pairing, no server, same subnet only.

## Install (Omarchy)

```sh
omarchy plugin add https://github.com/<you>/omarchy-emoji-swarm.git --enable
```

Then add a keybinding in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + E", "Emoji swarm", "omarchy-shell shell toggle kamil.emoji-swarm")
```

And allow the port through the firewall:

```sh
sudo ufw allow 47474/udp
```

Press `SUPER + ALT + E`: pick a laptop (or none to hit the whole swarm), pick
an emoji. Incoming emojis float up the screen. The `🐝 N nearby` pill in the
bottom-right corner reopens the picker.

## Receive on macOS

The agent is plain stdlib Python — it runs on macOS unchanged:

```sh
python3 agent.py            # beacon + receive; prints emojis to stdout
```

Run it in a terminal while the Mac is on the same Wi-Fi. macOS firewall:
allow incoming connections for python when prompted
(System Settings → Network → Firewall).

Send from the Mac (no clone needed):

```sh
python3 agent.py send 192.168.0.255 🎉 macbook   # directed broadcast
python3 agent.py send 192.168.0.147 🚀 macbook   # unicast to one laptop
```

To get the Mac into the Omarchy picker, keep `python3 agent.py` running —
its beacons make it show up as a peer.

## Files

- `manifest.json` — Omarchy shell plugin manifest (kind: overlay, keepLoaded)
- `Swarm.qml` — Quickshell UI: floater layer, picker, HUD
- `agent.py` — stdlib Python daemon: UDP beacons + emoji transport

## Uninstall

```sh
omarchy plugin disable kamil.emoji-swarm
omarchy plugin remove kamil.emoji-swarm
```

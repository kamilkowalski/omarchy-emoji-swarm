# omarchy-emoji-swarm

Spot nearby Omarchy laptops and hurl emojis at them. Emojis float up the
screen of every machine in the swarm, sender name attached.

Everything runs over one UDP port (47474) — presence beacons + emoji
datagrams. No pairing, no server, same subnet only.

## Install on Omarchy (agent-friendly)

Point any agent (or human) at this section. The block is idempotent — safe to
re-run.

```bash
set -e

# 1. Install + enable the shell plugin (non-interactive)
omarchy plugin add https://github.com/kamilkowalski/omarchy-emoji-swarm.git --enable --yes

# 2. Keybinding: SUPER+ALT+E toggles the picker (skip if already present)
grep -q 'kamil.emoji-swarm' ~/.config/hypr/bindings.lua 2>/dev/null || cat >> ~/.config/hypr/bindings.lua <<'EOF'

-- Emoji swarm: send/receive emojis with nearby Omarchy laptops
o.bind("SUPER + ALT + E", "Emoji swarm", "omarchy-shell shell toggle kamil.emoji-swarm")
EOF

# 3. Firewall: allow the swarm port (needed to receive anything)
sudo ufw allow 47474/udp 2>/dev/null || true

# 4. Reload Hyprland config if the binding was just added
hyprctl reload 2>/dev/null || true
```

Verify (all three must pass):

```bash
omarchy plugin list | grep kamil.emoji-swarm                 # enabled, overlay
pgrep -f "plugins/kamil.emoji-swarm/agent.py"                # agent running
omarchy-shell shell summon kamil.emoji-swarm                 # picker opens, no shell errors
omarchy-shell shell hide kamil.emoji-swarm
```

Usage: `SUPER+ALT+E` → pick a laptop (none selected = broadcast) → click an
emoji. Incoming emojis float up the screen. The `🐝 N nearby` pill
(bottom-right) reopens the picker. To hit a laptop from a script on another
Omarchy machine:

```bash
python3 agent.py send omarchy.local 🎉 laptop-name   # unicast via mDNS
```

## macOS

No install, no keybind. Needs python3 (macOS offers to install the Command
Line Tools on first `python3` run) and the same Wi-Fi.

```bash
git clone https://github.com/kamilkowalski/omarchy-emoji-swarm.git
cd omarchy-emoji-swarm

python3 agent.py                                    # receive + appear in the Omarchy picker
python3 agent.py send omarchy.local 🎉 macbook      # 🎉 floats on the Omarchy screen
python3 agent.py send 255.255.255.255 🎉 macbook    # blast the whole subnet
```

- Emoji input in Terminal: <kbd>Ctrl</kbd>+<kbd>Cmd</kbd>+<kbd>Space</kbd>.
- `omarchy.local` is the laptop's mDNS name — replace with its IP if .local
  resolution misbehaves.
- First run: allow incoming connections for python when macOS firewall asks,
  or the Mac can't receive and won't appear as a peer.
- Incoming emojis print to the agent's terminal (no GUI on macOS). Keep
  `python3 agent.py` running to stay visible as a peer.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Picker says 0 nearby | Both machines on same subnet; `ufw status` shows 47474/udp ALLOW; agent running (`pgrep -f agent.py`) |
| Sent, nothing floated | Receiver's firewall; try unicast to the exact IP instead of broadcast |
| `python3: command not found` (mac) | Install Command Line Tools: `xcode-select --install` |
| Picker blank / errors in shell | `journalctl --user _COMM=quickshell | grep -i swarm` |

## How it works

- `manifest.json` — Omarchy shell plugin manifest (kind: overlay, keepLoaded)
- `Swarm.qml` — Quickshell UI: click-through floater layer, picker, HUD pill
- `agent.py` — stdlib-only Python: UDP beacon every 2s on 47474, emoji
  datagrams; events to stdout as JSON lines, `send` subcommand for emits

## Uninstall

```bash
omarchy plugin disable kamil.emoji-swarm
omarchy plugin remove kamil.emoji-swarm
```

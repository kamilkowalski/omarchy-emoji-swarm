import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

// kamil.swarm — LAN emoji swarm. Beacons presence over UDP, shows nearby
// Omarchy machines, and floats received emojis across the screen.
Item {
  id: root

  property string omarchyPath: Quickshell.env("HOME")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string myId: ""
  property string myName: ""
    // id -> { id, name, ip, seen }
  property var peers: ({})
    // sorted copy for the picker list
  property var peersList: []
  property int selectedPeer: -1

  readonly property string agentPath: Qt.resolvedUrl("agent.py").toString().replace(/^file:\/\//, "")
  readonly property int maxFloaters: 24

  function open(payloadJson) {
    root.opened = true
    root.selectedPeer = Math.min(root.selectedPeer, root.peersList.length - 1)
    Qt.callLater(function() { contentRoot.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  // ------------------------------------------------------------- agent link

  function onAgentLine(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (!msg || !msg.event) return
    if (msg.event === "hello") {
      root.myId = String(msg.id || "")
      root.myName = String(msg.name || "")
    } else if (msg.event === "peer") {
      if (String(msg.id) === root.myId) return
      var id = String(msg.id)
      var prev = root.peers[id] || {}
      root.peers[id] = { id: id, name: String(msg.name || "?"), ip: String(msg.ip || ""), seen: Date.now() }
      if (prev.name !== root.peers[id].name || prev.ip !== root.peers[id].ip) root.rebuildPeers()
    } else if (msg.event === "emoji") {
      root.spawnFloat(String(msg.emoji || "🎉"), String(msg.from || "?"), false)
    }
  }

  function rebuildPeers() {
    var arr = []
    for (var id in root.peers) arr.push(root.peers[id])
    arr.sort(function(a, b) { return a.name < b.name ? -1 : 1 })
    root.peersList = arr
    if (root.selectedPeer >= arr.length) root.selectedPeer = arr.length - 1
  }

  Process {
    id: agentProc
    command: ["setpriv", "--pdeathsig", "TERM", "python3", root.agentPath]
    stdout: SplitParser { onRead: function(data) { root.onAgentLine(data) } }
    onExited: restartTimer.start()
  }

  Timer {
    id: restartTimer
    interval: 2000
    onTriggered: if (!agentProc.running) agentProc.running = true
  }

  // Presence expiry
  Timer {
    interval: 1500
    running: true
    repeat: true
    onTriggered: {
      var now = Date.now()
      var changed = false
      for (var id in root.peers) {
        if (now - root.peers[id].seen > 7000) { delete root.peers[id]; changed = true }
      }
      if (changed) root.rebuildPeers()
    }
  }

  // One-shot sender; queues while the previous send is in flight.
    property var _sendQueue: []
  function sendEmoji(ip, emoji) {
    var item = { ip: ip, emoji: emoji }
    if (sendProc.running) { root._sendQueue.push(item); return }
    sendProc.command = ["setpriv", "--pdeathsig", "TERM", "python3", root.agentPath,
      "send", ip, emoji, root.myName || "laptop"]
    sendProc._item = item
    sendProc.running = true
  }

  Process {
    id: sendProc
    property var _item: null
    onExited: {
      if (_item) {
        // local echo so sending feels the same as receiving
        root.spawnFloat(_item.emoji, root.myName + " →", true)
        _item = null
      }
      if (root._sendQueue.length > 0) {
        var next = root._sendQueue.shift()
        command = ["setpriv", "--pdeathsig", "TERM", "python3", root.agentPath,
          "send", next.ip, next.emoji, root.myName || "laptop"]
        _item = next
        running = true
      }
    }
  }

  // ------------------------------------------------------------ floaters

  function spawnFloat(emoji, from, isMine) {
    if (floatLayer.children.length >= root.maxFloaters) floatLayer.children[0].destroy()
    var props = {
      emoji: emoji || "🎉",
      from: String(from || ""),
      startX: Math.random() * Math.max(100, root.width - 160),
      duration: 6000 + Math.random() * 3000,
      mine: !!isMine
    }
    floatComp.createObject(floatLayer, props)
  }

  Component {
    id: floatComp

    Item {
      id: floater

      property string emoji
      property string from
      property real startX: 0
      property int duration: 7000
      property bool mine: false

      x: startX
      width: 180
      height: 120

      Text {
        id: glyph
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        text: parent.emoji
        font.pixelSize: 72
        opacity: 0
        scale: 0.5
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: glyph.bottom
        anchors.topMargin: 2
        text: parent.from
        color: "#ffffff"
        opacity: 0.65
        font.pixelSize: 13
      }

      SequentialAnimation {
        running: true
        ParallelAnimation {
          NumberAnimation { target: floater; property: "y"; from: floater.parent.height + 40; to: -140; duration: floater.duration; easing.type: Easing.InOutSine }
          SequentialAnimation {
            NumberAnimation { target: glyph; property: "opacity"; from: 0; to: 1; duration: 400 }
            NumberAnimation { target: glyph; property: "opacity"; to: 1; duration: floater.duration - 2200 }
            NumberAnimation { target: glyph; property: "opacity"; to: 0; duration: 1400 }
          }
          NumberAnimation { target: glyph; property: "scale"; from: 0.5; to: 1.1; duration: 500; easing.type: Easing.OutBack }
          SequentialAnimation {
            NumberAnimation { target: floater; property: "x"; to: floater.startX + 18; duration: 1600; easing.type: Easing.InOutSine }
            NumberAnimation { target: floater; property: "x"; to: floater.startX - 18; duration: 1600; easing.type: Easing.InOutSine }
            NumberAnimation { target: floater; property: "x"; to: floater.startX; duration: 1600; easing.type: Easing.InOutSine }
          }
        }
        ScriptAction { script: floater.destroy() }
      }
    }
  }

  // ------------------------------------------------------------- window

  PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-emoji-swarm"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    // click-through everywhere except the HUD pill (closed) / whole panel (open)
    mask: root.opened ? inputAll : inputHud

    Region { id: inputAll; item: contentRoot }
    Region { id: inputHud; item: hud }

    Item {
      id: contentRoot
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: if (root.opened) root.close()

      // dimmer + click-away while picking
      Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.opened ? 0.25 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
      }
      MouseArea {
        anchors.fill: parent
        enabled: root.opened
        onClicked: root.close()
      }

      // floating emoji layer
      Item {
        id: floatLayer
        anchors.fill: parent
      }

      // picker card
        Rectangle {
        id: card
        visible: root.opened
        anchors.centerIn: parent
        width: Math.min(420, parent.width - 48)
        height: 460
        radius: 16
        color: "#ee1c1f26"
        border.color: "#44ffffff"
        border.width: 1

        Column {
          anchors.fill: parent
          anchors.margins: 18
          spacing: 10

          Item {
            width: parent.width
            height: 28
            Text { text: "Swarm"; color: "#fff"; font.pixelSize: 18; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            Text { text: root.peersList.length + " nearby"; color: "#9effff"; font.pixelSize: 12; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
          }

          Text {
            width: parent.width
            text: root.peersList.length === 0
              ? "No laptops yet — open kamil.swarm on another Omarchy machine."
              : "Pick a laptop, then an emoji."
            color: "#9effff"
            opacity: 0.7
            font.pixelSize: 12
            elide: Text.ElideRight
          }

          // peers
          Column {
            width: parent.width
            spacing: 4

            Repeater {
              model: root.peersList

              delegate: Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: 34
                radius: 8
                color: index === root.selectedPeer ? "#33ffffff" : "transparent"
                border.color: index === root.selectedPeer ? "#66ffffff" : "#22ffffff"
                border.width: 1

                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: 10
                  spacing: 8
                  Text { text: "💻"; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                  Text { text: modelData.name; color: "#fff"; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                  Text { text: modelData.ip; color: "#9effff"; opacity: 0.5; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.selectedPeer = index
                }
              }
            }

            Text {
              visible: root.peersList.length === 0
              text: "waiting for beacons…"
              color: "#9effff"
              opacity: 0.4
              font.pixelSize: 12
            }
          }

          // emoji grid
          Flow {
            width: parent.width
            spacing: 4

            Repeater {
              model: ["😀","😂","🥰","😍","😎","🤩","🥳","🤗","🤔","🙃","😴","🫠","🤌","👀","🙏","👏","👍","🚀","🔥","✨","⚡","🎉","🎊","💖","⭐","🍕","🍩","☕","🍺","🧠","🦄","🐈","🦀","💩","🗿","💣"]

              delegate: Rectangle {
                required property string modelData
                required property int index
                width: 44
                height: 40
                radius: 8
                color: ma.containsMouse ? "#33ffffff" : "transparent"

                Text { anchors.centerIn: parent; text: parent.modelData; font.pixelSize: 22 }

                MouseArea {
                  id: ma
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: {
                    var target = root.selectedPeer >= 0 && root.selectedPeer < root.peersList.length
                      ? root.peersList[root.selectedPeer].ip : "255.255.255.255"
                    root.sendEmoji(target, parent.modelData)
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: root.selectedPeer >= 0
              ? "→ sending to " + root.peersList[root.selectedPeer].name + "  ·  Esc closes"
              : "no laptop selected — broadcasts to the swarm  ·  Esc closes"
            color: "#9effff"
            opacity: 0.5
            font.pixelSize: 11
            elide: Text.ElideRight
          }
        }
      }

      // passive HUD
      Rectangle {
        id: hud
        visible: !root.opened
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 14
        radius: 12
        width: hudRow.width + 20
        height: 26
        color: "#88000000"
        border.color: "#33ffffff"
        border.width: 1

        Row {
          id: hudRow
          anchors.centerIn: parent
          spacing: 6
          Text { text: "🐝"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
          Text {
            text: root.peersList.length > 0 ? root.peersList.length + " nearby" : "swarm"
            color: "#fff"
            opacity: 0.8
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.open()
        }
      }
    }
  }

  Component.onCompleted: {
    agentProc.running = true
    hudTimer.start()
  }

    // small stagger so the first beacon round is picked up
  Timer {
    id: hudTimer
    interval: 500
    onTriggered: root.rebuildPeers()
  }
}

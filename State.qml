import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Audio state. One instance, shared by the standalone bar widget and by Deck.
//
// Everything here reads Quickshell's Pipewire service, which is a shell-wide
// singleton, so there is no helper binary and no polling: the properties are
// live bindings.
Item {
  id: s

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: sink ? sink.audio : null

  // Tile face.
  readonly property bool active: !!audio && !audio.muted
  readonly property int volume: audio ? Math.round(audio.volume * 100) : 0
  readonly property bool muted: audio ? !!audio.muted : false

  readonly property string label: "Audio"
  readonly property string detail: muted ? "muted" : (volume + "%")
  readonly property string icon: "󰕾"

  readonly property string deviceName: {
    if (!sink) return "No output device"
    return String(sink.nickname || sink.description || sink.name || "Output")
  }

  readonly property var sinks: {
    var src = Pipewire.nodes ? Pipewire.nodes.values : []
    var out = []
    for (var i = 0; i < src.length; i++) {
      var n = src[i]
      if (n && n.isSink && !n.isStream) out.push(n)
    }
    return out
  }

  function toggle() {
    if (audio) audio.muted = !audio.muted
  }

  function setVolume(pct) {
    if (!audio) return
    audio.volume = Math.max(0, Math.min(1.5, Number(pct) / 100))
  }

  function setDefault(node) {
    if (node) Pipewire.preferredDefaultAudioSink = node
  }

  function nodeLabel(node) {
    if (!node) return ""
    return String(node.nickname || node.description || node.name || "?")
  }

  function isDefault(node) {
    return !!sink && !!node && node.id === sink.id
  }
}

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io

// Audio state. One instance, shared by the standalone bar widget and by Deck.
//
// Output, input and per-app streams are live Quickshell Pipewire bindings.
// Codec and sample rate come from the `audio-capability` helper, which is the
// one place that joins what the hardware advertises with what the graph is
// actually using. Its report is JSON on stdout; every action it offers is a
// flag on the same command.
Item {
  id: s

  // ---------------------------------------------------------------- output
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var audio: sink ? sink.audio : null

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

  // ----------------------------------------------------------------- input
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var sourceAudio: source ? source.audio : null
  readonly property int inputVolume: sourceAudio ? Math.round(sourceAudio.volume * 100) : 0
  readonly property bool inputMuted: sourceAudio ? !!sourceAudio.muted : false
  readonly property string sourceName: {
    if (!source) return "No input device"
    return String(source.nickname || source.description || source.name || "Input")
  }

  // Live input level, for the meter under the input slider. The monitor runs
  // only while a page that shows it is open: it is a capture stream, and a
  // permanent one in the bar would be a cost for a number nobody is reading.
  property bool meterActive: false
  readonly property real inputPeak: (inputMonitor.enabled ? inputMonitor.peak : 0)

  PwObjectTracker {
    objects: s.source ? [s.source] : []
  }

  PwNodePeakMonitor {
    id: inputMonitor
    node: s.source
    enabled: s.meterActive && !!s.source
  }

  readonly property var sources: {
    var src = Pipewire.nodes ? Pipewire.nodes.values : []
    var out = []
    for (var i = 0; i < src.length; i++) {
      var n = src[i]
      if (!n || n.isSink || n.isStream) continue
      var t = String(n.type || "")
      if (n.audio || t.indexOf("Audio/Source") !== -1 || t.indexOf("AudioSource") !== -1)
        out.push(n)
    }
    return out
  }

  function setInputVolume(pct) {
    if (!sourceAudio) return
    sourceAudio.volume = Math.max(0, Math.min(1.5, Number(pct) / 100))
  }

  function toggleInputMute() {
    if (sourceAudio) sourceAudio.muted = !sourceAudio.muted
  }

  function setDefaultSource(node) {
    if (node) Pipewire.preferredDefaultAudioSource = node
  }

  function isDefaultSource(node) {
    return !!source && !!node && node.id === source.id
  }

  // --------------------------------------------------------------- streams
  function props(node) {
    return (node && node.ready && node.properties) ? node.properties : {}
  }

  readonly property var streams: {
    var src = Pipewire.nodes ? Pipewire.nodes.values : []
    var out = []
    for (var i = 0; i < src.length; i++) {
      var n = src[i]
      if (!n || !n.isStream || !n.audio) continue
      var t = String(n.type || "")
      if (n.isSink === true || t.indexOf("Stream/Output/Audio") !== -1
          || t.indexOf("AudioOutStream") !== -1)
        out.push(n)
    }
    return out
  }

  function streamLabel(node) {
    var p = props(node)
    return String(p["application.name"] || node.description || p["media.name"]
      || p["node.name"] || node.name || "Stream")
  }

  function streamVolume(node) {
    return node && node.audio ? Math.round(node.audio.volume * 100) : 0
  }

  function isStreamMuted(node) {
    return node && node.audio ? !!node.audio.muted : false
  }

  function setStreamVolume(node, pct) {
    if (!node || !node.audio) return
    node.audio.volume = Math.max(0, Math.min(1.5, Number(pct) / 100))
  }

  function toggleStreamMute(node) {
    if (node && node.audio) node.audio.muted = !node.audio.muted
  }

  // ------------------------------------------------------- codec and rate
  property var report: ({})
  property bool reportLoaded: false

  readonly property var bt: report.codec || ({})
  readonly property bool isBluetooth: {
    var d = report.device
    return !!(d && String(d.sink || "").indexOf("bluez_output.") === 0)
  }
  readonly property var warnings: report.warnings || []

  readonly property int forcedRate: {
    var pol = report.policy
    return (pol && pol.forcedRate) ? Number(pol.forcedRate) : 0
  }

  // Only the intersection of what the device advertises and what the clock is
  // allowed to reach. A rate outside it would be a control that is accepted
  // and does nothing.
  readonly property var rateOptions: {
    var cap = (report.capability && report.capability.rates) || []
    var allowed = (report.policy && report.policy.allowedRates) || []
    var out = []
    for (var i = 0; i < cap.length; i++)
      if (allowed.indexOf(cap[i]) !== -1) out.push(cap[i])
    return out
  }

  readonly property var hardwareRates: (report.capability && report.capability.rates) || []
  readonly property int inUseRate: (report.inUse && report.inUse.rate) ? Number(report.inUse.rate) : 0
  readonly property bool canApplyRates: hardwareRates.length > 0 && rateOptions.length === 0

  function fmtHz(rate) {
    var r = Number(rate)
    if (!r) return "—"
    return (r >= 1000 ? (Math.round(r / 100) / 10) : Math.round(r)) + " kHz"
  }

  readonly property string rateLabel: {
    if (forcedRate > 0) return "Pinned at " + fmtHz(forcedRate)
    return inUseRate ? "Auto — following " + fmtHz(inUseRate) : "Auto — follows what is playing"
  }

  readonly property string codecLabel: {
    if (!isBluetooth) return ""
    var cur = bt.current
    return cur ? String(cur).toUpperCase() + " in use" : "Not connected"
  }

  readonly property string qualityLabel: {
    var q = bt.ldacQuality
    return q ? ("LDAC " + String(q).toUpperCase()) : ""
  }

  readonly property string bitrateLabel: {
    var b = bt.aacBitrateMode
    return (b !== null && b !== undefined) ? ("AAC mode " + b) : ""
  }

  // ------------------------------------------------------- headphone EQ
  readonly property string eqHelper: String(Qt.resolvedUrl("scripts/audio-eq")).replace("file://", "")
  property var eq: ({})
  property bool eqLoaded: false
  property var eqProfiles: []
  property var eqSearchResults: []
  property bool eqSearching: false
  property string eqError: ""

  readonly property bool eqOn: eq.on === true
  readonly property string eqProfile: String(eq.profile || "")
  readonly property real eqPreamp: Number(eq.preamp || 0)
  readonly property var eqBands: eq.bands || []
  readonly property string eqHardware: String(eq.hardware || "")
  readonly property bool eqSinkUp: eq.sinkUp === true

  Process {
    id: eqStatusProc
    command: [s.eqHelper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        try {
          s.eq = JSON.parse(raw)
          s.eqLoaded = true
          s.refreshReport()
        } catch (e) {
        }
      }
    }
  }

  Process {
    id: eqListProc
    command: [s.eqHelper, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        try { s.eqProfiles = JSON.parse(raw) } catch (e) {}
      }
    }
  }

  Process {
    id: eqSearchProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        s.eqSearching = false
        if (raw === "") return
        try { s.eqSearchResults = JSON.parse(raw) } catch (e) { s.eqSearchResults = [] }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var e = String(text || "").trim()
        if (e !== "") s.eqError = e.split("\n")[0]
        s.eqSearching = false
      }
    }
  }

  Process {
    id: eqActionProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        try {
          var res = JSON.parse(raw)
          if (res && res.ok === false) s.eqError = String(res.error || "EQ action failed")
        } catch (e) {}
      }
    }
    onExited: function(code) {
      if (code === 0) s.eqError = ""
      s.refreshEq()
      s.eqListProfiles()
    }
  }

  function refreshEq() {
    if (!eqStatusProc.running) eqStatusProc.running = true
  }

  function eqListProfiles() {
    if (!eqListProc.running) eqListProc.running = true
  }

  function eqRun(args) {
    eqActionProc.command = [s.eqHelper].concat(args)
    eqActionProc.running = true
  }

  function eqToggle() {
    s.eqRun([s.eqOn ? "off" : "on"])
  }

  function eqApply(profile, preamp, gains) {
    var args = ["apply", String(profile)]
    if (preamp !== undefined && preamp !== null) args = args.concat(["--preamp", String(preamp)])
    if (gains && gains.length)
      args = args.concat(["--gains", gains.join(",")])
    s.eqRun(args)
  }

  function eqApplyBands(profile, preamp, bands) {
    var args = ["apply", String(profile)]
    if (preamp !== undefined && preamp !== null)
      args = args.concat(["--preamp", String(preamp)])
    if (bands && bands.length)
      args = args.concat(["--bands-json", JSON.stringify(bands)])
    s.eqRun(args)
  }

  function eqSearch(query) {
    var q = String(query || "").trim()
    if (q === "") return
    s.eqSearching = true
    s.eqSearchResults = []
    s.eqError = ""
    eqSearchProc.command = [s.eqHelper, "search", q]
    eqSearchProc.running = true
  }

  function eqImport(url, name) {
    var args = ["import", String(url)]
    if (name) args.push(String(name))
    s.eqRun(args)
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: s.refreshEq()
  }

  Process {
    id: capProc
    command: ["audio-capability"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        try {
          s.report = JSON.parse(raw)
          s.reportLoaded = true
        } catch (e) {
        }
      }
    }
  }

  function refreshReport() {
    // With EQ on, the default sink is the filter sink, which has no hardware
    // capability. Probe the hardware the filter feeds instead.
    var args = ["audio-capability"]
    if (s.eqOn && s.eqHardware !== "") args = args.concat(["--device", s.eqHardware])
    capProc.command = args
    if (!capProc.running) capProc.running = true
  }

  function runCap(args) {
    Quickshell.execDetached(["audio-capability"].concat(args))
    capSettle.restart()
  }

  function setRate(rate) {
    runCap(["--rate", String(rate)])
  }

  function setCodec(codec) {
    runCap(["--codec", String(codec)])
  }

  function setCodecPref(arg) {
    runCap(["--codec-pref", String(arg)])
  }

  function applyFullRate() {
    runCap(["--apply"])
  }

  function activateFullRate() {
    runCap(["--activate"])
  }

  Timer {
    id: capSettle
    interval: 900
    onTriggered: s.refreshReport()
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: s.refreshReport()
  }

  Component.onCompleted: {
    refreshReport()
    refreshEq()
    eqListProfiles()
  }
}

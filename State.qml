import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io
import qs.Commons
import "/usr/share/omarchy/shell/plugins/panels/audio/Model.js" as AudioModel

// Audio state. One instance, shared by the standalone bar widget and by Deck.
//
// Output, input and per-app streams are live Quickshell Pipewire bindings.
// Codec and sample rate come from the `audio-capability` helper, which is the
// one place that joins what the hardware advertises with what the graph is
// actually using. Its report is JSON on stdout; every action it offers is a
// flag on the same command.
Item {
  id: s

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ---------------------------------------------------------------- output
  readonly property var defaultSink: Pipewire.defaultAudioSink
  property string effectiveSinkName: ""
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var sink: {
    if (!defaultSink) return null
    if (effectiveSinkName === "") return defaultSink
    for (var i = 0; i < nodes.length; i++)
      if (nodes[i] && nodes[i].name === effectiveSinkName) return nodes[i]
    return defaultSink
  }
  readonly property var audio: sink ? sink.audio : null

  readonly property bool active: !!audio && !audio.muted
  readonly property int volume: audio ? Math.round(audio.volume * 100) : 0
  readonly property bool muted: audio ? !!audio.muted : false

  readonly property string label: strings.t("audio.audio")
  readonly property string detail: muted ? "muted" : (volume + "%")
  readonly property string icon: "󰕾"

  readonly property string deviceName: {
    if (!defaultSink) return "No output device"
    return String(defaultSink.nickname || defaultSink.description || defaultSink.name || "Output")
  }

  function resolveEffectiveSink() {
    if (!defaultSink) { effectiveSinkName = ""; return }
    // Deck's EQ deliberately exposes its own preamp/volume model.
    if (String(defaultSink.name || "") === "deck_eq") {
      effectiveSinkName = "deck_eq"
      return
    }
    effectiveSinkResolver.command = ["omarchy-audio-output-sink", String(defaultSink.name || "")]
    if (!effectiveSinkResolver.running) effectiveSinkResolver.running = true
  }
  onDefaultSinkChanged: resolveEffectiveSink()

  Process {
    id: effectiveSinkResolver
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: s.effectiveSinkName = text.trim()
    }
  }

  readonly property var nodeNames: {
    var names = []
    for (var i = 0; i < nodes.length; i++) if (nodes[i] && nodes[i].name) names.push(String(nodes[i].name))
    return names
  }
  function platformHides(node) { return !!node && AudioNodes.platformHides(node.name, nodeNames) }

  property var sinkAvailability: ({})
  property var sourceAvailability: ({})
  property bool availabilityLoaded: false
  function parseAvailability(raw, target) {
    var next = ({})
    var lines = String(raw || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      if (parts.length === 2 && parts[0] !== "") next[parts[0]] = parts[1] === "1"
    }
    if (target === "sinks") s.sinkAvailability = next
    else s.sourceAvailability = next
    s.availabilityLoaded = true
  }
  function refreshAvailability() {
    if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
    if (!sourceAvailabilityProc.running) sourceAvailabilityProc.running = true
  }
  Process {
    id: sinkAvailabilityProc
    command: ["omarchy-audio-sink-availability"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: s.parseAvailability(text, "sinks") }
  }
  Process {
    id: sourceAvailabilityProc
    command: ["omarchy-audio-sink-availability", "sources"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: s.parseAvailability(text, "sources") }
  }
  Timer {
    interval: 5000
    repeat: true
    running: s.meterActive
    onTriggered: s.refreshAvailability()
  }
  onNodesChanged: if (availabilityLoaded) refreshAvailability()

  readonly property var sinks: {
    var out = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isSink || n.isStream || platformHides(n)) continue
      if (availabilityLoaded && sinkAvailability[String(n.name || "")] === false && n !== defaultSink) continue
      out.push(n)
    }
    return out
  }

  // Delegates hold primitives only. PipeWire can delete a node while a delegate
  // is being built; the live object is resolved again at the action itself, and
  // the constant name prevents an id recycled for another node being selected.
  function nodeById(id, name, list) {
    for (var i = 0; i < (list || []).length; i++) {
      var n = list[i]
      if (n && n.id === id && String(n.name || "") === String(name || "")) return n
    }
    return null
  }

  readonly property var sinkChoices: {
    var out = []
    for (var i = 0; i < sinks.length; i++) {
      var n = sinks[i]
      out.push({ id: n.id, name: String(n.name || ""), text: nodeLabel(n), current: isDefault(n) })
    }
    return out
  }
  function setDefaultChoice(id, name) { setDefault(nodeById(id, name, sinks)) }

  function toggle() {
    if (audio) audio.muted = !audio.muted
  }

  function setVolume(pct) {
    if (!audio) return
    audio.volume = Math.max(0, Math.min(1.5, Number(pct) / 100))
  }

  function setDefault(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    Quickshell.execDetached(["omarchy-audio-output-set-default", String(node.id), String(node.name)])
  }

  function nodeLabel(node) {
    if (!node) return ""
    return String(node.nickname || node.description || node.name || "?")
  }

  function isDefault(node) {
    return !!defaultSink && !!node && node.id === defaultSink.id
  }

  // ----------------------------------------------------------------- input
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var sourceAudio: source ? source.audio : null
  readonly property int inputVolume: sourceAudio ? Math.round(sourceAudio.volume * 100)
    : (UntypedInput.known ? Math.round(UntypedInput.volume * 100) : 0)
  readonly property bool inputMuted: sourceAudio ? !!sourceAudio.muted : UntypedInput.muted
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
    var out = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || n.isSink || n.isStream || platformHides(n) || String(n.name || "") === "quickshell") continue
      if (!AudioModel.isAudioSource(n) && !AudioModel.isUntypedSource(n, sourceAvailability)) continue
      if (availabilityLoaded && sourceAvailability[String(n.name || "")] === false && n !== source) continue
      out.push(n)
    }
    return out
  }

  readonly property var sourceChoices: {
    var out = []
    for (var i = 0; i < sources.length; i++) {
      var n = sources[i]
      out.push({ id: n.id, name: String(n.name || ""), text: nodeLabel(n), current: isDefaultSource(n) })
    }
    return out
  }
  function setDefaultSourceChoice(id, name) { setDefaultSource(nodeById(id, name, sources)) }

  function setInputVolume(pct) {
    var value = Math.max(0, Math.min(1.5, Number(pct) / 100))
    if (sourceAudio) sourceAudio.volume = value
    else UntypedInput.setVolume(Math.min(1, value))
  }

  function toggleInputMute() {
    if (sourceAudio) sourceAudio.muted = !sourceAudio.muted
    else UntypedInput.setMuted(!inputMuted)
  }

  function setDefaultSource(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSource = node
    Quickshell.execDetached(["omarchy-audio-input-set-default", String(node.id), String(node.name)])
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

  readonly property var streamRows: {
    var out = []
    for (var i = 0; i < streams.length; i++) {
      var n = streams[i]
      out.push({ id: n.id, name: String(n.name || ""), label: streamLabel(n),
        volume: streamVolume(n), muted: isStreamMuted(n) })
    }
    return out
  }
  function setStreamVolumeById(id, name, pct) {
    setStreamVolume(nodeById(id, name, streams), pct)
  }
  function toggleStreamMuteById(id, name) { toggleStreamMute(nodeById(id, name, streams)) }

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

  readonly property var hardwareRates: (report.capability && report.capability.rates) || []
  readonly property int inUseRate: (report.inUse && report.inUse.rate) ? Number(report.inUse.rate) : 0

  function fmtHz(rate) {
    var r = Number(rate)
    if (!r) return "-"
    return (r >= 1000 ? (Math.round(r / 100) / 10) : Math.round(r)) + " kHz"
  }

  readonly property string rateLabel: {
    if (forcedRate > 0) return "Pinned at " + fmtHz(forcedRate)
    return inUseRate ? "Auto, following " + fmtHz(inUseRate) : "Auto, follows what is playing"
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
  readonly property string capHelper: String(Qt.resolvedUrl("scripts/audio-capability")).replace("file://", "")
  readonly property string eqHelper: String(Qt.resolvedUrl("scripts/audio-eq")).replace("file://", "")
  property var eq: ({})
  property bool eqLoaded: false
  property var eqProfiles: []
  property var eqSearchResults: []
  property bool eqSearching: false
  // Providers whose index could not be read for the last search, by source id.
  property var eqSearchFailed: []
  property var eqSources: []
  property string eqSourcesError: ""
  property bool eqSourcesBusy: false
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

  // A new query while one is in flight replaces it: the old process is killed
  // and the newest text is started once it has exited, so a slow response for
  // "hd" can never overwrite the results for "hd 650".
  property string eqPendingQuery: ""

  Process {
    id: eqSearchProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (s.eqPendingQuery !== "") return
        s.eqSearching = false
        if (raw === "") return
        try {
          var res = JSON.parse(raw)
          if (res && res.ok === false) {
            s.eqSearchResults = []
            s.eqError = String(res.error || "search failed")
          } else {
            s.eqSearchResults = res.results || []
            s.eqSearchFailed = res.failed || []
          }
        } catch (e) { s.eqSearchResults = [] }
      }
    }
    onExited: function(code) {
      if (s.eqPendingQuery === "") return
      var q = s.eqPendingQuery
      s.eqPendingQuery = ""
      s.eqStartSearch(q)
    }
  }

  Process {
    id: eqSourcesProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        s.eqSourcesBusy = false
        if (raw === "") return
        try {
          var res = JSON.parse(raw)
          if (res && res.ok === false) s.eqSourcesError = String(res.error || "that did not work")
          else {
            s.eqSources = res.sources || []
            s.eqSourcesError = ""
          }
        } catch (e) {}
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

  function eqStartSearch(q) {
    s.eqSearching = true
    eqSearchProc.command = [s.eqHelper, "search", q]
    eqSearchProc.running = true
  }

  function eqSearch(query) {
    var q = String(query || "").trim()
    s.eqError = ""
    if (q === "") {
      s.eqPendingQuery = ""
      eqSearchProc.running = false
      s.eqSearching = false
      s.eqSearchResults = []
      return
    }
    if (eqSearchProc.running) {
      s.eqPendingQuery = q
      eqSearchProc.running = false
      return
    }
    s.eqStartSearch(q)
  }

  property var eqProviders: []

  Process {
    id: eqProvidersProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { s.eqProviders = JSON.parse(String(text || "{}")).providers || [] } catch (e) {}
      }
    }
  }

  function eqLoadProviders() {
    if (eqProvidersProc.running) return
    eqProvidersProc.command = [s.eqHelper, "providers"]
    eqProvidersProc.running = true
  }

  // Switching a provider is local and instant: the list is patched in place,
  // the helper's file is the record.
  function eqProviderEnable(name, on) {
    var next = s.eqProviders.map(function(p) {
      return p.provider === name ? Object.assign({}, p, { enabled: on }) : p
    })
    s.eqProviders = next
    Quickshell.execDetached([s.eqHelper, "provider-enable", String(name), on ? "on" : "off"])
  }

  function eqSaveProfile(name, preamp, bands) {
    s.eqRun(["save", String(name), "--preamp", String(preamp), "--bands-json", JSON.stringify(bands || [])])
  }

  function eqDeleteProfile(name) {
    s.eqRun(["delete", String(name)])
  }

  function eqSourcesRun(args) {
    if (eqSourcesProc.running) return
    s.eqSourcesBusy = true
    eqSourcesProc.command = [s.eqHelper].concat(args)
    eqSourcesProc.running = true
  }

  function eqLoadSources() { s.eqSourcesRun(["sources"]) }
  function eqSourceAdd(kind, target, name) {
    var a = ["source-add", String(kind), String(target)]
    if (name) a.push(String(name))
    s.eqSourcesError = ""
    s.eqSourcesRun(a)
  }
  function eqSourceRemove(id) { s.eqSourcesRun(["source-remove", String(id)]) }
  function eqSourceEnable(id, on) { s.eqSourcesRun(["source-enable", String(id), on ? "on" : "off"]) }
  function eqSourceRefresh(id) {
    var a = ["source-refresh"]
    if (id) a.push(String(id))
    s.eqSourcesRun(a)
  }

  // A result from a search: the name carries the provider, because the same
  // headphone is published by several and they must not overwrite each other.
  function eqApplyResult(r) {
    var args = ["apply", String(r.url), "--as", String(r.name) + " (" + String(r.provider) + ")"]
    s.eqRun(args)
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
    command: [s.capHelper]
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
    var args = [s.capHelper]
    if (s.eqOn && s.eqHardware !== "") args = args.concat(["--device", s.eqHardware])
    capProc.command = args
    if (!capProc.running) capProc.running = true
  }

  // ---------------------------------------------------- rate registration
  // `--status` is the read-only view of what is written and what is live; the
  // three writing modes run as tracked processes so the page can say it is
  // working and show a refusal instead of silently doing nothing.
  property var capStatus: ({})
  property bool capBusy: false
  property string capMessage: ""

  readonly property var liveAllowed: {
    var l = capStatus.liveAllowedRates
    if (l && l.length) return l
    return (report.policy && report.policy.allowedRates) || []
  }
  readonly property bool filesOurs: {
    var f = capStatus.files
    return !!f && ((f.global && f.global.state === "ours") || (f.device && f.device.state === "ours"))
  }
  readonly property bool needsLive: capStatus.rulesExpected === true && capStatus.rulesLanded !== true
  readonly property var unregisteredRates: {
    var out = []
    for (var i = 0; i < hardwareRates.length; i++)
      if (liveAllowed.indexOf(hardwareRates[i]) === -1) out.push(hardwareRates[i])
    return out
  }
  // What the device says it can do; when it says nothing, the rates the clock
  // may switch between, which the helper will refuse if the device cannot take them.
  // Nothing registered and nothing reported (a fresh start, or after Remove)
  // would leave the list empty and nothing to discover, so offer the usual ones.
  readonly property var rateChoices: hardwareRates.length > 0 ? hardwareRates
    : (liveAllowed.length > 0 ? liveAllowed : [44100, 48000, 88200, 96000, 176400, 192000])

  Process {
    id: capStatusProc
    command: [s.capHelper, "--status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") return
        try { s.capStatus = JSON.parse(raw) } catch (e) {}
      }
    }
  }

  Process {
    id: capActProc
    command: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        s.capMessage = lines.length ? lines[lines.length - 1] : ""
      }
    }
    onExited: function(code) {
      s.capBusy = false
      if (code === 0) s.capMessage = ""
      s.refreshReport()
      s.refreshStatus()
    }
  }

  function refreshStatus() {
    if (!capStatusProc.running) capStatusProc.running = true
  }

  function capAct(command) {
    if (s.capBusy) return
    s.capBusy = true
    s.capMessage = ""
    capActProc.command = command
    capActProc.running = true
  }

  function registerRates() { capAct([s.capHelper, "--apply"]) }
  function makeLive() { capAct([s.capHelper, "--activate"]) }
  function removeRegistration() { capAct([s.capHelper, "--revert"]) }

  // A rate the clock is not yet allowed to reach has to be registered first;
  // the helper refuses to pin one that is not.
  function registerAndPin(rate) {
    capAct(["bash", "-c", '"$1" --apply && "$1" --rate "$2"', "_", s.capHelper, String(rate)])
  }

  function runCap(args) {
    Quickshell.execDetached([s.capHelper].concat(args))
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
    resolveEffectiveSink()
    refreshAvailability()
    refreshReport()
    refreshStatus()
    refreshEq()
    eqListProfiles()
  }
}

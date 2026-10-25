import QtQuick
import qs.Commons

// Audio page, rendered by Deck and by this plugin's own popup.
//
// Structure borrowed from the strongest audio panels on the Omarchy
// marketplace: a hero that names the device and its role, caps section labels
// with a trailing value, sliders whose value sits on the right, and compact
// rows whose trailing mark says which device is current.
Item {
  id: page

  property var state: null
  property var host: null

  implicitHeight: col.implicitHeight
  readonly property real level: state ? Math.max(0, Math.min(1, state.volume / 100)) : 0
  // Which view of the page is showing. The equalizer is large enough to be a
  // page of its own: reached from a row on the main view, with a way back.
  property string view: "main"
  property bool outPickOpen: false
  property bool inPickOpen: false
  property bool appsOpen: true
  property bool advOpen: false

  readonly property var sinkRows: {
    var out = []
    var list = page.state ? page.state.sinks : []
    for (var i = 0; i < list.length; i++)
      out.push({ text: page.state.nodeLabel(list[i]), current: page.state.isDefault(list[i]) })
    return out
  }
  readonly property var profileRows: {
    var out = []
    var list = page.state ? page.state.eqProfiles : []
    for (var i = 0; i < list.length; i++)
      out.push({ text: String(list[i].name), current: page.state.eqProfile === String(list[i].name) })
    return out
  }
  readonly property var sourceRows: {
    var out = []
    var list = page.state ? page.state.sources : []
    for (var i = 0; i < list.length; i++)
      out.push({ text: page.state.nodeLabel(list[i]), current: page.state.isDefaultSource(list[i]) })
    return out
  }

  property bool ratePickOpen: false
  property bool codecPickOpen: false
  property bool prefPickOpen: false
  property bool qualPickOpen: false
  property bool bitPickOpen: false
  property bool removeArmed: false

  Timer {
    id: removeDisarm
    interval: 3500
    onTriggered: page.removeArmed = false
  }

  readonly property var rateRows: {
    var out = [{ text: "Auto, follows what is playing", rate: 0, registered: true,
                 current: !!page.state && page.state.forcedRate === 0 }]
    if (!page.state) return out
    var list = page.state.rateChoices
    for (var i = 0; i < list.length; i++) {
      var reg = page.state.liveAllowed.indexOf(list[i]) !== -1
      out.push({ text: page.state.fmtHz(list[i]) + (reg ? "" : "  · not registered"),
                 rate: list[i], registered: reg, current: page.state.forcedRate === list[i] })
    }
    return out
  }
  readonly property var codecRows: {
    var out = []
    var list = page.state ? (page.state.bt.known || []) : []
    for (var i = 0; i < list.length; i++)
      out.push({ text: String(list[i]).toUpperCase(), value: list[i],
                 current: page.state.bt.current === list[i] })
    return out
  }
  readonly property var prefRows: {
    var out = [{ text: "No preference", value: "", current: !!page.state && (page.state.bt.preferred || []).length === 0 }]
    var list = page.state ? (page.state.bt.known || []) : []
    for (var i = 0; i < list.length; i++)
      out.push({ text: String(list[i]).toUpperCase(), value: list[i],
                 current: (page.state.bt.preferred || [])[0] === list[i] })
    return out
  }
  readonly property var qualRows: {
    var q = page.state ? page.state.bt.ldacQuality : null
    return [["auto", "Auto"], ["hq", "High quality"], ["sq", "Standard"], ["mq", "Connection first"]]
      .map(function(r) { return { text: r[1], value: r[0], current: q === r[0] } })
  }
  readonly property var bitRows: {
    var b = page.state ? page.state.bt.aacBitrateMode : null
    var out = []
    for (var i = 0; i <= 5; i++)
      out.push({ text: "Mode " + i + (i === 0 ? " (lowest)" : i === 5 ? " (highest)" : ""), value: i, current: b === i })
    return out
  }

  // ------------------------------------------------------------- equalizer
  property bool eqProfilesOpen: false
  property bool eqSearchOpen: false
  property string eqSearchText: ""
  property var expandedGroups: ({})
  property string addKind: "github"
  property bool addPending: false
  property int bandRevision: 0
  property real eqPreampLocal: 0
  property bool eqDirty: false

  // A ListModel, not a JS array: setProperty updates a slider's band without
  // recreating the delegate, so a gain/frequency/Q drag stays continuous.
  ListModel { id: bandModel }

  function fmtGain(v) {
    var n = Number(v)
    return (n > 0 ? "+" : "") + n.toFixed(1) + " dB"
  }

  function typeLabel(type) {
    return type === "LS" ? "LOW SHELF" : type === "HS" ? "HIGH SHELF" : "PEAK"
  }

  function fmtFreq(v) {
    var n = Number(v)
    if (n >= 1000) return (Math.round(n / 100) / 10) + " kHz"
    return Math.round(n) + " Hz"
  }

  function fmtQ(v) { return Number(v).toFixed(2) }

  function syncEq() {
    if (!state) return
    var src = state.eqBands || []
    bandModel.clear()
    for (var i = 0; i < src.length; i++)
      bandModel.append({
        bandType: String(src[i].type || "PK"),
        freq: Number(src[i].fc || 1000),
        gainDb: Number(src[i].gain || 0),
        qValue: Number(src[i].q || 0.707)
      })
    eqPreampLocal = Number(state.eqPreamp)
    eqDirty = false
    bandRevision++
  }

  function bandsArray() {
    var out = []
    for (var i = 0; i < bandModel.count; i++) {
      var b = bandModel.get(i)
      out.push({ type: b.bandType, fc: b.freq, gain: b.gainDb, q: b.qValue })
    }
    return out
  }

  function bandChanged() {
    eqDirty = true
    bandRevision++
  }

  function setBandField(index, field, value) {
    if (index < 0 || index >= bandModel.count) return
    bandModel.setProperty(index, field, value)
    bandChanged()
  }

  function cycleBandType(index) {
    if (index < 0 || index >= bandModel.count) return
    var order = ["PK", "LS", "HS"]
    var at = order.indexOf(String(bandModel.get(index).bandType || "PK"))
    setBandField(index, "bandType", order[(at + 1) % order.length])
  }

  function addBand() {
    bandModel.append({ bandType: "PK", freq: 1000, gainDb: 0, qValue: 1.0 })
    bandChanged()
  }

  function removeBand(index) {
    if (index < 0 || index >= bandModel.count) return
    bandModel.remove(index)
    bandChanged()
  }

  function applyEqChanges() {
    if (!state || state.eqProfile === "") return
    state.eqApplyBands(state.eqProfile, eqPreampLocal, bandsArray())
    eqDirty = false
  }

  function isAddress(q) {
    return q.indexOf("http://") === 0 || q.indexOf("https://") === 0
  }

  // Typing searches by itself once the text has been still for a second. A
  // pasted address is the exception: it downloads a file, so it waits for Enter.
  function runSearch() {
    if (!state) return
    var q = String(eqSearchText || "").trim()
    if (isAddress(q)) return
    state.eqSearch(q)
  }

  function importAddress() {
    var q = String(eqSearchText || "").trim()
    if (state && isAddress(q)) state.eqApply(q, null, [])
  }

  readonly property var searchGroups: {
    var list = page.state ? page.state.eqSearchResults : []
    var order = [], seen = {}
    for (var i = 0; i < list.length; i++) {
      var r = list[i]
      var k = String(r.provider)
      if (seen[k] === undefined) {
        seen[k] = order.length
        order.push({ provider: k, source: String(r.sourceName), items: [] })
      }
      order[seen[k]].items.push(r)
    }
    return order
  }

  function toggleGroup(provider) {
    var next = {}
    for (var k in expandedGroups) next[k] = expandedGroups[k]
    next[provider] = !(expandedGroups[provider] === true)
    expandedGroups = next
  }

  function kindLabel(kind) {
    return kind === "github" ? "GitHub" : kind === "json" ? "List" : "Folder"
  }

  function ago(t) {
    var n = Number(t)
    if (!(n > 0)) return "not fetched"
    var d = Math.floor((Date.now() / 1000 - n) / 86400)
    return d <= 0 ? "today" : d === 1 ? "yesterday" : d + " days ago"
  }

  Timer {
    id: searchDebounce
    interval: 1000
    onTriggered: page.runSearch()
  }

  onEqSearchTextChanged: {
    if (page.isAddress(String(eqSearchText).trim())) {
      searchDebounce.stop()
      if (state) state.eqSearch("")
    } else {
      searchDebounce.restart()
    }
  }

  onViewChanged: {
    if (!state) return
    if (view === "sources") state.eqLoadSources()
    else if (view === "eq" && String(eqSearchText).trim() !== "") runSearch()
  }

  Connections {
    target: page.state
    function onEqSourcesBusyChanged() {
      if (!page.state.eqSourcesBusy && page.addPending) {
        page.addPending = false
        if (page.state.eqSourcesError === "") {
          addTargetField.text = ""
          addNameField.text = ""
        }
      }
    }
  }

  // The input meter is a capture stream. Run it only while this page is on
  // screen: `host.open` is Deck's (or the standalone popup's) visibility, and a
  // page with no host is a page that is only built when it is about to be shown.
  readonly property bool pageVisible: host && host.open !== undefined ? !!host.open : true
  onStateChanged: {
    if (state) {
      state.meterActive = pageVisible
      syncEq()
    }
  }

  Connections {
    target: page.state
    function onEqProfileChanged() { page.syncEq() }
  }
  onPageVisibleChanged: if (state) state.meterActive = pageVisible
  Component.onDestruction: if (state) state.meterActive = false

  component Caps: Text {
    color: Util.alpha(Color.foreground, 0.45)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  component Rule: Rectangle {
    width: parent ? parent.width : 0
    height: 1
    color: Util.alpha(Color.foreground, 0.1)
  }

  // A label row: glyph, caps title, trailing value.
  component Head: Item {
    id: head
    property string glyph: ""
    property string title: ""
    property string value: ""
    property int gap: 0
    width: parent ? parent.width : 0
    height: Style.space(22) + gap

    Item {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(22)

      Text {
        id: headGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        text: head.glyph
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.left: headGlyph.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: head.title.toUpperCase()
        color: Util.alpha(Color.foreground, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.5
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: head.value
        color: Util.alpha(Color.foreground, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }


  component Switch: Item {
    id: sw
    property bool checked: false
    signal toggled()
    width: Style.space(34)
    height: Style.space(18)

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: sw.checked
        ? Util.alpha(Color.accent, 0.85)
        : Util.alpha(Color.foreground, 0.2)

      Rectangle {
        width: Style.space(14)
        height: width
        radius: width / 2
        y: (parent.height - height) / 2
        x: sw.checked ? parent.width - width - Style.space(2) : Style.space(2)
        color: "#ffffff"
        Behavior on x { NumberAnimation { duration: 90 } }
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.toggled()
    }
  }

  // A horizontal gain slider with a zero mark, for a -12..+12 dB band.
  component GainSlider: Item {
    id: gain
    property real value: 0
    property real minValue: -12
    property real maxValue: 12
    property bool logarithmic: false
    property bool bipolar: true
    signal moved(real v)

    height: Style.space(18)

    readonly property real span: maxValue - minValue
    readonly property real clamped: Math.max(minValue, Math.min(maxValue, value))
    readonly property real pos: {
      if (logarithmic && minValue > 0)
        return Math.log(clamped / minValue) / Math.log(maxValue / minValue)
      return (clamped - minValue) / span
    }
    readonly property real zeroPos: {
      if (!bipolar || minValue > 0 || maxValue < 0) return 0
      return (0 - minValue) / span
    }

    function valueAt(p) {
      var q = Math.max(0, Math.min(1, p))
      if (logarithmic && minValue > 0)
        return minValue * Math.pow(maxValue / minValue, q)
      return minValue + q * span
    }

    Rectangle {
      id: track
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: 3
      radius: 2
      color: Util.alpha(Color.foreground, 0.18)

      Rectangle {
        x: (gain.bipolar ? Math.min(gain.pos, gain.zeroPos) : 0) * track.width
        width: (gain.bipolar
          ? Math.abs(gain.pos - gain.zeroPos)
          : gain.pos) * track.width
        height: parent.height
        radius: 2
        color: Color.accent
      }

      Rectangle {
        visible: gain.bipolar && gain.minValue <= 0 && gain.maxValue >= 0
        x: gain.zeroPos * track.width - 0.5
        width: 1
        height: 7
        y: -2
        color: Util.alpha(Color.foreground, 0.4)
      }
    }

    Rectangle {
      width: 9
      height: 9
      radius: 5
      color: Color.accent
      x: Math.max(0, Math.min(parent.width, gain.pos * parent.width)) - width / 2
      anchors.verticalCenter: parent.verticalCenter
    }

    // preventStealing: the page sits in a ScrollView, whose Flickable takes the
    // grab as soon as a drag wanders vertically, and the slider then stops
    // mid-gesture. The value follows the press, not the release.
    MouseArea {
      anchors.fill: parent
      preventStealing: true
      cursorShape: Qt.PointingHandCursor
      function setFrom(x) {
        gain.moved(gain.valueAt(x / width))
      }
      onPressed: function(mouse) { setFrom(mouse.x) }
      onPositionChanged: function(mouse) { if (pressed) setFrom(mouse.x) }
    }
  }

  // One band parameter on one line: name, slider, value. Three stacked
  // label-then-slider pairs made a ten-band profile over a thousand pixels
  // tall.
  component BandSlider: Item {
    id: bs
    property string label: ""
    property string valueText: ""
    property real value: 0
    property real minValue: 0
    property real maxValue: 1
    property bool logarithmic: false
    property bool bipolar: true
    signal moved(real v)

    height: Style.space(22)

    Text {
      id: bsLabel
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(66)
      text: bs.label
      color: Util.alpha(Color.foreground, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      id: bsValue
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(62)
      horizontalAlignment: Text.AlignRight
      text: bs.valueText
      color: Util.alpha(Color.foreground, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    GainSlider {
      anchors.left: bsLabel.right
      anchors.right: bsValue.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      value: bs.value
      minValue: bs.minValue
      maxValue: bs.maxValue
      logarithmic: bs.logarithmic
      bipolar: bs.bipolar
      onMoved: function(v) { bs.moved(v) }
    }
  }

  // Space between sections: a hairline with room on both sides. The bare
  // rule left sections one pixel and a spacing unit apart, which read as one
  // continuous list.
  component Gap: Item {
    width: parent ? parent.width : 0
    height: Style.space(18)

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: 1
      color: Util.alpha(Color.foreground, 0.1)
    }
  }

  // A section header that opens and closes: glyph, caps title, trailing value
  // and a chevron. With `mark` set it is a row that goes somewhere instead
  // (the chevron is replaced by the mark).
  component Fold: Item {
    id: fold
    property string glyph: ""
    property string title: ""
    property string value: ""
    property string mark: ""
    property bool open: false
    signal toggled()

    width: parent ? parent.width : 0
    height: Style.space(30)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: foldMouse.containsMouse ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : "transparent"
    }

    Text {
      id: foldGlyph
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(14)
      text: fold.glyph
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.left: foldGlyph.right
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: fold.title.toUpperCase()
      color: Util.alpha(Color.foreground, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.5
    }

    Text {
      id: foldMark
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(10)
      horizontalAlignment: Text.AlignRight
      text: fold.mark !== "" ? fold.mark : (fold.open ? "▾" : "▸")
      color: Util.alpha(Color.foreground, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.right: foldMark.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width * 0.5)
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: fold.value
      color: Util.alpha(Color.foreground, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: foldMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: fold.toggled()
    }
  }

  // A drop-down: one row showing the current choice; opening it lists the
  // others beneath, in the page, so it needs no second window and cannot be
  // clipped by the scroll area. `rows` is [{text, current}].
  component Pick: Column {
    id: pick
    property string glyph: ""
    property string text: ""
    property var rows: []
    property bool open: false
    signal toggled()
    signal chosen(int index)

    width: parent ? parent.width : 0
    spacing: Style.space(3)

    Rectangle {
      width: parent.width
      height: Style.space(32)
      radius: Style.cornerRadius
      color: pickMouse.containsMouse || pick.open
        ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : Util.alpha(Color.foreground, 0.04)
      border.width: 1
      border.color: pick.open ? Util.alpha(Color.accent, 0.5) : Util.alpha(Color.foreground, 0.2)

      Text {
        id: pickGlyph
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        text: pick.glyph
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.left: pickGlyph.right
        anchors.leftMargin: Style.space(8)
        anchors.right: pickChevron.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: pick.text !== "" ? pick.text : "None"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: pickChevron
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: pick.open ? "▴" : "▾"
        color: Util.alpha(Color.foreground, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        id: pickMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pick.toggled()
      }
    }

    Rectangle {
      visible: pick.open
      width: parent.width
      height: pickList.implicitHeight + Style.space(8)
      radius: Style.cornerRadius
      color: Util.alpha(Color.foreground, 0.04)
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.2)

      Column {
        id: pickList
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(4)

        Repeater {
          model: pick.rows

          delegate: Item {
            required property var modelData
            required property int index
            width: pickList.width
            height: Style.space(28)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: modelData.current
                ? Util.alpha(Color.accent, Style.selectedFillAlpha)
                : (rowMouse.containsMouse ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : "transparent")
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: rowCheck.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.text
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: modelData.current
              elide: Text.ElideRight
            }

            Text {
              id: rowCheck
              anchors.right: parent.right
              anchors.rightMargin: Style.space(9)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.current ? "✓" : ""
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: pick.chosen(index)
            }
          }
        }
      }
    }
  }

  component Level: Item {
    id: lvl
    property real value: 0
    signal moved(real pct)

    height: Style.space(18)

    Rectangle {
      id: lvlTrack
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: 3
      radius: 2
      color: Util.alpha(Color.foreground, 0.18)

      Rectangle {
        width: lvlTrack.width * Math.max(0, Math.min(1, lvl.value))
        height: parent.height
        radius: 2
        color: Color.accent
      }
    }

    Rectangle {
      width: 9
      height: 9
      radius: 5
      color: Color.accent
      x: Math.max(0, Math.min(lvlTrack.width, lvlTrack.width * Math.max(0, Math.min(1, lvl.value)))) - width / 2
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      anchors.fill: parent
      preventStealing: true
      cursorShape: Qt.PointingHandCursor
      function setFrom(x) { lvl.moved(Math.max(0, Math.min(100, Math.round(x / width * 100)))) }
      onPressed: function(mouse) { setFrom(mouse.x) }
      onPositionChanged: function(mouse) { if (pressed) setFrom(mouse.x) }
    }
  }

  // A single-line text box with the page's side margin built in.
  component Field: Item {
    id: field
    property alias text: input.text
    property string placeholder: ""
    signal accepted()

    width: parent ? parent.width : 0
    height: Style.space(26)

    Rectangle {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      radius: Style.cornerRadius
      color: Util.alpha(Color.foreground, 0.05)
      border.width: 1
      border.color: input.activeFocus
        ? Util.alpha(Color.accent, 0.7)
        : Util.alpha(Color.foreground, 0.22)
    }

    Text {
      anchors.fill: parent
      anchors.leftMargin: Style.space(15)
      anchors.rightMargin: Style.space(15)
      verticalAlignment: Text.AlignVCenter
      visible: input.text === ""
      text: field.placeholder
      color: Util.alpha(Color.foreground, 0.35)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: Style.space(15)
      anchors.rightMargin: Style.space(15)
      verticalAlignment: TextInput.AlignVCenter
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      clip: true
      selectByMouse: true
      onAccepted: field.accepted()
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool selected: false
    signal picked()

    width: chipText.implicitWidth + Style.space(16)
    height: Style.space(22)
    radius: Style.cornerRadius
    property bool hovered: false
    color: chip.selected
      ? Util.alpha(Color.accent, Style.selectedFillAlpha)
      : chip.hovered ? Util.alpha(Color.accent, Style.hoverFillAlpha) : "transparent"
    border.width: 1
    border.color: chip.selected
      ? Util.alpha(Color.accent, 0.55)
      : Util.alpha(Color.foreground, Style.normalBorderAlpha)

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: chip.hovered = true
      onExited: chip.hovered = false
      onClicked: chip.picked()
    }
  }

  Column {
    id: col
    width: parent.width
    spacing: Style.space(2)

    // ---- main view ----
    Column {
      id: mainView
      width: parent.width
      spacing: Style.space(2)
      visible: page.view === "main"

      // ---- output level ----
      // The percentage lives on the slider row; repeating it here would say the
      // same thing twice on adjacent lines.
      Head {
        glyph: "󰕾"
        title: "Output"
        value: ""
        gap: Style.space(4)
      }

      Pick {
        glyph: "󰓃"
        text: page.state ? page.state.deviceName : ""
        open: page.outPickOpen
        rows: page.sinkRows
        onToggled: page.outPickOpen = !page.outPickOpen
        onChosen: function(i) { page.outPickOpen = false; if (page.state) page.state.setDefault(page.state.sinks[i]) }
      }

      Item {
        width: parent.width
        height: Style.space(24)

        Text {
          id: volGlyph
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(14)
          text: page.state && page.state.muted ? "󰝟" : "󰕾"
          color: Util.alpha(Color.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            cursorShape: Qt.PointingHandCursor
            onClicked: if (page.state) page.state.toggle()
          }
        }

        Text {
          id: volValue
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(34)
          horizontalAlignment: Text.AlignRight
          text: page.state ? page.state.volume + "%" : ""
          color: Util.alpha(Color.foreground, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Item {
          anchors.left: volGlyph.right
          anchors.leftMargin: Style.space(8)
          anchors.right: volValue.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(18)

          Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 3
            radius: 2
            color: Util.alpha(Color.foreground, 0.18)

            Rectangle {
              width: track.width * page.level
              height: parent.height
              radius: 2
              color: Color.accent
            }
          }

          Rectangle {
            width: 9
            height: 9
            radius: 5
            color: Color.accent
            x: Math.max(0, Math.min(track.width, track.width * page.level)) - width / 2
            anchors.verticalCenter: parent.verticalCenter
          }

          MouseArea {
            anchors.fill: parent
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            function setFrom(x) {
              if (page.state) page.state.setVolume(Math.max(0, Math.min(100, Math.round(x / width * 100))))
            }
            onPressed: function(mouse) { setFrom(mouse.x) }
            onPositionChanged: function(mouse) { if (pressed) setFrom(mouse.x) }
          }
        }
      }

      Gap { }

      // ---- input ----
      Head {
        glyph: "󰍬"
        title: "Input"
        value: ""
        gap: Style.space(4)
      }

      Pick {
        glyph: "󰍬"
        text: page.state ? page.state.sourceName : ""
        open: page.inPickOpen
        rows: page.sourceRows
        onToggled: page.inPickOpen = !page.inPickOpen
        onChosen: function(i) { page.inPickOpen = false; if (page.state) page.state.setDefaultSource(page.state.sources[i]) }
      }

      Item {
        width: parent.width
        height: Style.space(24)

        Text {
          id: inGlyph
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(14)
          text: page.state && page.state.inputMuted ? "󰍭" : "󰍬"
          color: Util.alpha(Color.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (page.state) page.state.toggleInputMute()
          }
        }

        Text {
          id: inValue
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(34)
          horizontalAlignment: Text.AlignRight
          text: page.state ? page.state.inputVolume + "%" : ""
          color: Util.alpha(Color.foreground, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Level {
          anchors.left: inGlyph.right
          anchors.leftMargin: Style.space(8)
          anchors.right: inValue.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          value: page.state ? page.state.inputVolume / 100 : 0
          onMoved: function(pct) { if (page.state) page.state.setInputVolume(pct) }
        }
      }

      // The input's own level, not its volume: this is what the microphone is
      // actually picking up. Stock audio panel draws the same line under its
      // input slider, and it is the only way to see a dead or clipping source.
      Item {
        width: parent.width
        height: Math.max(4, Style.space(4))

        // Aligned to the slider above, not to the row: the glyph column and the
        // percentage column are outside the track, so the meter matches them.
        Rectangle {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(30)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(42)
          height: parent.height
          color: Util.alpha(Color.foreground, 0.18)
          opacity: page.state && page.state.inputMuted ? 0.35 : 1.0

          Rectangle {
            height: parent.height
            width: parent.width * Math.max(0, Math.min(1, page.state ? page.state.inputPeak : 0))
            color: Color.accent

            Behavior on width {
              NumberAnimation { duration: 70 }
            }
          }
        }
      }


      Gap { }

      // ---- per-app streams ----
      Fold {
        glyph: "󰓃"
        title: "Apps"
        value: page.state ? String(page.state.streams.length) : "0"
        open: page.appsOpen
        onToggled: page.appsOpen = !page.appsOpen
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: page.appsOpen


        Text {
          visible: page.state && page.state.streams.length === 0
          width: parent.width
          height: Style.space(22)
          verticalAlignment: Text.AlignVCenter
          leftPadding: Style.space(8)
          text: "Nothing playing"
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: page.state ? page.state.streams : []

          delegate: Column {
            required property var modelData
            width: col.width
            spacing: 1

            Item {
              width: parent.width
              height: Style.space(22)

              Text {
                id: streamGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(14)
                text: page.state && page.state.isStreamMuted(modelData) ? "󰝟" : "󰕾"
                color: Util.alpha(Color.foreground, 0.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (page.state) page.state.toggleStreamMute(modelData)
                }
              }

              Text {
                id: streamValue
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
                horizontalAlignment: Text.AlignRight
                text: page.state ? page.state.streamVolume(modelData) + "%" : ""
                color: Util.alpha(Color.foreground, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.left: streamGlyph.right
                anchors.leftMargin: Style.space(8)
                anchors.right: streamValue.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: page.state ? page.state.streamLabel(modelData) : ""
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
            }

            Level {
              width: parent.width
              value: page.state ? page.state.streamVolume(modelData) / 100 : 0
              onMoved: function(pct) { if (page.state) page.state.setStreamVolume(modelData, pct) }
            }
          }
        }

      }

      Gap { }

      // ---- sample rate and Bluetooth codec ----
      Fold {
        glyph: "󰒓"
        title: "Rate & codec"
        value: page.state && page.state.reportLoaded
          ? (page.state.isBluetooth ? page.state.codecLabel : page.state.fmtHz(page.state.inUseRate))
          : ""
        open: page.advOpen
        onToggled: {
          page.advOpen = !page.advOpen
          if (page.advOpen && page.state) page.state.refreshStatus()
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: page.advOpen

        // The codec and clock come from the audio-capability helper. Without it,
        // say so once rather than drawing controls that cannot act.
        Text {
          visible: page.state && !page.state.reportLoaded
          width: parent.width
          height: Style.space(24)
          verticalAlignment: Text.AlignVCenter
          leftPadding: Style.space(8)
          text: "Install audio-capability for sample rate and codec controls"
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Caps {
          visible: page.state && page.state.reportLoaded
          leftPadding: Style.space(8)
          text: "SAMPLE RATE"
        }

        // `clock.force-rate` is the lever that acts now: 0 is Auto. A rate the
        // device offers but the clock may not reach is listed too, marked, and
        // choosing it registers it first.
        Pick {
          visible: page.state && page.state.reportLoaded
          glyph: "󰒓"
          text: page.state ? page.state.rateLabel : ""
          open: page.ratePickOpen
          rows: page.rateRows
          onToggled: page.ratePickOpen = !page.ratePickOpen
          onChosen: function(i) {
            page.ratePickOpen = false
            var r = page.rateRows[i]
            if (!page.state) return
            if (r.rate === 0) page.state.setRate("auto")
            else if (r.registered) page.state.setRate(r.rate)
            else page.state.registerAndPin(r.rate)
          }
        }

        Text {
          visible: page.state && page.state.reportLoaded && page.state.hardwareRates.length === 0
          width: parent.width
          wrapMode: Text.WordWrap
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          text: "This device does not list its rates. The ones below are what PipeWire may switch between; any the device cannot take is refused."
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // ---- registry: what PipeWire has been told it may use ----
        Caps {
          visible: page.state && page.state.reportLoaded
          topPadding: Style.space(6)
          leftPadding: Style.space(8)
          text: "REGISTERED RATES"
        }

        Text {
          visible: page.state && page.state.reportLoaded
          width: parent.width
          wrapMode: Text.WordWrap
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          text: page.state && page.state.liveAllowed.length > 0
            ? page.state.liveAllowed.map(function(r) { return Math.round(r / 100) / 10 }).join(", ") + " kHz"
            : "None; PipeWire stays at its default rate"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: page.state && page.state.reportLoaded
          width: parent.width
          wrapMode: Text.WordWrap
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          text: {
            if (!page.state) return ""
            if (page.state.capBusy) return "Working…"
            if (page.state.unregisteredRates.length > 0)
              return page.state.unregisteredRates.length + " rates this device offers are not registered"
            if (page.state.needsLive)
              return "Written, not live yet. Make live restarts WirePlumber and audio pauses for a moment."
            if (page.state.filesOurs) return "Registered by this panel"
            return "Nothing registered by this panel"
          }
          color: Util.alpha(Color.foreground, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Flow {
          visible: page.state && page.state.reportLoaded
          width: parent.width - Style.space(16)
          x: Style.space(8)
          spacing: Style.space(6)

          Chip {
            label: "Discover"
            onPicked: if (page.state) { page.state.refreshReport(); page.state.refreshStatus() }
          }

          Chip {
            visible: page.state && (page.state.unregisteredRates.length > 0 || !page.state.filesOurs)
            label: "Register"
            onPicked: if (page.state) page.state.registerRates()
          }

          Chip {
            visible: page.state && page.state.needsLive
            label: "Make live"
            onPicked: if (page.state) page.state.makeLive()
          }

          Chip {
            visible: page.state && page.state.filesOurs
            label: page.removeArmed ? "Confirm remove" : "Remove"
            onPicked: {
              if (!page.state) return
              if (page.removeArmed) {
                page.removeArmed = false
                page.state.removeRegistration()
              } else {
                page.removeArmed = true
                removeDisarm.restart()
              }
            }
          }
        }

        Text {
          visible: page.state && page.state.capMessage !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          text: page.state ? page.state.capMessage : ""
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // ---- Bluetooth codec: switch now, and prefer at the next connect ----
        Caps {
          visible: page.state && page.state.isBluetooth
          topPadding: Style.space(6)
          leftPadding: Style.space(8)
          text: "CODEC, SWITCH NOW"
        }

        Pick {
          visible: page.state ? page.state.isBluetooth : false
          glyph: "󰂯"
          text: page.state ? page.state.codecLabel : ""
          open: page.codecPickOpen
          rows: page.codecRows
          onToggled: page.codecPickOpen = !page.codecPickOpen
          onChosen: function(i) {
            page.codecPickOpen = false
            if (page.state) page.state.setCodec(page.codecRows[i].value)
          }
        }

        Caps {
          visible: page.state && page.state.isBluetooth
          topPadding: Style.space(6)
          leftPadding: Style.space(8)
          text: "PREFER AT CONNECT"
        }

        Pick {
          visible: page.state ? page.state.isBluetooth : false
          glyph: "󰂯"
          text: page.state && (page.state.bt.preferred || []).length > 0
            ? String(page.state.bt.preferred[0]).toUpperCase() : "No preference"
          open: page.prefPickOpen
          rows: page.prefRows
          onToggled: page.prefPickOpen = !page.prefPickOpen
          onChosen: function(i) {
            page.prefPickOpen = false
            if (!page.state) return
            var v = page.prefRows[i].value
            page.state.setCodecPref(v === "" ? "none" : "codec=" + v)
          }
        }

        Caps {
          visible: page.state && page.state.isBluetooth
          topPadding: Style.space(6)
          leftPadding: Style.space(8)
          text: "LDAC QUALITY"
        }

        Pick {
          visible: page.state ? page.state.isBluetooth : false
          glyph: "󰂯"
          text: page.state && page.state.qualityLabel !== "" ? page.state.qualityLabel : "Next connect"
          open: page.qualPickOpen
          rows: page.qualRows
          onToggled: page.qualPickOpen = !page.qualPickOpen
          onChosen: function(i) {
            page.qualPickOpen = false
            if (page.state) page.state.setCodecPref("quality=" + page.qualRows[i].value)
          }
        }

        Caps {
          visible: page.state && page.state.isBluetooth
          topPadding: Style.space(6)
          leftPadding: Style.space(8)
          text: "AAC BITRATE MODE"
        }

        Pick {
          visible: page.state ? page.state.isBluetooth : false
          glyph: "󰂯"
          text: page.state && page.state.bitrateLabel !== "" ? page.state.bitrateLabel : "Next connect"
          open: page.bitPickOpen
          rows: page.bitRows
          onToggled: page.bitPickOpen = !page.bitPickOpen
          onChosen: function(i) {
            page.bitPickOpen = false
            if (page.state) page.state.setCodecPref("bitrate=" + page.bitRows[i].value)
          }
        }

        Text {
          visible: page.state && page.state.reportLoaded && !page.state.isBluetooth
          width: parent.width
          wrapMode: Text.WordWrap
          topPadding: Style.space(3)
          bottomPadding: Style.space(3)
          leftPadding: Style.space(8)
          text: "Codec and bitrate controls appear with a Bluetooth output"
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: page.state ? page.state.warnings : []

          delegate: Text {
            required property var modelData
            width: col.width
            text: String(modelData)
            wrapMode: Text.Wrap
            leftPadding: Style.space(8)
            rightPadding: Style.space(8)
            topPadding: Style.space(3)
            color: Util.alpha(Color.foreground, 0.5)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

      }

      Gap { }

      Fold {
        glyph: "󰒓"
        title: "Equalizer"
        mark: "›"
        value: page.state && page.state.eqOn ? (page.state.eqProfile || "on") : "off"
        onToggled: page.view = "eq"
      }
    }

    // ---- headphone EQ ----
    // ---- equalizer view ----
    Column {
      id: eqView
      width: parent.width
      spacing: Style.space(2)
      visible: page.view === "eq"

      Item {
        width: parent.width
        height: Style.space(32)

        // Breadcrumb: "Audio" goes back one level, "Equalizer" is where you are.
        Text {
          id: eqBack
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Audio"
          color: backMouse.containsMouse ? Color.accent : Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.title

          MouseArea {
            id: backMouse
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.view = "main"
          }
        }

        Text {
          id: eqCrumb
          anchors.left: eqBack.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: "›"
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        Text {
          anchors.left: eqCrumb.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: "Equalizer"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Switch {
          id: eqMaster
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          checked: page.state ? page.state.eqOn : false
          onToggled: {
            if (!page.state) return
            if (!page.state.eqOn && page.eqDirty) page.applyEqChanges()
            else page.state.eqToggle()
          }
        }

        Chip {
          visible: page.eqDirty
          anchors.right: eqMaster.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          label: "Apply"
          onPicked: page.applyEqChanges()
        }
      }

      Gap { }


      Text {
        visible: page.state && !page.state.eqLoaded
        width: parent.width
        height: Style.space(24)
        verticalAlignment: Text.AlignVCenter
        leftPadding: Style.space(8)
        text: "Install audio-eq to enable headphone EQ"
        color: Util.alpha(Color.foreground, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }


      Pick {
        glyph: "󰒓"
        text: page.state && page.state.eqProfile !== "" ? page.state.eqProfile : "Choose a profile"
        open: page.eqProfilesOpen
        rows: page.profileRows
        onToggled: page.eqProfilesOpen = !page.eqProfilesOpen
        onChosen: function(i) {
          page.eqProfilesOpen = false
          if (page.state) page.state.eqApply(page.state.eqProfiles[i].name, null, [])
        }
      }


      // ---- online profiles ----
      Fold {
        glyph: "󰖟"
        title: "Find online"
        value: page.state && page.state.eqSources.length > 0
          ? page.state.eqSources.filter(function(x) { return x.enabled }).length + " sources" : ""
        open: page.eqSearchOpen
        onToggled: {
          page.eqSearchOpen = !page.eqSearchOpen
          if (page.eqSearchOpen && page.state) page.state.eqLoadSources()
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(4)
        visible: page.eqSearchOpen

        Field {
          placeholder: "Type a headphone model"
          onTextChanged: page.eqSearchText = text
          onAccepted: {
            searchDebounce.stop()
            if (page.isAddress(String(page.eqSearchText).trim())) page.importAddress()
            else page.runSearch()
          }
        }

        Text {
          width: parent.width
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          wrapMode: Text.WordWrap
          visible: text !== ""
          text: {
            var q = String(page.eqSearchText).trim()
            if (page.isAddress(q)) return "Press Enter to import this address"
            if (page.state && page.state.eqSearching) return "Searching…"
            if (q === "") return "Searches as you type, grouped by who measured it"
            if (page.state && page.state.eqSearchResults.length === 0 && !searchDebounce.running)
              return "No profiles found"
            if (page.state && page.state.eqSearchResults.length > 0)
              return page.state.eqSearchResults.length + " profiles from " + page.searchGroups.length + " providers"
            return ""
          }
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          leftPadding: Style.space(10)
          rightPadding: Style.space(10)
          wrapMode: Text.WordWrap
          visible: page.state && page.state.eqSearchFailed.length > 0
          text: page.state ? "Could not read: " + page.state.eqSearchFailed.join(", ") : ""
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Repeater {
          model: page.searchGroups

          delegate: Column {
            id: group
            required property var modelData
            readonly property bool expanded: page.expandedGroups[modelData.provider] === true
              || page.searchGroups.length === 1
            readonly property var shown: expanded ? modelData.items : modelData.items.slice(0, 3)
            width: col.width
            spacing: 0

            Item {
              width: parent.width
              height: Style.space(24)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: groupMouse.containsMouse ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : "transparent"
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: group.modelData.provider.toUpperCase()
                color: Util.alpha(Color.foreground, 0.6)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.2
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: group.modelData.items.length + (group.modelData.items.length > 3 ? (group.expanded ? "  ▾" : "  ▸") : "")
                color: Util.alpha(Color.foreground, 0.45)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: groupMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.toggleGroup(group.modelData.provider)
              }
            }

            Repeater {
              model: group.shown

              delegate: Item {
                id: hit
                required property var modelData
                readonly property string fullName: String(modelData.name) + " (" + String(modelData.provider) + ")"
                width: group.width
                height: Style.space(26)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: hitMouse.containsMouse ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : "transparent"
                }

                Text {
                  id: hitCat
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(implicitWidth, parent.width * 0.38)
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideRight
                  text: String(hit.modelData.category)
                  color: Util.alpha(Color.foreground, 0.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.right: hitCat.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: String(hit.modelData.name)
                  color: page.state && page.state.eqProfile === hit.fullName ? Color.accent : Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: hitMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (page.state) page.state.eqApplyResult(hit.modelData)
                }
              }
            }

            Item {
              visible: !group.expanded && group.modelData.items.length > 3
              width: parent.width
              height: Style.space(22)

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                text: "Show " + (group.modelData.items.length - 3) + " more"
                color: moreMouse.containsMouse ? Color.accent : Util.alpha(Color.foreground, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: moreMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.toggleGroup(group.modelData.provider)
              }
            }
          }
        }

        Text {
          visible: page.state && page.state.eqError !== ""
          width: parent.width
          wrapMode: Text.Wrap
          leftPadding: Style.space(8)
          rightPadding: Style.space(8)
          text: page.state ? page.state.eqError : ""
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Fold {
          glyph: "󰒓"
          title: "Manage sources"
          mark: "›"
          onToggled: page.view = "sources"
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(3)
        visible: page.state && page.state.eqLoaded && bandModel.count > 0

        BandSlider {
          width: parent.width
          label: "Preamp"
          valueText: page.fmtGain(page.eqPreampLocal)
          value: page.eqPreampLocal
          minValue: -15
          maxValue: 5
          onMoved: function(v) {
            page.eqPreampLocal = Math.round(v * 10) / 10
            page.eqDirty = true
          }
        }

        Canvas {
          id: eqCurve
          width: parent.width
          height: Style.space(96)
          property real preamp: page.eqPreampLocal
          property int revision: page.bandRevision
          onRevisionChanged: requestPaint()
          onPreampChanged: requestPaint()

          // The real response of the biquad PipeWire runs (RBJ cookbook, the
          // form its bq_* nodes use), at 48 kHz. Q and shelf slope therefore
          // move the curve the way they move the sound; a hand-drawn bump did
          // not.
          function bandResponse(f, band) {
            var fs = 48000
            var f0 = Math.max(1, Math.min(fs / 2 - 1, Number(band.freq) || 1000))
            var q = Math.max(0.05, Number(band.qValue) || 0.707)
            var g = Number(band.gainDb) || 0
            var A = Math.pow(10, g / 40)
            var w0 = 2 * Math.PI * f0 / fs
            var cs = Math.cos(w0), sn = Math.sin(w0)
            var alpha = sn / (2 * q)
            var b0, b1, b2, a0, a1, a2
            if (band.bandType === "LS" || band.bandType === "HS") {
              var beta = 2 * Math.sqrt(A) * alpha
              if (band.bandType === "LS") {
                b0 = A * ((A + 1) - (A - 1) * cs + beta)
                b1 = 2 * A * ((A - 1) - (A + 1) * cs)
                b2 = A * ((A + 1) - (A - 1) * cs - beta)
                a0 = (A + 1) + (A - 1) * cs + beta
                a1 = -2 * ((A - 1) + (A + 1) * cs)
                a2 = (A + 1) + (A - 1) * cs - beta
              } else {
                b0 = A * ((A + 1) + (A - 1) * cs + beta)
                b1 = -2 * A * ((A - 1) + (A + 1) * cs)
                b2 = A * ((A + 1) + (A - 1) * cs - beta)
                a0 = (A + 1) - (A - 1) * cs + beta
                a1 = 2 * ((A - 1) - (A + 1) * cs)
                a2 = (A + 1) - (A - 1) * cs - beta
              }
            } else {
              b0 = 1 + alpha * A
              b1 = -2 * cs
              b2 = 1 - alpha * A
              a0 = 1 + alpha / A
              a1 = -2 * cs
              a2 = 1 - alpha / A
            }
            var w = 2 * Math.PI * Math.min(f, fs / 2 - 1) / fs
            var c1 = Math.cos(w), s1 = Math.sin(w), c2 = Math.cos(2 * w), s2 = Math.sin(2 * w)
            var nr = b0 + b1 * c1 + b2 * c2, ni = -(b1 * s1 + b2 * s2)
            var dr = a0 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2)
            var mag2 = (nr * nr + ni * ni) / Math.max(1e-12, dr * dr + di * di)
            return 10 * Math.log(Math.max(1e-12, mag2)) / Math.LN10
          }

          onPaint: {
            var ctx = getContext("2d")
            var w = width, h = height, mid = h / 2, range = 18
            ctx.clearRect(0, 0, w, h)
            ctx.lineWidth = 1
            ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g,
              Color.foreground.b, 0.12)
            for (var d = -12; d <= 12; d += 6) {
              var y = mid - d / range * mid
              ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke()
            }
            for (var fq = 20; fq <= 20000; fq *= 10) {
              var x = Math.log(fq / 20) / Math.log(1000) * w
              ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke()
            }

            var pts = []
            for (var x2 = 0; x2 <= w; x2 += 2) {
              var f = 20 * Math.pow(1000, x2 / w)
              var db = preamp
              for (var i = 0; i < bandModel.count; i++)
                db += bandResponse(f, bandModel.get(i))
              var yy = mid - Math.max(-range, Math.min(range, db)) / range * mid
              pts.push([x2, yy])
            }

            ctx.beginPath()
            ctx.moveTo(0, mid)
            for (var p = 0; p < pts.length; p++) ctx.lineTo(pts[p][0], pts[p][1])
            ctx.lineTo(w, mid)
            ctx.closePath()
            ctx.fillStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
            ctx.fill()

            ctx.beginPath()
            for (var q = 0; q < pts.length; q++) {
              if (q === 0) ctx.moveTo(pts[q][0], pts[q][1])
              else ctx.lineTo(pts[q][0], pts[q][1])
            }
            ctx.strokeStyle = Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.9)
            ctx.lineWidth = 1.5
            ctx.stroke()

            ctx.beginPath(); ctx.moveTo(0, mid); ctx.lineTo(w, mid)
            ctx.strokeStyle = Qt.rgba(Color.foreground.r, Color.foreground.g,
              Color.foreground.b, 0.25)
            ctx.lineWidth = 1
            ctx.stroke()

            // Axis labels: decades along the bottom, dB at the left.
            ctx.fillStyle = Qt.rgba(Color.foreground.r, Color.foreground.g,
              Color.foreground.b, 0.45)
            ctx.font = "9px sans-serif"
            var marks = [[20, "20"], [200, "200"], [2000, "2k"], [20000, "20k"]]
            for (var m = 0; m < marks.length; m++) {
              var mx = Math.log(marks[m][0] / 20) / Math.log(1000) * w
              ctx.textAlign = m === 0 ? "left" : (m === marks.length - 1 ? "right" : "center")
              ctx.fillText(marks[m][1], mx + (m === 0 ? 2 : (m === marks.length - 1 ? -2 : 0)), h - 2)
            }
            ctx.textAlign = "left"
            var dbs = [12, -12]
            for (var k = 0; k < dbs.length; k++)
              ctx.fillText((dbs[k] > 0 ? "+" : "") + dbs[k], 2, mid - dbs[k] / range * mid + (dbs[k] > 0 ? 10 : -3))
          }
        }

        // The axis labels sit on the canvas's last pixels; keep the first band's
        // chip off them.
        Item { width: parent.width; height: Style.space(4) }

        Repeater {
          model: bandModel

          delegate: Column {
            id: band
            // Collapsed to a one-line summary; the three sliders open on demand.
            property bool expanded: false
            width: col.width
            spacing: 1

            Item {
              width: parent.width
              height: Style.space(28)

              // First, so the chip and the remove button above it keep their own clicks.
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: band.expanded = !band.expanded
              }

              Chip {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                label: page.typeLabel(bandType) + "  ▾"
                onPicked: page.cycleBandType(index)
              }

              Rectangle {
                width: Style.space(18)
                height: width
                radius: Style.cornerRadius
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                color: removeBandMouse.containsMouse
                  ? Util.alpha(Color.urgent, 0.15) : "transparent"
                border.width: 1
                border.color: Util.alpha(Color.foreground, 0.3)

                Text {
                  anchors.centerIn: parent
                  text: "×"
                  color: Util.alpha(Color.foreground, 0.8)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: removeBandMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: page.removeBand(index)
                }
              }

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(116)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(34)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: page.fmtFreq(freq) + "   " + page.fmtGain(gainDb) + "   " + (band.expanded ? "▾" : "▸")
                color: Util.alpha(Color.foreground, 0.7)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              width: parent.width
              spacing: 1
              visible: band.expanded

              BandSlider {
                width: parent.width
                label: "Frequency"
                valueText: page.fmtFreq(freq)
                value: freq
                minValue: 20
                maxValue: 20000
                logarithmic: true
                bipolar: false
                onMoved: function(v) { page.setBandField(index, "freq", Math.round(v)) }
              }

              BandSlider {
                width: parent.width
                label: "Gain"
                valueText: page.fmtGain(gainDb)
                value: gainDb
                minValue: -15
                maxValue: 15
                onMoved: function(v) {
                  page.setBandField(index, "gainDb", Math.round(v * 10) / 10)
                }
              }

              BandSlider {
                width: parent.width
                label: "Q"
                valueText: page.fmtQ(qValue)
                value: qValue
                minValue: 0.1
                maxValue: 10
                // Useful Q lives between about 0.5 and 3; a linear track puts all
                // of it in the first fifth.
                logarithmic: true
                bipolar: false
                onMoved: function(v) {
                  page.setBandField(index, "qValue", Math.round(v * 100) / 100)
                }
              }

            }

            Rule { }
          }
        }

        Item {
          width: parent.width
          height: Style.space(26)

          Chip {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            label: "+ Add band"
            onPicked: page.addBand()
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: bandModel.count + " bands"
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

    // ---- sources view ----
    Column {
      id: sourcesView
      width: parent.width
      spacing: Style.space(2)
      visible: page.view === "sources"

      Item {
        width: parent.width
        height: Style.space(32)

        Text {
          id: srcBack
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Audio"
          color: srcBackMouse.containsMouse ? Color.accent : Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.title

          MouseArea {
            id: srcBackMouse
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.view = "main"
          }
        }

        Text {
          id: srcCrumb1
          anchors.left: srcBack.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: "›"
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        Text {
          id: srcEq
          anchors.left: srcCrumb1.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: "Equalizer"
          color: srcEqMouse.containsMouse ? Color.accent : Util.alpha(Color.foreground, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.title

          MouseArea {
            id: srcEqMouse
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.view = "eq"
          }
        }

        Text {
          id: srcCrumb2
          anchors.left: srcEq.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: "›"
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        Text {
          anchors.left: srcCrumb2.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: "Sources"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }
      }

      Text {
        width: parent.width
        leftPadding: Style.space(8)
        rightPadding: Style.space(8)
        wrapMode: Text.WordWrap
        text: "Where Find online looks. One source can hold many providers; the results are grouped by provider."
        color: Util.alpha(Color.foreground, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Gap { }

      Repeater {
        model: page.state ? page.state.eqSources : []

        delegate: Item {
          id: srcRow
          required property var modelData
          width: col.width
          height: Style.space(42)

          Switch {
            id: srcSwitch
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            checked: srcRow.modelData.enabled === true
            onToggled: if (page.state) page.state.eqSourceEnable(srcRow.modelData.id, !srcRow.modelData.enabled)
          }

          Item {
            id: srcTrail
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(40)
            height: Style.space(22)

            Text {
              visible: srcRow.modelData.builtin === true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "built in"
              color: Util.alpha(Color.foreground, 0.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: srcRow.modelData.builtin !== true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "×"
              color: srcDel.containsMouse ? Color.urgent : Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.title

              MouseArea {
                id: srcDel
                anchors.fill: parent
                anchors.margins: -Style.space(8)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (page.state) page.state.eqSourceRemove(srcRow.modelData.id)
              }
            }
          }

          Column {
            anchors.left: srcSwitch.right
            anchors.leftMargin: Style.space(10)
            anchors.right: srcTrail.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
              width: parent.width
              elide: Text.ElideRight
              text: String(srcRow.modelData.name)
              color: srcRow.modelData.enabled ? Color.foreground : Util.alpha(Color.foreground, 0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width
              elide: Text.ElideRight
              text: page.kindLabel(srcRow.modelData.kind) + " · " + srcRow.modelData.count
                + " profiles · " + page.ago(srcRow.modelData.updated)
              color: Util.alpha(Color.foreground, 0.45)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width
              elide: Text.ElideMiddle
              text: String(srcRow.modelData.target)
              color: Util.alpha(Color.foreground, 0.35)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(26)

        Chip {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          label: "Refresh all"
          onPicked: if (page.state) page.state.eqSourceRefresh("")
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          visible: page.state && page.state.eqSourcesBusy
          text: "Working…"
          color: Util.alpha(Color.foreground, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Gap { }

      Head {
        glyph: "󰐕"
        title: "Add a source"
      }

      Item {
        width: parent.width
        height: Style.space(28)

        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          Chip {
            label: "GitHub repo"
            selected: page.addKind === "github"
            onPicked: page.addKind = "github"
          }

          Chip {
            label: "List address"
            selected: page.addKind === "json"
            onPicked: page.addKind = "json"
          }

          Chip {
            label: "Folder"
            selected: page.addKind === "folder"
            onPicked: page.addKind = "folder"
          }
        }
      }

      Field {
        id: addTargetField
        placeholder: page.addKind === "github" ? "owner/repo or owner/repo@branch"
          : page.addKind === "json" ? "https://example.com/profiles.json"
          : "/path/to/folder of ParametricEQ.txt files"
        onAccepted: addButton.picked()
      }

      Field {
        id: addNameField
        placeholder: "Name (optional)"
        onAccepted: addButton.picked()
      }

      Text {
        width: parent.width
        leftPadding: Style.space(10)
        rightPadding: Style.space(10)
        wrapMode: Text.WordWrap
        text: page.addKind === "github"
          ? "A repository laid out like AutoEq: results/INDEX.md and one folder per provider."
          : page.addKind === "json"
            ? "An address returning a list of {name, url} entries, with optional provider and category."
            : "Every .txt file with Filter lines is a profile; sub-folders become categories."
        color: Util.alpha(Color.foreground, 0.4)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Item {
        width: parent.width
        height: Style.space(28)

        Chip {
          id: addButton
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          label: page.state && page.state.eqSourcesBusy && page.addPending ? "Checking…" : "Add source"
          onPicked: {
            if (!page.state || page.state.eqSourcesBusy) return
            if (String(addTargetField.text).trim() === "") return
            page.addPending = true
            page.state.eqSourceAdd(page.addKind, String(addTargetField.text).trim(), String(addNameField.text).trim())
          }
        }
      }

      Text {
        visible: page.state && page.state.eqSourcesError !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        leftPadding: Style.space(10)
        rightPadding: Style.space(10)
        text: page.state ? page.state.eqSourcesError : ""
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    }
  }
}

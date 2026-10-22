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
  property bool rateOpen: false
  property bool codecOpen: false

  // ------------------------------------------------------------- equalizer
  property bool eqProfilesOpen: false
  property bool eqSearchOpen: false
  property string eqSearchText: ""
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

  function eqLookup() {
    if (!state) return
    var q = String(eqSearchField.text || "").trim()
    if (q === "") return
    if (q.indexOf("http://") === 0 || q.indexOf("https://") === 0)
      state.eqApply(q, null, [])
    else
      state.eqSearch(q)
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

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      function setFrom(x) {
        gain.moved(gain.valueAt(x / width))
      }
      onClicked: function(mouse) { setFrom(mouse.x) }
      onPositionChanged: function(mouse) { if (pressed) setFrom(mouse.x) }
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
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { lvl.moved(Math.round(mouse.x / width * 100)) }
      onPositionChanged: function(mouse) { if (pressed) lvl.moved(Math.round(mouse.x / width * 100)) }
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    signal picked()

    width: chipText.implicitWidth + Style.space(16)
    height: Style.space(22)
    radius: Style.cornerRadius
    property bool hovered: false
    color: chip.hovered ? Util.alpha(Color.accent, Style.hoverFillAlpha) : "transparent"
    border.width: 1
    border.color: Util.alpha(Color.foreground, Style.normalBorderAlpha)

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

    // ---- hero ----
    Item {
      width: parent.width
      height: Style.space(44)

      Text {
        id: heroGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        text: page.state && page.state.muted ? "󰝟" : "󰕾"
        color: page.state && page.state.muted ? Util.alpha(Color.foreground, 0.5) : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        horizontalAlignment: Text.AlignHCenter
      }

      Column {
        anchors.left: heroGlyph.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
          width: parent.width
          text: page.state ? page.state.deviceName : ""
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Caps {
          width: parent.width
          text: page.state && page.state.muted ? "MUTED" : "DEFAULT OUTPUT"
        }
      }
    }

    Rule { }

    // ---- output level ----
    // The percentage lives on the slider row; repeating it here would say the
    // same thing twice on adjacent lines.
    Head {
      glyph: "󰕾"
      title: "Output"
      value: ""
      gap: Style.space(4)
    }

    Item {
      width: parent.width
      height: Style.space(24)

      Text {
        id: volGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        text: "󰕾"
        color: Util.alpha(Color.foreground, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
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
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) { if (page.state) page.state.setVolume(Math.round(mouse.x / width * 100)) }
          onPositionChanged: function(mouse) {
            if (pressed && page.state) page.state.setVolume(Math.round(mouse.x / width * 100))
          }
        }
      }
    }

    Rule { }

    // ---- devices ----
    Head {
      glyph: "󰓃"
      title: "Devices"
      value: page.state ? String(page.state.sinks.length) : "0"
      gap: Style.space(6)
    }

    Repeater {
      model: page.state ? page.state.sinks : []

      delegate: Item {
        required property var modelData
        width: col.width
        height: Style.space(30)

        readonly property bool current: page.state ? page.state.isDefault(modelData) : false

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: parent.current
            ? Util.alpha(Color.accent, Style.selectedFillAlpha)
            : (hover.containsMouse ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : "transparent")
          border.width: parent.current ? 1 : 0
          border.color: Util.alpha(Color.accent, 0.5)
        }

        Text {
          id: rowGlyph
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(14)
          text: "󰕾"
          color: parent.current ? Color.accent : Util.alpha(Color.foreground, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.left: rowGlyph.right
          anchors.leftMargin: Style.space(8)
          anchors.right: rowMark.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: page.state ? page.state.nodeLabel(modelData) : ""
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: parent.current
          elide: Text.ElideRight
        }

        Text {
          id: rowMark
          anchors.right: parent.right
          anchors.rightMargin: Style.space(9)
          anchors.verticalCenter: parent.verticalCenter
          text: parent.current ? "✓" : ""
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: hover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (page.state) page.state.setDefault(modelData)
        }
      }
    }

    Rule { }

    // ---- input ----
    Head {
      glyph: "󰍬"
      title: "Input"
      value: page.state ? page.state.sourceName : ""
      gap: Style.space(4)
    }

    Item {
      width: parent.width
      height: Style.space(24)

      Text {
        id: inGlyph
        anchors.left: parent.left
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
        anchors.leftMargin: Style.space(22)
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

    Repeater {
      model: page.state ? page.state.sources : []

      delegate: Item {
        required property var modelData
        width: col.width
        height: Style.space(28)

        readonly property bool current: page.state ? page.state.isDefaultSource(modelData) : false

        Rectangle {
          anchors.fill: parent
          color: parent.current ? Util.alpha(Color.accent, Style.selectedFillAlpha) : "transparent"
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(28)
          anchors.verticalCenter: parent.verticalCenter
          text: page.state ? page.state.nodeLabel(modelData) : ""
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: parent.current
          elide: Text.ElideRight
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(9)
          anchors.verticalCenter: parent.verticalCenter
          text: parent.current ? "✓" : ""
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: if (page.state) page.state.setDefaultSource(modelData)
        }
      }
    }

    Rule { }

    // ---- per-app streams ----
    Head {
      glyph: "󰓃"
      title: "Apps"
      value: page.state ? String(page.state.streams.length) : "0"
      gap: Style.space(4)
    }

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

    Rule { }

    // ---- sample rate and Bluetooth codec ----
    Head {
      glyph: "󰒓"
      title: "Rate & codec"
      visible: page.state && page.state.reportLoaded
      value: page.state
        ? (page.state.isBluetooth ? page.state.codecLabel : page.state.fmtHz(page.state.inUseRate))
        : ""
      gap: Style.space(4)
    }

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

    // Sample rate. `clock.force-rate` is the lever that acts now: 0 is Auto.
    Item {
      width: parent.width
      height: Style.space(30)
      visible: page.state && page.state.reportLoaded

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: page.rateOpen = !page.rateOpen
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "Sample rate"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: (page.state ? page.state.rateLabel : "") + "  ▾"
        color: Util.alpha(Color.foreground, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      width: parent.width
      spacing: 0
      visible: page.rateOpen && page.state && page.state.reportLoaded

      Repeater {
        model: [0].concat(page.state ? page.state.rateOptions : [])

        delegate: Item {
          required property var modelData
          readonly property bool current: page.state
            && (modelData === 0 ? page.state.forcedRate === 0
                                : page.state.forcedRate === modelData)

          width: col.width
          height: Style.space(26)

          Rectangle {
            anchors.fill: parent
            color: parent.current ? Util.alpha(Color.accent, Style.selectedFillAlpha) : "transparent"
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(20)
            anchors.verticalCenter: parent.verticalCenter
            text: modelData === 0
              ? "Auto — follow what is playing"
              : (page.state ? page.state.fmtHz(modelData) : "")
            color: parent.current ? Color.accent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (page.state) page.state.setRate(modelData === 0 ? "auto" : modelData)
              page.rateOpen = false
            }
          }
        }
      }
    }

    // The device advertises rates the clock is not allowed to reach. The
    // helper owns the two files that fix that; this offers them, labelled.
    Item {
      width: parent.width
      height: Style.space(30)
      visible: page.state && page.state.canApplyRates

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "Allow the hardware's rates"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width - applyChip.width - Style.space(20)
      }

      Chip {
        id: applyChip
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        label: "Apply"
        onPicked: if (page.state) page.state.applyFullRate()
      }
    }

    Item {
      width: parent.width
      height: Style.space(26)
      visible: page.state && page.state.canApplyRates

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "Then restart WirePlumber to pick the rules up"
        color: Util.alpha(Color.foreground, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Chip {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        label: "Restart"
        onPicked: if (page.state) page.state.activateFullRate()
      }
    }

    // Bluetooth codec. The row's press switches the open link; the pin writes
    // a preference for the next connect. They are different mechanisms.
    Item {
      width: parent.width
      height: Style.space(30)
      visible: page.state ? page.state.isBluetooth : false

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: page.codecOpen = !page.codecOpen
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "Codec"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: (page.state ? page.state.codecLabel : "") + "  ▾"
        color: Util.alpha(Color.foreground, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      width: parent.width
      spacing: 0
      visible: page.state && page.state.isBluetooth && page.codecOpen

      Repeater {
        model: page.state ? (page.state.bt.known || []) : []

        delegate: Item {
          required property var modelData
          readonly property bool current: page.state && page.state.bt.current === modelData
          readonly property bool prefer: page.state
            && (page.state.bt.preferred || []).indexOf(modelData) !== -1

          width: col.width
          height: Style.space(28)

          Rectangle {
            anchors.fill: parent
            color: parent.current ? Util.alpha(Color.accent, Style.selectedFillAlpha) : "transparent"
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(20)
            anchors.right: preferChip.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: String(modelData).toUpperCase()
              + (parent.current ? "  · in use" : "")
              + (parent.prefer ? "  · preferred" : "")
            color: parent.current ? Color.accent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Chip {
            id: preferChip
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            label: "prefer"
            onPicked: if (page.state) page.state.setCodecPref("codec=" + modelData)
          }

          MouseArea {
            anchors.fill: parent
            anchors.rightMargin: Style.space(60)
            cursorShape: Qt.PointingHandCursor
            onClicked: if (page.state) page.state.setCodec(modelData)
          }
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(30)
      visible: page.state ? page.state.isBluetooth : false

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "LDAC quality"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: page.state && page.state.qualityLabel !== ""
          ? page.state.qualityLabel : "next connect"
        color: Util.alpha(Color.foreground, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (!page.state) return
          var q = page.state.bt.ldacQuality
          var next = q === "auto" ? "hq" : q === "hq" ? "sq" : q === "sq" ? "mq" : "auto"
          page.state.setCodecPref("quality=" + next)
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(30)
      visible: page.state ? page.state.isBluetooth : false

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "AAC bitrate mode"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: page.state && page.state.bitrateLabel !== ""
          ? page.state.bitrateLabel : "next connect"
        color: Util.alpha(Color.foreground, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (!page.state) return
          var b = page.state.bt.aacBitrateMode
          var next = (b === null || b === undefined || b >= 5) ? 0 : (b + 1)
          page.state.setCodecPref("bitrate=" + next)
        }
      }
    }

    Text {
      visible: page.state && page.state.reportLoaded && !page.state.isBluetooth
      width: parent.width
      height: Style.space(22)
      verticalAlignment: Text.AlignVCenter
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

    Rule { }

    // ---- headphone EQ ----
    Head {
      glyph: "󰒓"
      title: "Equalizer"
      value: page.state && page.state.eqOn
        ? (page.state.eqProfile || "on") : "off"
      gap: Style.space(4)
    }

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

    Item {
      width: parent.width
      height: Style.space(30)

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "Headphone EQ"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Switch {
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
    }

    Item {
      width: parent.width
      height: Style.space(30)

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: page.eqProfilesOpen = !page.eqProfilesOpen
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "Local profile"
        color: Util.alpha(Color.foreground, 0.7)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: (page.state && page.state.eqProfile !== ""
          ? page.state.eqProfile : "Choose a profile") + "  ▾"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: Math.max(0, parent.width - Style.space(110))
        horizontalAlignment: Text.AlignRight
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(1)
      visible: page.eqProfilesOpen

      Repeater {
        model: page.state ? page.state.eqProfiles : []

        delegate: Item {
          required property var modelData
          readonly property bool current: page.state
            && page.state.eqProfile === String(modelData.name)
          width: col.width
          height: Style.space(28)

          Rectangle {
            anchors.fill: parent
            color: current ? Util.alpha(Color.accent, Style.selectedFillAlpha) : "transparent"
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(24)
            anchors.verticalCenter: parent.verticalCenter
            text: String(modelData.name)
            color: current ? Color.accent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(9)
            anchors.verticalCenter: parent.verticalCenter
            text: current ? "✓" : ""
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (!page.state) return
              page.state.eqApply(modelData.name, null, [])
              page.eqProfilesOpen = false
            }
          }
        }
      }
    }

    // ---- online profiles ----
    Item {
      width: parent.width
      height: Style.space(20)

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "ONLINE · AUTO EQ"
        color: Util.alpha(Color.foreground, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.5
      }

    }

    Text {
      width: parent.width
      height: Style.space(16)
      leftPadding: Style.space(8)
      verticalAlignment: Text.AlignVCenter
      text: "Crinacle · oratory1990 · Super Review"
      color: Util.alpha(Color.foreground, 0.38)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      width: parent.width
      height: Style.space(26)
      color: Util.alpha(Color.foreground, 0.05)
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.22)
      radius: Style.cornerRadius

      Text {
        anchors.fill: parent
        anchors.leftMargin: Style.space(7)
        anchors.verticalCenter: parent.verticalCenter
        visible: eqSearchField.text === ""
        text: "Search a headphone model or source"
        color: Util.alpha(Color.foreground, 0.35)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      TextInput {
        id: eqSearchField
        anchors.fill: parent
        anchors.leftMargin: Style.space(7)
        anchors.rightMargin: Style.space(7)
        verticalAlignment: TextInput.AlignVCenter
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        clip: true
        selectByMouse: true
        onAccepted: page.eqLookup()
      }
    }

    Item {
      width: parent.width
      height: Style.space(24)

      Chip {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        label: page.state && page.state.eqSearching ? "Searching…" : "Find online"
        onPicked: page.eqLookup()
      }
    }

    Text {
      visible: page.state && page.state.eqSearching
        && page.state.eqSearchResults.length === 0
      width: parent.width
      height: Style.space(20)
      leftPadding: Style.space(16)
      verticalAlignment: Text.AlignVCenter
      text: "Searching AutoEQ…"
      color: Util.alpha(Color.foreground, 0.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      visible: page.state && !page.state.eqSearching
        && page.state.eqSearchResults.length === 0
        && eqSearchField.text !== ""
      width: parent.width
      height: Style.space(20)
      leftPadding: Style.space(16)
      verticalAlignment: Text.AlignVCenter
      text: "No profiles found"
      color: Util.alpha(Color.foreground, 0.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: page.state ? page.state.eqSearchResults : []

      delegate: Item {
        required property var modelData
        width: col.width
        height: Style.space(32)

        Column {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1

          Text {
            width: parent.width
            text: String(modelData.name)
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: String(modelData.source) + " · " + String(modelData.category)
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!page.state) return
            page.state.eqApply(modelData.url, null, [])
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
      topPadding: Style.space(2)
      text: page.state ? page.state.eqError : ""
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Column {
      width: parent.width
      spacing: Style.space(3)
      visible: page.state && page.state.eqLoaded && bandModel.count > 0

      Item {
        width: parent.width
        height: Style.space(20)

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Preamp"
          color: Util.alpha(Color.foreground, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.2
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: page.fmtGain(page.eqPreampLocal)
          color: Util.alpha(Color.foreground, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      GainSlider {
        width: parent.width
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

        function bandResponse(f, band) {
          var ratio = f / Math.max(1, Number(band.freq) || 1000)
          var l = Math.log(ratio) / Math.LN2
          var g = Number(band.gainDb) || 0
          if (band.bandType === "LS") {
            var k = Math.pow(ratio, 4)
            return g / (1 + k)
          }
          if (band.bandType === "HS") {
            var k2 = Math.pow(ratio, 4)
            return g * k2 / (1 + k2)
          }
          var width = 0.55 / Math.max(0.3, Number(band.qValue) || 0.7) + 0.25
          return g * Math.exp(-0.5 * Math.pow(l / width, 2))
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
        }
      }

      Repeater {
        model: bandModel

        delegate: Column {
          width: col.width
          spacing: 1

          Item {
            width: parent.width
            height: Style.space(24)

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
          }

          Item {
            width: parent.width
            height: Style.space(16)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "Frequency"
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: page.fmtFreq(freq)
              color: Util.alpha(Color.foreground, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          GainSlider {
            width: parent.width
            value: freq
            minValue: 20
            maxValue: 20000
            logarithmic: true
            bipolar: false
            onMoved: function(v) { page.setBandField(index, "freq", Math.round(v)) }
          }

          Item {
            width: parent.width
            height: Style.space(16)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "Gain"
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: page.fmtGain(gainDb)
              color: Util.alpha(Color.foreground, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          GainSlider {
            width: parent.width
            value: gainDb
            minValue: -15
            maxValue: 15
            onMoved: function(v) {
              page.setBandField(index, "gainDb", Math.round(v * 10) / 10)
            }
          }

          Item {
            width: parent.width
            height: Style.space(16)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "Q"
              color: Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: page.fmtQ(qValue)
              color: Util.alpha(Color.foreground, 0.7)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          GainSlider {
            width: parent.width
            value: qValue
            minValue: 0.1
            maxValue: 10
            bipolar: false
            onMoved: function(v) {
              page.setBandField(index, "qValue", Math.round(v * 100) / 100)
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

      Item {
        width: parent.width
        height: Style.space(26)

        Chip {
          visible: page.eqDirty
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          label: "Apply changes"
          onPicked: page.applyEqChanges()
        }

        Chip {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          label: page.state && page.state.eqOn ? "Turn off" : "Turn on"
          onPicked: {
            if (!page.state) return
            if (!page.state.eqOn && page.eqDirty) page.applyEqChanges()
            else page.state.eqToggle()
          }
        }
      }
    }
  }
}

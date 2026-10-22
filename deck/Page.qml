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
        onToggled: page.advOpen = !page.advOpen
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
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
                  ? "Auto, follows what is playing"
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
        value: "AutoEQ"
        open: page.eqSearchOpen
        onToggled: page.eqSearchOpen = !page.eqSearchOpen
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: page.eqSearchOpen

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
            verticalAlignment: Text.AlignVCenter
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
    }
  }
}

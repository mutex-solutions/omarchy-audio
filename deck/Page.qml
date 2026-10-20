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

  // The input meter is a capture stream. Run it only while this page is on
  // screen: `host.open` is Deck's (or the standalone popup's) visibility, and a
  // page with no host is a page that is only built when it is about to be shown.
  readonly property bool pageVisible: host && host.open !== undefined ? !!host.open : true
  onStateChanged: if (state) state.meterActive = pageVisible
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
}

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
  }
}

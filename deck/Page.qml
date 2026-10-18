import QtQuick
import qs.Commons

// Audio page. Rendered by Deck and by this plugin's own popup, so everything
// comes from `state` and nothing is Deck-specific.
Item {
  id: page

  property var state: null
  property var host: null

  implicitHeight: col.implicitHeight

  readonly property real level: state ? Math.max(0, Math.min(1, state.volume / 100)) : 0

  Column {
    id: col
    width: parent.width
    spacing: Style.space(4)

    // ---- volume ----
    Item {
      width: parent.width
      height: Style.space(26)

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
        x: track.width * page.level - width / 2
        anchors.verticalCenter: parent.verticalCenter
      }

      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) { if (page.state) page.state.setVolume(Math.round(mouse.x / width * 100)) }
        onPositionChanged: function(mouse) {
          if (pressed && page.state) page.state.setVolume(Math.round(mouse.x / width * 100))
        }
      }
    }

    Text {
      text: page.state && page.state.muted ? "Muted" : (page.state ? page.state.volume + "%" : "")
      color: Util.alpha(Color.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    // ---- outputs ----
    Text {
      text: "OUTPUT"
      color: Util.alpha(Color.foreground, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.4
      topPadding: Style.space(7)
      bottomPadding: Style.space(3)
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
        }

        Text {
          id: dot
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: parent.current ? "●" : "○"
          color: parent.current ? Color.accent : Util.alpha(Color.foreground, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.left: dot.right
          anchors.leftMargin: Style.space(9)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(9)
          anchors.verticalCenter: parent.verticalCenter
          text: page.state ? page.state.nodeLabel(modelData) : ""
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: parent.current
          elide: Text.ElideRight
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

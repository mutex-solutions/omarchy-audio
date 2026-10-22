import QtQuick
import Quickshell
import qs.Commons

// Deck adapter. The five members Deck reads, forwarded to the shared State.
// The page is handed `state` by Deck (see Deck's docs/CONTRACT.md), so tile and
// page read the same object.
//
// tileFull is the larger presentation: the device, the volume and a live
// slider, so a 4x1 tile is more useful than a stretched 2x1. The default body
// still handles the half and compact sizes.
Item {
  id: s

  readonly property var state: stateLoader.item

  readonly property bool active: state ? state.active : false
  readonly property string label: state ? state.label : ""
  readonly property string detail: state ? state.detail : ""
  readonly property string icon: state ? state.icon : ""

  function toggle() {
    if (state) state.toggle()
  }

  function openPage() {
    Quickshell.execDetached(["omarchy-shell", "mutex-solutions.deck", "openSection", "audio"])
  }

  readonly property Component tileFull: fullTile

  Component {
    id: fullTile

    Item {
      id: full
      readonly property var st: s.state

      // The background is the page door; the mute button and the slider are
      // declared after it and keep their own clicks.
      MouseArea {
        id: pageArea
        anchors.fill: parent
        property bool held: false
        onPressed: {
          held = false
          pageHold.restart()
        }
        onReleased: {
          pageHold.stop()
          if (!held) s.openPage()
        }
        onCanceled: pageHold.stop()

        Timer {
          id: pageHold
          interval: 450
          onTriggered: {
            pageArea.held = true
            s.openPage()
          }
        }
      }

      Text {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        text: full.st ? full.st.icon : ""
        color: full.st && full.st.active ? Color.accent : Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }

      Column {
        anchors.left: glyph.right
        anchors.leftMargin: Style.space(11)
        anchors.right: percent.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Style.space(5)
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: s.label
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: full.st ? full.st.deviceName : ""
          color: Util.alpha(Color.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: percent
        anchors.right: mute.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Style.space(5)
        text: full.st ? full.st.volume + "%" : ""
        color: Util.alpha(Color.foreground, 0.8)
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Rectangle {
        id: mute
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Style.space(5)
        width: Style.space(22)
        height: Style.space(22)
        radius: Style.cornerRadius
        color: muteMouse.containsMouse
          ? Util.alpha(Color.accent, Style.hoverFillAlpha) : "transparent"
        border.width: 1
        border.color: Util.alpha(Color.foreground, 0.25)

        Text {
          anchors.centerIn: parent
          text: full.st && full.st.muted ? "󰝟" : "󰕾"
          color: full.st && full.st.muted
            ? Util.alpha(Color.foreground, 0.45) : Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: muteMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (full.st) full.st.toggle()
        }
      }

      Item {
        id: volumeTrack
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(14)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(9)
        height: Style.space(5)

        Rectangle {
          anchors.fill: parent
          radius: parent.height / 2
          color: Util.alpha(Color.foreground, 0.18)
        }

        Rectangle {
          width: parent.width * Math.max(0, Math.min(1,
            full.st ? full.st.volume / 100 : 0))
          height: parent.height
          radius: parent.height / 2
          color: Color.accent
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            if (full.st) full.st.setVolume(Math.round(mouse.x / width * 100))
          }
          onPositionChanged: function(mouse) {
            if (pressed && full.st)
              full.st.setVolume(Math.round(mouse.x / width * 100))
          }
        }
      }
    }
  }

  Loader {
    id: stateLoader
    source: "../State.qml"
  }
}

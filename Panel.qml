import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Standalone bar widget. Click opens the panel; the same page Deck renders is
// shown inside it, so both modes stay in sync by construction.
Panel {
  id: root

  moduleName: "mutex-solutions.audio"
  ipcTarget: "mutex-solutions.audio"

  readonly property var state: stateLoader.item

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: stateLoader
    source: "State.qml"
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.state ? root.state.icon : ""
    active: root.state ? root.state.active : false
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.close()
    }

    Column {
      id: content
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(10)

      // header: title and the master toggle
      Item {
        width: parent.width
        height: Style.space(24)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Audio"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Rectangle {
          id: masterSwitch
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(34)
          height: Style.space(18)
          radius: height / 2
          color: root.state && root.state.active
            ? Util.alpha(Color.accent, 0.85)
            : Util.alpha(Color.foreground, 0.2)

          Rectangle {
            width: Style.space(14)
            height: width
            radius: width / 2
            y: (parent.height - height) / 2
            x: root.state && root.state.active ? parent.width - width - Style.space(2) : Style.space(2)
            color: "#ffffff"
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.state) root.state.toggle()
          }
        }
      }

      Loader {
        id: pageLoader
        width: parent.width
        source: "deck/Page.qml"
        onLoaded: if (item) item.state = root.state
      }
    }
  }

  onStateChanged: if (pageLoader.item) pageLoader.item.state = root.state
}

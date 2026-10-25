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

  // The page runs a capture meter while it is shown. It is inside this popup
  // and is loaded once, so it asks the popup whether it is actually open.
  readonly property QtObject pageHost: QtObject {
    readonly property bool open: root.opened
    function close() { root.close() }
    function notify(text) { console.log("audio:", String(text)) }
  }

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
      onCloseRequested: {
        var it = pageLoader.item
        if (it && it.canGoBack === true) it.goBack()
        else root.close()
      }
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

        Rectangle {
          id: backButton
          visible: !!pageLoader.item && pageLoader.item.canGoBack === true
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(24)
          height: Style.space(24)
          radius: Style.cornerRadius
          color: backMouse.containsMouse ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : "transparent"
          border.width: 1
          border.color: Util.alpha(Color.foreground, Style.normalBorderAlpha)

          Text {
            anchors.centerIn: parent
            text: "←"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pageLoader.item.goBack()
          }
        }

        Text {
          id: headerGlyph
          anchors.left: backButton.visible ? backButton.right : parent.left
          anchors.leftMargin: backButton.visible ? Style.space(8) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: "󰕾"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        Text {
          anchors.left: headerGlyph.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: pageLoader.item && pageLoader.item.trail && pageLoader.item.trail.length > 0
            ? "Audio  ›  " + pageLoader.item.trail.join("  ›  ") : "Audio"
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

      Rectangle {
        width: parent.width
        height: 1
        color: Util.alpha(Color.foreground, 0.12)
      }

      Loader {
        id: pageLoader
        width: parent.width
        source: "deck/Page.qml"
        onLoaded: {
          if (!item) return
          item.host = root.pageHost
          item.state = root.state
        }
      }
    }
  }

  onStateChanged: if (pageLoader.item) pageLoader.item.state = root.state
}

import QtQuick

// Deck adapter. The five members Deck reads, forwarded to the shared State.
// The page is handed `state` by Deck (see Deck's docs/CONTRACT.md), so tile and
// page read the same object.
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

  Loader {
    id: stateLoader
    source: "../State.qml"
  }
}

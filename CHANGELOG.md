# Changelog

## 0.1.0

First release.

- Standalone Omarchy bar widget: volume, mute, and output selection.
- Deck section (`deck/Section.qml` + `deck/Page.qml`), sharing one state object
  with the standalone widget so both modes stay in sync.
- No helper binary: state comes from Quickshell's Pipewire service.

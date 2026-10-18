# Audio

Volume, mute and output selection for Omarchy. Works two ways: as a bar widget,
or as a section inside [Deck](https://github.com/mutex-solutions/omarchy-deck).

## Standalone

```bash
omarchy plugin add https://github.com/mutex-solutions/omarchy-audio --enable
```

Click the speaker icon to open the panel: a volume slider and the list of output
devices, with the current one marked.

## Inside Deck

```bash
omarchy plugin add https://github.com/mutex-solutions/omarchy-audio
```

Then add the section to Deck's registry:

```json
{ "id": "audio", "title": "Audio",
  "file": "/home/YOU/.config/omarchy/plugins/mutex-solutions.audio/deck/Section.qml",
  "page": "/home/YOU/.config/omarchy/plugins/mutex-solutions.audio/deck/Page.qml" }
```

`install-bundle.sh` in the Deck repo does this for every section at once.

Inside Deck the tile toggles mute on click and opens the page on hold. As a
standalone widget, click opens the page directly.

## How it is built

| File | Role |
| --- | --- |
| `State.qml` | volume, mute, sinks; one object shared by both modes |
| `deck/Section.qml` | the five members Deck reads, forwarded to `State` |
| `deck/Page.qml` | the panel content, bound to `state` |
| `Panel.qml` | the standalone bar widget and its popup |

No helper binary and no polling: everything binds to Quickshell's Pipewire
service, so a volume change from anywhere updates both modes immediately.

## Requirements

Omarchy 4.x with PipeWire.

## Licence

MIT. See [LICENSE](LICENSE).

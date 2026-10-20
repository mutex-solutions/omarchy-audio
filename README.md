# Audio

Volume, mute and output selection for Omarchy. Works two ways: as a bar widget,
or as a section inside [Deck](https://github.com/mutex-solutions/omarchy-deck).

## Standalone

```bash
omarchy plugin add https://github.com/mutex-solutions/omarchy-audio --enable
```

Click the speaker icon to open the panel: the output volume and device list,
the microphone's volume and live level, every playing app with its own volume,
and the sample rate or Bluetooth codec the device is using.

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
| `State.qml` | output, input, streams, and the codec/rate report; one object shared by both modes |
| `deck/Section.qml` | the five members Deck reads, forwarded to `State` |
| `deck/Page.qml` | the panel content, bound to `state` |
| `Panel.qml` | the standalone bar widget and its popup |

Output, input and per-app streams bind directly to Quickshell's Pipewire
service, so a volume change from anywhere updates both modes immediately.

The **Rate & codec** section reads the `audio-capability` helper's JSON report.
That helper is the join between what the hardware advertises and what PipeWire
is actually allowed to use, and it is the only way to show that gap honestly.
Without it the section hides itself and says so; the rest of the panel works.
The input meter is a real capture stream, so it runs only while the page is on
screen, not while the widget sits in the bar.

## Requirements

Omarchy 4.x with PipeWire.

## Licence

MIT. See [LICENSE](LICENSE).

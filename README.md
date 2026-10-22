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

## Headphone EQ

The audio page ends with an **Equalizer** section:

- an on/off switch and the current profile;
- a library of built-in presets (Flat, Bass Boost, Vocal, Treble) and any
  profile you import;
- **AutoEQ online** search by headphone model or by source (Crinacle,
  oratory1990, Super Review, ...), or a pasted `ParametricEQ.txt` URL. The
  source line in the panel names those sources; profiles are fetched from
  `raw.githubusercontent.com/jaakkopasanen/AutoEq` and cached;
- a response curve, a preamp and, per band, editable **type** (peak, low
  shelf, high shelf), **frequency**, **gain** and **Q**, plus add/remove band;
  **Apply changes** regenerates the graph;
- the live profiles are hosted as a PipeWire filter-chain sink (`deck_eq`) in a
  dedicated user service, the same shape Omarchy uses for its speaker tuning.
  Turning EQ on moves the default sink and any playing app streams through it;
  turning it off restores the hardware sink and the volume levels.

Profiles are AutoEQ `ParametricEQ.txt` files. The helper is
[`scripts/audio-eq`](scripts/audio-eq); the UI calls the copy installed with
the plugin. No root is needed. The filter-chain host config is Omarchy's own
`/usr/share/omarchy/default/audio/filter-chain-host.conf`.

With EQ on, the rate/codec report probes the **hardware** the filter feeds, so
Bluetooth codec and bitrate controls stay available instead of disappearing
behind the filter sink.

## Codec and bitrate

The **Rate & codec** section always shows the sample rate and the clock
policy. The Bluetooth rows (codec, LDAC quality, AAC bitrate mode) appear when
a Bluetooth output is selected; on a wired or internal output the section says
that a Bluetooth output is needed.

## How it is built

| File | Role |
| --- | --- |
| `State.qml` | output, input, streams, codec/rate and EQ state; one object shared by both modes |
| `scripts/audio-eq` | the PipeWire EQ host, profile parser, AutoEQ search and routing |
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

# Audio

Volume, mute and output selection for Omarchy. Works two ways: as a bar widget,
or as a section inside [Deck](https://github.com/mutex-solutions/omarchy-deck).

## Standalone

```bash
omarchy plugin add https://github.com/mutex-solutions/omarchy-audio --enable
```

Click the speaker icon to open the panel: the output and input each have a
device drop-down with their volume under it (the microphone also shows its live
level), then **Apps** (every playing app with its own volume) and **Rate &
codec** (the sample rate or Bluetooth codec in use) as sections that fold away,
and an **Equalizer** row that opens the equalizer as its own view.

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

The **Equalizer** row at the bottom of the audio page opens a view of its own
(breadcrumb `Audio > Equalizer`, with the on/off switch in its header):

- a profile drop-down;
- a library of built-in presets (Flat, Bass Boost, Vocal, Treble) and any
  profile you import;
- **Find online** (folded until opened): type a headphone model and the list
  updates once you have stopped typing for a second. Results are **grouped by
  provider** (crinacle, oratory1990, Rtings, Super Review and the rest of what
  AutoEq publishes), three per group until you open one. A pasted
  `ParametricEQ.txt` address imports on Enter.
- **Sources**: Find online reads from a list you manage on its own page
  (`Audio > Equalizer > Sources`). AutoEq is built in; you can switch any source
  off, and add a **GitHub repo** laid out like AutoEq (`owner/repo[@branch]`), a
  **list address** returning `[{name, url, provider?, category?}]`, or a
  **folder** of `ParametricEQ.txt` files. A source is checked when it is added
  and an unreadable one is refused. Indexes are cached for a week and
  `Refresh all` rebuilds them. The list lives in
  `~/.config/deck/eq/sources.json`;
- a response curve, a preamp and a one-line summary per band that opens to
  editable **type** (peak, low shelf, high shelf), **frequency**, **gain** and
  **Q**, plus add/remove band; **Apply** (in the header, shown when there are
  edits) regenerates the graph;
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

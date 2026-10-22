# Changelog

## 0.3.0

- **Parametric headphone EQ.** `scripts/audio-eq` hosts a PipeWire
  filter-chain in its own client (`deck_eq`), the same shape Omarchy uses for
  its speaker tuning, and routes the default sink through it. Profiles are
  AutoEQ `ParametricEQ.txt` files; the built-in library has Flat, Bass Boost,
  Vocal and Treble, and AutoEQ (Crinacle, oratory1990, Super Review, ...) can
  be searched by model or source or loaded by URL.
- The audio page has an **Equalizer** section: on/off, profile list, AutoEQ
  search, a response curve, a preamp and one gain slider per band. Applying a
  gain or preamp regenerates the graph; the live EQ sink is fed from the
  hardware output so the two are not attenuated twice.
- With EQ on, the rate and codec report probes the **hardware** the filter
  feeds, not the filter sink, so Bluetooth codec and bitrate controls stay.
- The codec/bitrate note now says when those controls require a Bluetooth
  output.

## 0.2.2

- A hold on the 4x1 Audio tile opens the audio page, matching the host gesture on non-custom tiles.

## 0.2.1

- A **4x1 tile** (`tileFull`): the device name, volume, a mute button and a
  live volume slider. Half and compact keep the default body, so a section
  that only wants the simple view is unchanged.

## 0.2.0

- **Input.** A microphone section with its own volume, mute and default-source
  choice, plus a live level meter under the slider. The meter is a real capture
  stream and only runs while the page is on screen (`host.open`).
- **Per-app streams.** Every playback stream is listed with its own volume and
  mute, so one app can be turned down without touching the rest.
- **Rate and codec.** A sample-rate picker driven by the device's advertised
  rates intersected with the clock's allowed rates, Bluetooth codec switching
  (with a `prefer` action for the next connect), LDAC quality and AAC bitrate
  preferences, and the helper's warnings. Hidden when `audio-capability` is not
  installed, with one line saying so.
- The rate and codec section is a viewer that can act once on purpose; it
  never applies a clock change on its own.

## 0.1.0

First release.

- Standalone Omarchy bar widget: volume, mute, and output selection.
- Deck section (`deck/Section.qml` + `deck/Page.qml`), sharing one state object
  with the standalone widget so both modes stay in sync.
- No helper binary: state comes from Quickshell's Pipewire service.

# Changelog

## 0.6.0

- **Find online searches as you type.** The query runs one second after you
  stop typing, a newer query replaces one still in flight, and a pasted address
  waits for Enter. Results are grouped by provider with a count, three rows
  each and a "Show N more" row.
- **Sources page** (`Audio > Equalizer > Sources`): switch sources on and off,
  add a GitHub repo in AutoEq layout, a JSON list address or a local folder,
  remove the ones you added, refresh. A source that cannot be read is refused
  at add time and reported in the results rather than failing the search.
  `audio-eq` gained `sources`, `source-add`, `source-remove`, `source-enable`
  and `source-refresh`.
- A profile picked from a search is saved as `Name (Provider)`, so the same
  headphone from two providers no longer overwrites itself.
- **Rate & codec uses drop-downs.** Sample rate lists what the device offers,
  and a rate PipeWire has not been told about is marked "not registered";
  choosing it registers it and then pins it. A **Registered rates** block shows
  what the clock may switch between and has **Discover**, **Register**,
  **Make live** (restarts WirePlumber) and **Remove** (asks twice). Bluetooth
  gets drop-downs for codec now, preferred codec at connect, LDAC quality and
  AAC bitrate mode.
- **Profiles can be created and deleted.** `New` saves what is on screen under
  a name (so it doubles as save-as); `Delete` asks twice and refuses while the
  profile is in use. The built-in presets are seeded once, so a deleted preset
  stays deleted. `audio-eq` gained `save` and `delete`.
- **Providers** (on the Sources page) lists every provider in the enabled
  sources with its count and a switch, so a provider can be hidden from search
  without removing its source.
- Find online waits 0.4 s after typing, and the explanatory text on the
  Equalizer, Sources and Rate & codec views is cut to labels.
- After Remove, the rate list falls back to the usual rates so there is still
  something to register.
- Fixed the INDEX parser cutting names that contain a bracket, such as
  "(footsteps preset)".

## 0.5.0

- **The page is rebuilt around what people do.** Output and input each get a
  **device drop-down** (the list opens in the page, so it cannot be clipped)
  with the volume beneath it; the speaker glyph on the output slider mutes. The
  hero that repeated the device name is gone. The main view now fits without
  scrolling.
- **Apps** and **Rate & codec** are collapsible sections (Rate & codec starts
  closed).
- **The equalizer is its own view**, opened from an **Equalizer** row at the
  bottom of the page, with an `Audio > Equalizer` breadcrumb and the on/off
  switch in its header. Inside it: a profile drop-down, a folded **Find online**
  section, the preamp, the curve, and one line per band that opens to its three
  sliders. A ten-band profile that took about 900 px now takes about 330 px
  collapsed. **Apply** sits in the header and appears only when there are edits.
- Sections are separated by a spaced rule instead of a bare hairline.
- The rate labels no longer use an em dash ("Auto, following 48 kHz").

## 0.4.1

- **Sliders keep the drag.** The output, input, per-app, preamp and band sliders
  now set `preventStealing`. The page sits in a ScrollView, and a drag that
  wandered vertically was taken over by scrolling, so the slider stopped
  mid-gesture. A press also sets the value immediately instead of waiting for
  the release.
- **Q is logarithmic**, like frequency. Linear 0.1 to 10 put every useful value
  in the first fifth of the track.
- **The response curve is the real response** of the biquad PipeWire runs (RBJ
  cookbook, 48 kHz), so Q and shelf slope move it the way they move the sound.
  It now has decade labels and +12 and -12 dB marks.
- **Bands take a third of the room.** Name, slider and value share one line, so
  a ten-band profile is about 900 px instead of 1,300. The preamp uses the same
  row.
- The helper clamps and validates what it writes into the PipeWire config
  (frequency 20 to 20000, gain -30 to 30, Q 0.05 to 20, preamp -30 to 10, at
  most 32 bands, known filter types only), so a bad imported profile fails with
  a message instead of "the EQ sink did not appear".
- The tile glyph sits in Deck's fixed icon cell and is no longer always accent
  coloured. The Rate and codec note wraps instead of running off the edge, and
  the search field's placeholder is vertically centred.

## 0.4.0

- **The parametric bands are fully editable**: type cycles peak / low shelf /
  high shelf, and frequency (20 Hz - 20 kHz, logarithmic), gain (-15..+15 dB)
  and Q (0.1..10) each have a slider. Bands can be added and removed. The
  helper accepts the result as `--bands-json`, so a custom band set does not
  have to be written back to an AutoEQ file.
- Band edits use a `ListModel` and `setProperty`, so dragging a frequency, gain
  or Q slider does not recreate the delegate under the pointer.
- The online profile source is explicit: an always-visible **ONLINE · AUTO EQ**
  section names Crinacle, oratory1990 and Super Review, with search results
  labelled by source and category. The built-in/local profiles are in a
  separate Local profile list.

## 0.3.1

- Reapplying a profile while EQ is on keeps the user's volume: the hardware
  stays parked at 100% and the EQ sink keeps the level it had.
- Turning EQ on from the switch or the Turn on chip applies the pending band
  and preamp edits instead of discarding them.

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

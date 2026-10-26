# Audio capability — what an output device can do, next to what it is doing

The helper behind the Audio plugin's **Rate & codec** section, kept as `scripts/audio-capability`.
It started as a standalone bar widget on the 830 G8 and moved into this plugin; the widget is gone.
References below to the old widget, `dinhlongviolin1.audiocap`, are history.

## What it is

A bar widget that sits immediately right of the stock volume icon. Click it and you get two
numbers:

| | |
|---|---|
| **Playing at** | what the device is actually running at right now |
| **Can do** | the highest rate the hardware itself advertises |

plus a plain-language line naming the reason when those two disagree, and a **Details** row you
press to unfold the evidence (format list, where capability was read from, clock rate, allowed
rates, quantum).

Four further controls: a **Sample rate** picker
([below](#choosing-the-rate-yourself)), a **Codec** section that appears only for a Bluetooth
sink ([below](#choosing-the-bluetooth-codec)), a **Display** row that toggles the panel between
120 Hz and 60 Hz ([below](#display-refresh--120-hz--60-hz)), and press-to-copy paths for every
file the tool writes. On a Bluetooth sink the codec *is* the rate story — SBC and AAC are stuck at
44100/48000 while LDAC runs to 96 kHz — so that section is what makes the two columns above it
mean anything there.

It is a **viewer that can act, once, on purpose.** Opening it, and the 3-second refresh behind
it, only read — nothing runs on a timer, on a device plug, or on boot. The panel gets its second
half from one row you have to press, and the same press again takes it back. See
[Applying the fix](#applying-the-fix).

## Why the two columns are the whole point

Neither column is trustworthy alone, and the gap between them is invisible from either side:

- **Capability comes from the hardware** and drivers misreport it. A USB DAC's
  `/proc/asound/card<N>/stream0` is authoritative — every altset with its exact format, bit depth
  and rate list. Nothing else on the system has this. (A SMSL PO100 claims 32-bit/768 kHz while
  handling 24/192 in practice.)
- **In-use comes from PipeWire**, which silently resamples to the graph clock. So an iBasso
  DC-Series advertising 44.1–384 kHz and native DSD sits at **48 kHz forever** with no error
  anywhere.

The usual culprit is `clock.allowed-rates` in `pw-metadata -n settings`. When it holds a single
rate, the graph only ever runs at that rate and a higher one can't be negotiated — which is why
the helper reports that as its own warning rather than leaving you to infer it.

**Two different things are called "bitrate" here.** Sample rate is 44.1/48/192/384 kHz. Codec
bitrate is LDAC's 990/660/330 kbps. They are orthogonal — a Bluetooth headphone can be at
990 kbps and still be resampling. The panel shows the rate in both columns and gives the codec
its own section with its own controls (see [Choosing the Bluetooth codec](#choosing-the-bluetooth-codec)),
because on a Bluetooth sink the codec *is* the rate story: which codec is negotiated fixes the
rate list above it.

## Applying the fix

Seeing the gap and being able to close it are different things. Below the problem line the
panel carries **one row**: press it and the machine re-detects the connected output devices and
configures sampling so each can run at the full PCM rate it advertises. Press the row under it
(**Undo**) and everything goes back.

> ⚠ **Do not press Apply while a device you care about is unplugged.** Apply regenerates both
> files from **the devices connected at that moment**, so a DAC that is away contributes nothing
> to the union *and* gets no per-device rule. Applying without it **narrows the config** —
> `--plan` will show it, e.g. `union: [48000]` instead of the DAC's eight rates — and the next
> replug leaves that device at 48 kHz until Apply is pressed again *with it connected*. The
> revert path is the same shape in reverse. Check `--plan` before pressing apply on a machine
> whose device set has changed; the *What was written* paths make the current file readable if
> you want to see what would be lost.

Press that first row and a **second one appears** — **Make it live now**. The apply row itself
is non-disruptive: it writes the files and moves the graph clock live. The per-device half
cannot move that way, so the panel offers the one action that makes it land — a WirePlumber
restart — as its own press, after you have seen what was written. Until you press it the panel
says so plainly rather than showing a tick that implies everything is already in force.

**Nothing here runs by itself.** Not on open, not on a timer, not on a plug event. The 3-second
refresh behind an open panel only reads. The only writers are rows you pressed — and the second
one only restarts a user service, never touches a config file.

### The two layers, and why both are needed

| Layer | Mechanism | Scope |
|---|---|---|
| **Global** | `default.clock.allowed-rates` in `~/.config/pipewire/pipewire.conf.d/50-audio-capability.conf` | the graph clock — the set of rates it may switch between |
| **Per-device** | `monitor.alsa.rules` → `update-props { audio.allowed-rates }` in `~/.config/wireplumber/wireplumber.conf.d/50-audio-capability.conf` | one node — which rates it may be *opened* at |

**Global is the lever.** `man pipewire.conf`: *"The graph sample rate will be switched when
devices are idle."* Nothing changes without it, and the stock value on this machine is the
single rate `[ 48000 ]`.

**Per-device is the safety net.** `man pipewire-props`: *"Only rates from the array will be used
to open the device."* Upstream ships `allowed-rates` off by default *"because of various kernel
and Bluetooth issues"* — and this machine is exactly that case: four internal HDA sinks
advertise **exactly one** rate (48000), and the iBasso advertises **eight**. Widening the graph
clock without pinning each device is the unsafe version of this change, and it is the version
that produces silence.

**Bluetooth is the third case, and it is *not* "fixed at 48000".** That is only true of SBC and
AAC, which are stuck at 44100 or 48000. **LDAC runs 44.1 / 48 / 88.2 / 96 kHz**, so the rates a
Bluetooth sink offers are a property of *the codec that was negotiated* — which is why the codec
now has its own control. An earlier version of this doc asserted the flat "fixed at 48000", and
so did the comment inside the generated bluez rule; both were wrong the moment LDAC was in play.

**Observed 2026-10-13:** with an LDAC headset actually connected, the sink runs at **96 kHz** —
`inUse.rate: 96000`, and the panel shows "Playing at 96 kHz / Can do 96 kHz". So the "fixed at
48000" version of this claim was not merely imprecise, it was wrong about this machine.

The generated rule still pins `[ 44100 48000 ]`, which is the **conservative** choice, and it is
still recorded as **unverified**: the pin only lands on a *reconnect*, and at the time of writing
the headset was running without it. Whether that pin **caps** LDAC at 48 kHz or merely fails to
widen it therefore remains unobserved. It is deliberately not widened on a guess — the same rule
this feature applies to rule keys it has not seen work. See
[the codec gate](#verification-status).

**The two halves apply at different times, and the UI says so:**

- **Global applies live** via `pw-metadata -n settings 0 clock.allowed-rates "[ … ]"`. No
  restart, no interruption, even mid-album.
- **Per-device applies when WirePlumber next creates the node** — a replug, or
  `systemctl --user restart wireplumber`. WirePlumber has `CanReload=no`, so there is no soft
  reload, and no way to poke `monitor.alsa.rules` at a running node. That is a **user** service:
  **no `sudo` anywhere in this feature.** Because the restart is the only thing that makes the
  per-device half real, the panel does not leave it as a copy-paste instruction — it is the
  **Make it live now** row (see [below](#making-it-live-and-seeing-what-was-written)).

### What it writes

Exactly two files, both in `$HOME`, both tagged as generated, both deletable. Neither is
hand-made, and both are regenerated on the next apply.

A **third** file exists, but the apply path never touches it: the Bluetooth codec preference
(`51-bluetooth-prefs.conf`, see [Choosing the Bluetooth codec](#choosing-the-bluetooth-codec)).
It is kept separate on purpose — the file below is **regenerated from the detected device set on
every apply**, so a user's codec choice stored there would be silently clobbered by the next
apply. `--revert` leaves the preference alone too: forgetting the codec is its own press.

`~/.config/pipewire/pipewire.conf.d/50-audio-capability.conf` — the union of every connected
sink's advertised rates, ascending:

```conf
# Generated by audio-capability — do not edit.
# Revert:  audio-capability --revert
# Applied: 2026-10-12T23:02:25+07:00
#
# Union of 5 output device(s) (1 variable-rate, 4 fixed-rate).
# Restores to: [ 48000 ]
context.properties = {
  default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 352800 384000 ]
}
```

`~/.config/wireplumber/wireplumber.conf.d/50-audio-capability.conf` — one `monitor.alsa.rules`
entry per sink, each pinned to its own ladder, plus a Bluetooth rule:

```conf
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~^alsa_output[.]usb-iBasso_iBasso-DC-Series_5000000001" } ]
    actions = { update-props = { audio.allowed-rates = [ 44100 48000 88200 96000 176400 192000 352800 384000 ] } }
  }
  {
    matches = [ { node.name = "~^alsa_output[.]pci-0000_00_1f[.]3-platform-skl_hda_dsp_generic[.]HiFi__Speaker__sink$" } ]
    actions = { update-props = { audio.allowed-rates = [ 48000 ] } }
  }
  # … one more per HDA sink (HDMI 1–3) …
]

monitor.bluez.rules = [
  {
    matches = [ { node.name = "~^bluez_output[.]" } ]
    actions = { update-props = { audio.allowed-rates = [ 44100 48000 ] } }
  }
]
```

Details that matter, all of them earned:

- **`[.]` instead of `\.`** for a literal dot in the regex. `~` means POSIX ERE, and a backslash
  inside a SPA-JSON string inside a `.conf` needs two escaping layers — miscount one and the
  rule matches nothing, silently. A character class needs no escaping and means the same thing.
- **Match on a stable prefix, not the whole node name.** A USB node name carries a volatile
  `-<card-index>.<profile>` tail (`…5000000001-01.analog-stereo`) that changes with the profile.
  The rule anchors on the vendor/product/serial prefix, which survives a replug. Names with no
  variable part get a plain exact match (`^…$`) instead — no reason to reach for a regex when a
  string compare will do.
- **`monitor.alsa.rules` matches on `node.name`**, which is a *node* property. `device.name`
  identifies the *card*, and all four HDA sinks share one card — so a card-scoped rule cannot
  express per-sink ladders at all.
- **Bluetooth pins `audio.allowed-rates` on a `node.name` match**, not `bluez5.default.rate`.
  That property is real, but it lives under `monitor.bluez.properties` (plugin construction
  props) and is **not** a valid rule `update-props` key — a rule setting it would be a no-op.
  The same split governs the codec, and getting it wrong is the trap this section exists to
  stop: **`bluez5.codec`** (singular, the codec *in use*) is a runtime property you can write
  live; **`bluez5.codecs`** (plural, the *preference order*) is a **monitor property under
  `monitor.bluez.properties`**, set at plugin construction, with **no documented runtime
  setter**. So the plural is written to a config file and takes effect on the **next connect** —
  it is not, and cannot be, a live knob. See
  [Choosing the Bluetooth codec](#choosing-the-bluetooth-codec).
- **No `override.` prefix.** WirePlumber concatenates JSON arrays found across config files;
  `override.` *replaces*. Using it would delete the stock `/usr/share/wireplumber` VM rules.
- **`50-` is deliberate.** Omarchy's own audio tuning deletes stale `90-omarchy-speaker-tuning.conf`
  from both directories, so anything named `90-*` is unsafe to own.
- **Empty capability means omitted.** A sink whose rate read failed gets **no rule and no place in
  the union**. An empty `audio.allowed-rates` array does not mean "no rates" — it means *any*, so
  writing it would be a silent behaviour change in the opposite direction.

Every generated file is validated through **`spa-json-dump`** — the daemons' own SPA-JSON reader
— before it is moved into place, so a config that the daemon cannot parse is never written.

### Revert

Three things, because a partial revert is worse than none:

1. Delete both generated files.
2. Restore the live rate list from `~/.local/state/audio-capability/pre-apply-rates`, captured
   the first time apply ran.
3. If that file is gone (fresh machine, or a reboot since), fall back to the daemon's documented
   stock default `[ 48000 ]` — and say which of the two was used.

Revert is safe to run twice. It **refuses** (exit 3, removing nothing) if either target file
lacks the generated-by header, so a hand-written `50-audio-capability.conf` is never destroyed.

### Making it live, and seeing what was written

The per-device rules sit in a file until WirePlumber re-reads it, and WirePlumber only reads it
when it creates a node. So a completed apply leaves the machine in a state that is *half* real:
the clock has moved, the rules have not. The panel refuses to paper over that.

Once `--status` reports `rulesExpected` and not yet `rulesLanded`, a row appears:

> ⚡ **Make it live now** — *restarts WirePlumber · audio gaps for a moment*

Press it and it runs `audio-capability --activate`, which:

1. **Refuses to do anything if no files are applied** (exit 3). It will not restart the audio
   stack to make nothing happen.
2. Runs `systemctl --user restart wireplumber`, capped at `timeout 20`.
3. **Polls for the rules to actually land** — up to 12 times at 400 ms, each poll a single
   `pw-dump` filtered in `jq` (~30 ms), not a re-survey. Worst case 7.2 s; typically 1–2 s.
   The poll stops as soon as every target node reports a non-empty `audio.allowed-rates`, so the
   common case does not wait out the cap.
4. Re-reads `--status` and reports what *happened*, not what was attempted.

The row then disappears, because `rulesPending` is no longer true — the panel's own condition
is the report. If the poll never saw the rates land, the row stays and the panel says the rules
did not take, which is the honest result and the signal to set `EMIT_DEVICE_RULES=0`.

**It is a user service.** `wireplumber.service` is `/usr/lib/systemd/user/wireplumber.service`,
`CanStart=yes`, `CanStop=yes`, `CanReload=no` — so a restart is stop+start, needs **no polkit
prompt and no `sudo`**, and the panel row is a plain `systemctl --user` call. That is the whole
reason the button can exist where a "fix my audio" script could not.

**Below the rows, the panel names what it wrote.** A *What was written* section lists the two
generated files by their role — **Graph clock** (`pipewire.conf.d`) and **Per-device rules**
(`wireplumber.conf.d`) — with the full path under each, and **one press copies that path** to
the clipboard (the same `wl-copy` route the network and Tailscale panels use; the row confirms
with *Copied* for a moment). The path is the handover: it is what you paste into an editor, a
diff, a bug report, or `cat`.

Both paths come out of the plan the panel polls anyway, so the control costs **no extra
process at all** — and pointing at the file beats re-rendering what we meant to write, because
the file on disk is the thing that actually counts. `audio-capability --show global|device`
still reads a file back byte-for-byte from a shell; the panel simply no longer needs it.

### Verification status

Recorded honestly, because two of these held and one has not been run yet:

| Check | Result |
|---|---|
| Generated files parse under `spa-json-dump` | **pass** — 5 ALSA rules + 1 bluez rule |
| Per-device regexes match the live node names | **pass** — all 5, including the iBasso prefix catching the full `-01.analog-stereo` name |
| Global layer applies live with no restart | **pass** — `pw-metadata` takes the full ladder, audio uninterrupted |
| Revert, revert-again, refusal on a foreign file | **pass** — restores `[ 48000 ]`, idempotent, exits 3 and leaves the foreign file alone |
| `--activate` refuses with nothing applied | **pass** — exit 3, and WirePlumber is not restarted |
| `--activate` worst-case duration | **pass** — 7.16 s (12 polls × a single `pw-dump`), ~1–2 s when the rules land |
| `--show` on a missing file / a bad target | **pass** — exit 0 with `exists:false`; exit 2 for a target that is not `global`/`device` |
| Panel loads with the new rows | **pass** — widget renders (sliders icon), `qmllint` clean against a stock-panel control |
| **Per-device rules land on the created node** | **pass** — see below; this was the gate the whole layer rested on |
| `--rate` pins and releases the live clock | **pass** — `--rate 96000` moved the DAC's own `Momentary freq` to 96000 Hz, `--rate auto` returned it to 44100 following the stream |
| `--rate` refuses what it cannot do | **pass** — exit 3 for a rate outside the device's ladder and for one outside `clock.allowed-rates`; exit 2 for a non-number |
| `--codec` refuses a name this build cannot load | **pass** — exit 3, and the message names the offered set |
| `--codec` refuses a non-Bluetooth sink | **pass** — exit 3, naming the sink it *is* on |
| `--codec-pref` writes, merges, validates and clears | **pass** — each key rewrites only its own; setting `quality` keeps the codec order; the file parses under `spa-json-dump`; `none` deletes it |
| `--codec-pref` refuses a file it did not write | **pass** — exit 3, file untouched |
| The hardware-database force flag is written with a codec that needs one | **pass** — `codec=sbc_xq` writes `bluez5.enable-sbc-xq = true`; switching to `aac` leaves **no** stale force (`grep -c` = 0) |
| The codec read path, against a captured graph | **pass** — see below |
| An option missing its value exits 2 rather than hanging | **pass** — was an **infinite loop**, see the trap below |
| A report that cannot be built fails loudly instead of printing nothing | **pass** — exit 5, empty stdout; the jq error on stderr for an unnamed field, `$VAR is not valid JSON` for a validated one; see below |
| **The live codec switch, against a real headset** | **pass, 2026-10-13** — an XM6, `ldac → aac → ldac`, audio staying on the same sink |
| **The `monitor.bluez.rules` pin landing on the created node** | **not run — needs the headset** |

The codec read path was exercised **with no headset attached**, by replaying a `pw-dump` in which
one node is relabelled as a bluez sink carrying `api.bluez5.codec: "ldac"`:

```bash
AUDIO_CAP_PWDUMP=/path/to/bt-sink.json AUDIO_CAP_SINK=bluez_output.AC_80_0A_11_22_33.a2dp-sink \
  audio-capability | jq .codec
# → {"bluetooth":true,"current":"ldac","known":[ 14 ],"preferred":[], …}
```

That proves the **read** path — the `bluetooth` flag, `current`, the known list, the preference
read-back — and as of 2026-10-13 it is verified against the **real graph**, not a relabelled one:
a WF-1000XM6 was connected and this exact invocation returned the values above, with the real
fixture captured (`pw-dump > /tmp/bt-sink.json`). **The fixture lives in `/tmp`, so it does not
survive a reboot** — recapture it the next time a headset is connected if you need it, and note
that replaying it needs `AUDIO_CAP_SINK` set to the captured node name as well, because the dump
is keyed by node name and the live sink will never match it.

The gate — **did `monitor.alsa.rules` actually reach the created node?** — was run on
**2026-10-12 23:22** by pressing **Make it live now**, and it **passed**. WirePlumber 0.5.17 on
this machine honours the rule. The evidence, in the order it settles the question:

```bash
# 1. the run itself, from ~/.local/state/omarchy/audio-capability.log
2026-10-12T23:22:23+07:00 activate restarted=true landed=true

# 2. every ALSA node now carries its intended ladder — the iBasso 8 rates, the four
#    fixed HDA sinks still the single 48000 they advertise
pw-dump | jq -r '.[] | select(.type=="PipeWire:Interface:Node")
  | select((.info.props["media.class"] // "") | test("Audio/Sink"))
  | [.info.props["node.name"], (.info.props["audio.allowed-rates"]|tostring)] | @tsv'

# 3. and the hardware, which is the only opinion that finally counts
cat /proc/asound/card1/stream0 | grep -E "Altset =|Momentary freq"
```

Step 2 shows `[ 44100 48000 88200 96000 176400 192000 352800 384000 ]` on the iBasso and
`[ 48000 ]` on each HDA sink — i.e. *the rules, not just the union*. Step 3 reports
`Altset = 3` (`S32_LE`) and `Momentary freq = 44100 Hz`: the DAC running 32-bit at 44.1 kHz,
which is Spotify's own rate, so no rate conversion is happening at all.

Run it by hand instead if you prefer:

```bash
audio-capability --apply
systemctl --user restart wireplumber      # interrupts audio briefly
audio-capability --status | jq .rulesLanded
```

**Fail** would be `null`/absent, in which case the per-device block is dropped by setting
`EMIT_DEVICE_RULES=0` at the top of the helper and the feature degrades to global-only. That
was not needed here.

**Of the two Bluetooth gates, one has now been run and one has not.** "No evidence" and
"evidence of no problem" are different things, so neither was ever implied:

| Gate | Flag | State |
|---|---|---|
| The `monitor.bluez.rules` pin lands on the created bluez node | `EMIT_BLUEZ_RULE` | **pending** — needs a reconnect to observe |
| A live A2DP codec switch actually takes | `EMIT_BLUEZ_CODEC_SWITCH` | **PASS, 2026-10-13** — see below |

The second is the one that mattered, because it is **documented nowhere**: the mechanism exists
in this build's own plugin (`libspa-bluez5.so` exports `codec_switch_configure_a2dp`,
`codec_switch_start_timer`, `codec_switch_reply`, `codec_switched`, and the recovery path
`failed to switch codec (%d), setting basic profile`) but no public command is specified for it.

### The first implementation was wrong, and it failed in a way that looked like a dead feature

Two mistakes, each independently sufficient to make a working mechanism report "no change":

1. **The key.** The card does not expose `bluez5.codec`. It exposes a SPA param prop:

   ```
   $ pw-cli enum-params <card-id> Props
     Prop: key Spa:Pod:Object:Param:Props:bluetoothAudioCodec (270), flags 00000000
       Id 8        (Spa:Enum:BluetoothAudioCodec:ldac)
   ```

   — an **ordinal** from `spa/param/bluetooth/audio.h`, in a different namespace from the other
   codec keys. `{"bluez5.codec": "aac"}` is accepted, echoed back by `pw-cli`, and ignored.
   The ordinals are the header's own order (`START` = 0, so `SBC`=1, `SBC_XQ`=2, `MPEG`=3,
   `AAC`=4 … `LDAC`=8), and `LDAC`=8 is **confirmed against the card**, which reports `ldac`
   as `Id 8`, rather than assumed from the arithmetic.

2. **The readback.** A successful switch **tears the media node down and creates a new one** —
   observed going node 83 → 53 → 111, same `node.name`, different id. Reading the codec back by
   a remembered node id returns nothing for a switch that in fact worked, so the tool now looks
   the node up **by name**.

The evidence, from the live XM6:

```
$ audio-capability --codec aac
{"action":"codec","ok":true,"requested":"aac","before":"ldac","codec":"aac","switched":true,"fellBack":false,"target":"39"}
$ audio-capability --codec ldac
{"action":"codec","ok":true,"requested":"ldac","before":"aac","codec":"ldac","switched":true,"fellBack":false,"target":"39"}
```

`target: "39"` is the **card**, not the media node — that is the object that carries the prop.
Audio stayed on the same sink through both switches. Flip `EMIT_BLUEZ_CODEC_SWITCH=0` and
`--codec` refuses with a distinct "this build does not support live switching" while
`--codec-pref` keeps working.

### What the headset supports is a different question, and the panel does not answer it

The offered list is **what this machine can load** (14 codecs). The headset's own set comes from
BlueZ, which registers the remote's stream endpoints as objects under the device:

```bash
$ busctl tree org.bluez | grep sep
  ├─ /org/bluez/hci0/dev_58_18_62_8D_55_1A/sep1
  ├─ /org/bluez/hci0/dev_58_18_62_8D_55_1A/sep2
  └─ /org/bluez/hci0/dev_58_18_62_8D_55_1A/sep3
$ busctl get-property org.bluez /org/bluez/hci0/dev_…/sep1 org.bluez.MediaEndpoint1 Codec
y 0        # 0 = SBC,  2 = AAC,  255 = vendor — then Capabilities carries the vendor id
```

The XM6 exposes exactly **three**: SBC, AAC and LDAC (vendor `0x0145`, codec `0x00AA`). So of
the 14 rows on offer, 3 are usable with these buds and the other 11 are not *incompatible* —
they are simply not something this headset accepts. Pressing one is harmless (the switch
either takes or the readback says it did not), but the panel does not yet distinguish them.

If the switch *does* turn out to fail, the failure mode it must never have is the quiet one: a
plugin that drops the headset to SBC and reports success. The helper reads `api.bluez5.codec`
**back** after the write and reports the fallback as its own outcome, so a headset that refused
LDAC says so rather than showing a tick.

**Not `omarchy-restart-audio`.** It reads like the house tool for this and is the wrong one: it
restarts all three services and, if PipeWire looks unhealthy afterwards, walks `/proc/asound/*/status`
and can `sudo usbreset` USB audio devices to recover a stuck one. That is a *recovery* hammer for
audio that has already failed, not an apply step — pointing it at a working system to re-read one
config file invites exactly the USB reset it exists to perform.

## Choosing the rate yourself

Everything above is *automatic*: once the clock is allowed to move, it follows the stream. Sometimes
you want to override that — pin the graph to one rate, deliberately, right now.

The panel carries a folded **Sample rate** row that states the current answer — `Auto — following
44.1 kHz`, or `Pinned at 96 kHz — Auto releases it` — and unfolds into the choice. Picking one runs
`audio-capability --rate <n>`; picking **Auto** runs `--rate auto`. Underneath, all of it is one
property:

```bash
audio-capability --rate 96000    # pin the graph clock
audio-capability --rate auto     # release it
```

**Why `clock.force-rate` and not `clock.rate`.** `clock.rate` is the *startup default*: writing it
changes nothing until the daemon restarts, and it is precisely the single value `clock.allowed-rates`
exists to move away from. `clock.force-rate` is the live lever — immediate, no restart, no
privilege, and `0` releases it. It is also the **only** way to change the rate *now*, because
otherwise the graph picks a new rate only **when the devices go idle**; that is why a continuously
playing stream can sit at the old rate indefinitely.

**What pinning costs.** A pinned graph converts everything that is not already at that rate, so
pinning 96 kHz while Spotify sends 44.1 kHz adds exactly the resampling this whole widget is about
removing. That is not a defect — *pin* is for when you want one rate on purpose (a fixed-rate DSP
or DAC mode), or to prove which rate the hardware is really on. **Auto** is the listening state.

**What is offered is deliberately narrow.** The dropdown lists the **intersection** of the rates the
current device advertises and the rates in the live `clock.allowed-rates`. A rate outside that set is
refused (exit 3) rather than offered, because `pw-metadata` will cheerfully accept a value the clock
can never reach and then do **nothing** — the exact silent no-op this tool exists to expose. In
practice that means the list is short before the fix is applied (usually just 48 kHz) and the
device's full ladder after it.

Verified here: `--rate 96000` moved the iBasso's own `Momentary freq` to `96000 Hz`, and `--rate
auto` returned it to `44100 Hz`, following the stream again.

## Choosing the Bluetooth codec

A Bluetooth sink has **no `/proc/asound` entry at all**, so the capability read has nothing to
enumerate. Whatever A2DP negotiated *is* the device's rate list, and it was never visible or
choosable: the widget showed the codec only as a passive line in Details. This section is that
gap closed.

### Three different things are called "the codec"

Conflating them is the whole failure mode, so they are separated explicitly:

| | what it is | lever | takes effect |
|---|---|---|---|
| **codec choice** | which codecs are preferred | `bluez5.codecs` — a **plural**, ordered list | **next connect** |
| **codec switch** | change it on an open A2DP link | `bluez5.codec` — a **singular** `Props` write | **immediately, if it works** |
| **codec tuning** | LDAC quality, AAC bitrate mode | `bluez5.a2dp.ldac.quality`, `bluez5.a2dp.aac.bitratemode` | **next connect** |

The plural is the trap. **`bluez5.codecs` is a monitor property** — it is documented only under
`monitor.bluez.properties`, is read at plugin construction, and has **no documented runtime
setter**. Anyone reaching for `wpctl set-profile` is also wrong: the profiles this build exposes
are per-**role** (`a2dp-sink`, `a2dp-source`, `bap-sink`, `bap-source`, `bap-duplex`), never
per-codec. So:

```bash
audio-capability --codec ldac       # switch NOW on the open link (the risky half)
audio-capability --codec-pref codec=ldac    # remember it for the NEXT connect
audio-capability --codec-pref quality=hq    # LDAC quality; also next connect
audio-capability --codec-pref bitrate=3     # AAC bitrate mode
audio-capability --codec-pref none          # forget; WirePlumber's default returns
```

### What can and cannot be known

**There is no `api.bluez5.codecs`.** This build reports `api.bluez5.codec` — the *current* one —
and nothing anywhere enumerates **what a given headset supports**. So the list the panel offers
is *what this machine can offer*, not what your headphones accept, and the panel does not pretend
otherwise: a codec the headset cannot do is refused by the headset, and the only truth-teller is
the **read-back** after the attempt. `--codec` reads `api.bluez5.codec` back and reports what
happened, including a drop to the basic profile, rather than reporting the request.

`KNOWN_CODECS` is derived from this build, not from a list someone remembered:

```bash
strings /usr/lib/spa-0.2/bluez5/libspa-bluez5.so | grep -oE '^[a-z0-9_]{3,20}$' | sort -u
# → sbc sbc_xq aac ldac aptx aptx_hd aptx_ll aptx_ll_duplex faststream
#   faststream_duplex opus_05 opus_05_duplex opus_05_pro lc3
```

**What is offered, and what is deliberately not.** The set is everything this build can actually
load, which is what "support what is already there" means — offering more would be offering
buttons that cannot work:

| Codec | Here? | Why it matters |
|---|---|---|
| **SBC** | ✅ | universal — every A2DP device supports it |
| **AAC** | ✅ | Apple and most modern headphones |
| **LDAC** | ✅ | Sony and many Android-era headphones; `libldac` present |
| **aptX / aptX HD / aptX LL** | ✅ | Qualcomm-licensed headphones; `libfreeaptx` present |
| **SBC-XQ** | ✅ | a Linux-side bitrate boost, not a headphone feature — see the force flag above |
| **FastStream** | ✅ | low-latency, for headsets used for calls |
| **Opus 05 (three variants), LC3** | ✅ | present in the build; rare in the wild |
| **aptX Adaptive** | ❌ | **common on newer Qualcomm headphones, and there is no SPA plugin in this build.** The one genuinely-felt absence |
| **Samsung SSC, LHDC** | ❌ | proprietary, never in mainline — no plugin |

A sweep of `libspa-codec-bluez5-*.so` is the check, not a list someone remembered. Re-derive it
after a PipeWire bump — a new codec plugin is exactly what a release adds, and `--codec` refusing
a codec the build now has is the symptom.

**Not codecs, and not offered as entries.** The plugin directory also holds `g722`, `hfp-cvsd`,
`hfp-msbc`, `hfp-lc3-*` and `opus-g` — those are **HFP/HSP voice codecs for phone calls**, a
different profile entirely, and putting them in an A2DP list would be a category error of the
same kind as offering `lc3` there.

**LE Audio is not a codec choice.** LC3 belongs to the `bap-sink` *profile*, not to the A2DP
codec list, so it can be *reported* but not offered as a dropdown entry. Choosing `lc3` while on
A2DP would be a category error, which is why the list is the A2DP set.

### The preference file

`~/.config/wireplumber/wireplumber.conf.d/51-bluetooth-prefs.conf` — a **third** generated file,
`50-`-numbered for the same reason as the others (Omarchy deletes stale `90-*` from both audio
dirs), with the same generated-by header and the same refusal to touch a file it did not write.

It is deliberately **global, not per-device**, and this is the part worth being explicit about.
`bluez5.codecs` is ordered, and the order is a **priority**: `[ ldac aac sbc ]` reads as "LDAC,
else AAC, else SBC" — which does the right thing for a headset that cannot do LDAC without
knowing anything about that headset. A per-device rule would need the headset's identity *and*
its capability list, and we have neither.

The chosen codec is written **first**, followed by every other codec this build knows. This is the
whole file after `--codec-pref codec=ldac`:

```conf
# Generated by audio-capability — do not edit. Revert: audio-capability --codec-pref none
# Written 2026-10-13T00:28:56+07:00.
# Applies to the NEXT connect: bluez5.codecs is a monitor property, so
# nothing here can take effect on an already-open A2DP link.
monitor.bluez.properties = {
  bluez5.codecs = [ ldac sbc sbc_xq aac aptx aptx_hd aptx_ll aptx_ll_duplex faststream faststream_duplex opus_05 opus_05_duplex opus_05_pro lc3 ]
}

monitor.bluez.rules = [
  {
    matches = [ { device.name = "~bluez_card[.]" } ]
    actions = { update-props = {
      bluez5.a2dp.ldac.quality = "auto"
      bluez5.a2dp.aac.bitratemode = 0
    } }
  }
]
```

Listing **only** the chosen codec would be the obvious simplification and it is wrong: the list
selects among *enabled* codecs, so a one-entry list **disables every other codec** and breaks any
headset that cannot do the chosen one. Chosen-first gets the wanted codec wherever it is
supported and falls through cleanly where it is not.

Both tuning knobs are always written — `auto` and `0` are the plugin defaults, so writing them
explicitly costs nothing and keeps the file a complete statement of the preference rather than a
partial one that a later merge has to reconstruct. They sit in the same file under a rule scoped
by `device.name = "~bluez_card[.]"` so they reach the **card**, not the node.

Both property names are verified **inside this build's own codec plugins**, not inferred —
`bluez5.a2dp.ldac.quality` lives in `libspa-codec-bluez5-ldac.so` and
`bluez5.a2dp.aac.bitratemode` in `-aac.so`. LDAC quality is `auto|hq|sq|mq` (990/660/330 kbps);
AAC bitratemode is `0` for CBR then `1`–`5`.

The whole shape of this file is confirmed by the vendor's own example, shipped with this exact
version at `/usr/share/doc/wireplumber/examples/wireplumber.conf.d/bluetooth.conf` — the same
`monitor.bluez.properties` for the codec list *and* the same `monitor.bluez.rules` →
`update-props` for the two tuning keys, with the same values. That file also confirms the
`bluez5.default.rate` claim above: it is listed under **construction properties**, not under
rules, which is why a rule setting it does nothing.

### Two codecs are not decided by the list alone

The same example settles a trap worth stating plainly:

> These features **do not work on all headsets**, so they are enabled by default based on the
> **hardware database**. They can also be **forced** on/off for all devices by the following
> options: `bluez5.enable-sbc-xq` …

So **SBC-XQ and FastStream are governed per-headset**, not by membership in `bluez5.codecs`. A
list containing `sbc_xq` is a *preference among enabled codecs* — and on a headset the database
did not enable it for, it stays off and the press appears to do nothing. Pressing SBC-XQ by name
**is** the documented "force" case, so the flag is written with the choice:

```conf
monitor.bluez.properties = {
  bluez5.codecs = [ sbc_xq sbc aac ldac … ]
  bluez5.enable-sbc-xq = true
}
```

It is recomputed from the current choice on every write, so switching to `aac` does **not** leave
a stale force switched on behind it. `bluez5.enable-faststream` is written the same way;
its name comes from the plugin's own property table rather than from the example, where it sits
beside the three documented flags.

**This was a real defect in the first cut of this feature** — the panel offered SBC-XQ as a
button that would have been accepted, stored, and silently unhonoured. It was found by reading
the vendor example against the plugin's strings rather than by testing, which is the only way it
*could* have been found without a headset.

**Rejected:** `wpctl set-profile` (profiles are per-role, not per-codec), and toggling the
profile off and on to force a re-pick — that re-negotiates but cannot *choose*. Also rejected:
a per-device `monitor.bluez.rules` → `update-props { bluez5.codecs = […] }`, which is **not
confirmed valid**. Writing unverified rule keys is the mistake the previous feature was gated to
avoid, and it is not repeated — see the `bluez5.default.rate` no-op above for the general shape.

### Reads and the preference are honest by construction

Each `--codec-pref` rewrites the file **from what is already on disk**, so setting the LDAC
quality does not silently forget the codec order. The panel separates the two halves so the
difference is visible rather than implied: switching now says what the readback shows, and
saving a preference says plainly that it **takes effect on the next connect, not on the open
link.** The same honesty as the *Make it live now* row — nothing claims to be in force before it
is.

`--revert` **does not touch this file.** Undoing the sample-rate fix is not the same act as
forgetting a codec, so forgetting is its own press (`--codec-pref none`). It is also the reason
the preference lives in `51-` and not in the `50-` the apply path owns: **that file is
regenerated from the detected device set on every apply**, so a codec choice stored there would
be clobbered by the next apply.

### A read that fails must not look like a read that succeeded

The codec rows stayed on **LDAC** after a press that had genuinely switched the link to **AAC**, and
the reason had nothing to do with codecs. `EnumFormat.format` carries two different shapes:

| node | `.format` | |
|---|---|---|
| an ALSA sink | `{"default":"S32LE","alt1":"S24_32LE"}` | an object of choices — `to_entries` is right |
| a bluez sink | `"S16LE"` | a bare **scalar** — `to_entries` on it is a jq **error** |

The read assumed the object. On a Bluetooth sink the jq call failed, `$( )` handed back the empty
string, and that empty string was passed to `--argjson capFormats`. **jq rejects the entire
argument list when a single `--argjson` is unparseable**, so the report was never built at all.
The tail then did the worst available thing with that:

```bash
jq -c . "$tmp" 2>/dev/null || cat "$tmp"     # prints the empty file, exits 0
```

Empty stdout at exit 0 — and the panel only raises an error when it has **never** loaded, so it
went on rendering the last report that had parsed. The link was on AAC, the helper agreed, and the
panel said LDAC. `rate` has this same scalar-or-object split on the very next line and has always
handled it; `format` never got the matching branch.

Three changes, and only the third matters beyond this one bug:

1. `format` is branched on its type, exactly as `rate` is.
2. `CAP_ALTSETS` / `CAP_RATES` / `CAP_FORMATS` are normalised to `[]`, so one unparseable field
   costs its own field instead of the whole report.
3. A report that still cannot be built **exits 5**, empty stdout, with the jq error on stderr. An
   empty read is not *"nothing changed"* — it is no answer, and it does not get to share exit 0
   with a real one. The panel renders the stderr line as an error, so the next version of this bug
   is loud instead of looking like a stale value.

### The same door, a second time — and the guard that closes it

Point 3 paid for itself within the hour. Switching to **SBC** worked (`before=ldac after=sbc
target=114 ok=true`, and the graph said `api.bluez5.codec=sbc`) and the panel again showed LDAC —
but this time the report failed *loudly*, exit 5, with `invalid JSON text passed to --argjson` on
stderr. A different argument, the same door:

```bash
PREF_CODECS="$(sed -n 's/.*bluez5\.codecs *= *\[\([^]]*\)\].*/\1/p' "$BT_PREF_CONF" | head -1 \
  | jq -R -c '[splits("[ \t]+") | select(length > 0)]' 2>/dev/null || echo '[]')"
```

The preference file existed — pressing a tuning knob writes one — but it carried **no
`bluez5.codecs` line**, which is correct and deliberate: a quality or bitrate choice does not
imply a codec order. sed therefore printed nothing, and **`jq -R` on no input prints nothing and
exits 0.** It does not fail, so the `|| echo '[]'` never fired, and `""` travelled on to
`--argjson prefCodecs`. The `-R -s` slurp form turns no-input into `""`, which splits to `[]`.
`--argjson allowedRates` had the identical latent flaw.

The fallback in both cases was written for **jq failing**, and the failure is **jq succeeding
quietly** — which is the harder of the two to see, and the reason a `||` default is not a guard.

So rather than fix a third one by hand, every JSON-valued argument is now validated *by name*
before the report:

```bash
for _json_var in CAP_ALTSETS CAP_RATES CAP_FORMATS ALLOWED_JSON WARNINGS PREF_CODECS; do
  _json_val="${!_json_var:-}"
  # Emptiness is checked separately and deliberately: `jq .` parses an empty
  # stream successfully, so the parse check alone would wave "" straight through.
  if [[ -z $_json_val ]] || ! printf '%s' "$_json_val" | jq . >/dev/null 2>&1; then
    echo "audio-capability: internal error — \$${_json_var} is not valid JSON: [${_json_val}]" >&2
    exit 5
  fi
done
```

It exits 5 naming the field. Verified by injecting both failure modes into a copy: a malformed
value gives `$CAP_FORMATS is not valid JSON: [notjson]` and the empty string gives
`$PREF_CODECS is not valid JSON: []`.

`--plan` already treats an unreadable rate list as its own condition — *"no rate list reported;
left at its current setting"* — and that is unchanged and deliberate. The internal HDA sinks
report `rate` as an object of choices rather than a `{min,max}` range, so they read as *no rate
list reported* and are left alone rather than guessed at. The cost is real and worth stating: the
panel shows no capability ladder for the internal speaker and the HDMI sinks.

## Install

Nothing to install. The plugin calls `scripts/audio-capability` by its own path, so
deploying the plugin deploys the helper. To run it from a shell:

```bash
~/.config/omarchy/plugins/mutex-solutions.audio/scripts/audio-capability --pretty
```

## Usage

Examples use the bare name; put `scripts/` on your PATH or call it by full path.

```bash
audio-capability                 # the current default sink, as JSON
audio-capability --pretty        # same, readable
audio-capability --device ibasso # first sink whose name matches, case-insensitive

audio-capability --plan          # what --apply WOULD do. writes nothing
audio-capability --status        # applied / not / partially, from disk + live
audio-capability --apply         # write the two generated files + switch the clock live
audio-capability --activate      # restart WirePlumber so the per-device rules land
audio-capability --revert        # delete them + put the clock back

audio-capability --rate 96000    # pin the graph clock to 96 kHz, right now
audio-capability --rate auto     # stop pinning; follow whatever is playing

audio-capability --codec ldac    # switch the open A2DP link's codec NOW (Bluetooth only)
audio-capability --codec-pref codec=ldac        # prefer it from the next connect
audio-capability --codec-pref quality=hq        # LDAC quality: auto|hq|sq|mq
audio-capability --codec-pref bitrate=3         # AAC bitrate mode: 0 (cbr) then 1-5
audio-capability --codec-pref none              # forget the preference entirely

audio-capability --show global   # the generated clock file, byte for byte
audio-capability --show device   # the generated WirePlumber rules, byte for byte
```

Exit codes: `0` ok, `1` no matching sink, `2` bad argument (including an option **missing its
value**, a `--show` target that is not `global` or `device`, a `--rate` that is not `auto` or a
number, and a `--codec-pref` that is not `key=value` or `none`), `3` refused — a file this did
not write is in the way, the rate list came out empty, `--activate` was asked to restart the
audio stack with nothing applied, `--rate` was given a rate the device does not advertise or the
clock cannot reach, `--codec` was given a name this build cannot load or aimed at a sink that is
not Bluetooth, or `--codec-pref` was given a codec outside the known set — `4` failed or partial.

**Every option that takes a value now requires it.** It did not always: `shift 2` with the value
absent fails, so `$1` never advanced and the argument loop spun forever. `audio-capability
--show` ran **2.5 million iterations in six seconds** and printed nothing — a mistyped
invocation hung the shell rather than erroring. All five value-taking options
(`--device --show --rate --codec --codec-pref`) now exit 2 with `<option> needs a value`.

**stdout is always exactly one JSON object**, in every mode — the panel parses it
unconditionally. Everything meant for a human goes to **stderr**.

In the bar: click the sliders icon. `Esc` closes. `r` re-reads and re-plans. `a` applies.
`m` makes it live (the WirePlumber restart; does nothing unless a restart is actually pending).
`u` reverts, and does nothing unless something is applied.

State changes append one line to `~/.local/state/omarchy/audio-capability.log`, the same
convention `agent-mode` uses. Reads and `--plan` log nothing.

## Verifying it actually works

Check the two columns against ground truth rather than trusting the panel:

```bash
cat /proc/asound/card1/stream0                 # capability (USB only)
pw-metadata -n settings | grep allowed-rates   # policy — the usual gate
pactl list sinks | grep -A1 'Sample Spec'      # in use
```

Then compare with what the helper derived:

```bash
audio-capability | jq '{inUse: .inUse.rate, capMax: (.capability.rates|max), warnings}'
```

Expect `inUse` to be below `capMax` and the divergence named in `warnings` whenever a
single-rate `allowed-rates` is pinning a multi-rate DAC.

**On a machine with no USB DAC attached**, the USB parser can still be exercised by pointing it
at a saved `stream0`:

```bash
AUDIO_CAP_STREAM0=/path/to/stream0 audio-capability --device anything --pretty
```

**On a machine with no Bluetooth sink attached**, the codec read path can be exercised the same
way. Both overrides are needed, because the graph is keyed by node name and the replay is not on
that sink:

```bash
pw-dump > /tmp/bt-sink.json          # capture this the first time a headset connects
AUDIO_CAP_PWDUMP=/tmp/bt-sink.json \
AUDIO_CAP_SINK=bluez_output.AC_80_0A_11_22_33.a2dp-sink \
  audio-capability | jq .codec
```

Neither override makes the **switch** testable. Whether a headset accepts a codec is a fact about
the headset, and there is no fixture for that.

Three different sources must all work, because the code paths differ:

```bash
audio-capability --device iBasso    # USB: stream0 path, altsets + DSD
audio-capability --device Speaker   # internal SOF/HDA: EnumFormat path, no stream0 exists
audio-capability --device WF        # Bluetooth: no stream0, codec in its own section
```

## Design notes worth keeping

- **A bar widget whose root is a bare `Item` renders nothing, silently.** `plugins/bar/Bar.qml`
  sizes the slot from `activeItem.implicitWidth`, which defaults to `0` — the widget still
  instantiates, its IPC target still registers, and no QML error is logged, so it reads as a
  *loading* failure when it is a *sizing* one. Forward the button's size
  (`implicitWidth: button.implicitWidth`); the stock audio panel does the same.
- **The helper owns every parse.** `/proc`, `pw-dump`, `pw-metadata` and `amixer` are all read
  in `audio-capability`, so the QML stays a renderer and the risky part is testable from a shell
  with no shell restart. This plugin is also the first `/proc` reader in the Omarchy shell.
- **Warnings are prose, not property names.** They render verbatim in the panel, so they are
  written the way a person would say them out loud — *"Playing at 48 kHz, but this device can do
  up to 384 kHz."* Anything that reads like a log line belongs in Details.
- **Details is folded by default.** The answer is two numbers; the format list and clock settings
  are how you confirm it, not what you came for.
- **`alsa.resolution_bits` is a static card hint, not a measurement — in two places.** On the
  internal SOF HDA it reads `16` for every sink on the card regardless of what is open; on the
  iBasso it read `16` while the negotiated format was `s32le`. So it is never used for the
  in-use depth (that comes from the negotiated format name, `s32le` → 32) **nor for the
  bit-depth warning** — comparing it there printed *"Playing 16-bit"* directly above
  *"s32le (32-bit)"* in the same panel, which is the exact class of error the warning exists to
  catch. It is carried as context only.
- **`amixer scontrols` prints only the short control name.** `Master,0` contains no "Volume", so
  a hardware-volume check must query `amixer -c N controls` instead.
- **One `pw-dump` per run.** It serialises the entire graph; calling it once per query triples
  the helper's cost.
- **The action gets its own `Process`, never the polling one.** The polling process is
  `running`-guarded and must not be blocked by a write. Rows are disabled while busy, and a
  **safety-net timer** clears the busy state so a row can't stick on *"Working…"* if the process
  dies without emitting `onExited` — the same pattern the network panel uses for its band write.
  The interval is **per mode**: 10 s for apply/revert, **45 s for `--activate`**, because the
  restart plus the 12-poll landing check can legitimately run ~7 s and a 10-second net could fire
  *under* a restart still in progress. On a nonzero exit the panel renders the helper's stderr
  line in `bar.urgent`; it never assumes the write succeeded. The exit handler captures the mode
  *before* clearing it, so the message a user sees names the action that actually failed.
- **A row is shown by what it changes, not by what happens to be live.** The LDAC quality and AAC
  bitrate rows began gated on `bt.current === "ldac"` / `"aac"`, on the reasoning that the other
  would be noise. That was wrong on its own terms: what those rows write is the **global** bluez
  rule (`device.name = "~bluez_card[.]"`), so a value set there applies to any LDAC — or AAC —
  device on the next connect, not to the codec live right now. Gating a durable, device-independent
  setting on a transient, device-specific state **conflates the very two axes this document keeps
  apart** (see *three different things are called "the codec"*). The visible cost is what surfaced
  it: switch codec and the row you were just using disappears, which reads as *the control is
  gone*. They are now unconditional inside the Codec section.
- **A QML `Row` rejects anchors on its children — and only says so once per render.** The trailing
  "prefer" chip was a `Row` whose `Text` children carried `anchors.verticalCenter` and whose
  `MouseArea` carried `anchors.fill: parent`. Qt logs *"Cannot specify left, right,
  horizontalCenter, fill or centerIn anchors for items inside Row. Row will not function"* — **once
  per row per paint**, so the journal filled with it — and lays the row out anyway, which left the
  chip's own `MouseArea` neither filling nor reliably clickable. The fix is an `Item` wrapper that
  owns the anchoring, with a plain `Row` inside it holding only the children's order and spacing.
  Same rendering, legal anchors. Note the warning is a *runtime* one: `qmllint` is silent about it,
  so only the journal shows it.
- **The pending-rules row is derived, never latched.** `rulesPending` is
  `applied && rulesExpected && !rulesLanded`, recomputed from `--status` on every poll — so the
  row disappears the moment the rules land, and reappears if a later restart loses them. Nothing
  stores "the user pressed make-it-live"; there is no local flag to drift out of sync with the
  daemon.
- **`--show` is answered before the sink survey.** Reading a file back needs no sink, and during
  the `--activate` restart there is briefly no sink to read. Handling `--show` first — with
  `file_state()` moved to the top level for it — is what keeps the viewer working precisely when
  the user is most likely to open it.
- **Apply is idempotent in both directions.** Running it twice writes the same content and does
  **not** re-capture `pre-apply-rates`, so Undo still restores what was really there before the
  *first* apply rather than the state apply itself created. Note this is idempotence *for a given
  device set* — pull a device out and apply, and the content genuinely changes (see the warning
  above). `--status` reports that as `drift` rather than as breakage: a DAC that has been
  unplugged disagrees with a config naming it, and the tool says so instead of guessing.
- **`--status` reporting `applied:false` after a device is unplugged is correct, not a fault.**
  It compares the generated config against **the devices present now**; the config is fine and
  still names the DAC, and replugging restores the match with no action at all. Do not "repair"
  it by applying — that is the one action that actually destroys the config.
- **A pinned rate and an allowed set are different questions, and only one can be answered
  automatically.** `clock.allowed-rates` is *which rates the graph may use*; `clock.force-rate` is
  *which one it is using, ignoring everything else*. Keeping them as separate controls is what stops
  "choose the rate" from quietly meaning "throw away the automatic behaviour" — Auto is always one
  press away, and the row says which state it is in.
- **The rate control reads its options from the same poll as everything else.** Both the device's
  ladder and the live allowed set are already in the read JSON, so the dropdown needs no process,
  no extra `pw-dump`, and cannot disagree with the two columns above it.
- **`clock.force-rate` is normalised, not passed through.** The daemon reports `0` to mean "not
  pinned", which is not a rate; the helper turns it into `null` in JSON rather than surfacing a
  0 Hz option that would read like a real choice.
- **`--plan` is a true dry run.** It writes nothing and does not even create
  `~/.config/pipewire` — that is what lets the panel show what a press would do, and detect
  "already applied", without side effects.

- **An option missing its value used to hang the shell, silently.** Every value-taking option
  read `${2:-}` and then ran `shift 2`. With the value absent the shift **fails**, `$1` never
  advances, and the `while [[ $# -gt 0 ]]` loop re-matches the same word forever —
  `audio-capability --show` burned 2.5 M iterations in six seconds and printed nothing, so the
  only symptom was a hang with no output and no error. All five now go through a `need_arg`
  guard that exits 2. Two things about the fix are worth keeping: the guard **cannot** be a
  command substitution, because `exit` inside `$( )` kills only the subshell and the loop spins
  on — it sets a variable instead; and note this was **latent in three pre-existing options**
  (`--device --show --rate`), not introduced with the codec work.
- **The shell's log is in the journal under the tag `omarchy-shell`** — not under
  `quickshell.service`, which does not exist, and **not** in Hyprland's own log, which holds
  none of it. Quickshell is launched by `omarchy-launch-shell` through
  `systemd-cat -t omarchy-shell`, and its stdout otherwise goes to Hyprland's exec socket, where
  nothing reads it. Checking the wrong one gives an **empty log that reads as a clean one**:

  ```bash
  journalctl -t omarchy-shell --since "-10 min"   # the real channel
  ```

- **The plugin loader logs "reloading" without re-instantiating the widget — so a new
  `Panel.qml` can sit on disk being ignored while the bar runs the old one.** This corrects
  what this doc said before 2026-10-13. `omarchy-launch-shell` sets
  **`QS_DISABLE_FILE_WATCHER=1`** (deliberately: a package upgrade rewriting the shell tree
  would otherwise reload against a half-written file), but Omarchy's plugin loader has its own
  watcher and does log:

  ```
  DEBUG qml: Local plugin changed, reloading: dinhlongviolin1.audiocap
  ```

  **That line is not proof the running widget changed.** What actually happened, on
  2026-10-13: an XM6 was connected, the panel showed no Codec section, and the installed
  `Panel.qml` provably contained one. Three reload events (00:21, 00:29, 00:51) each logged
  the line with no `ERROR qml:` after it, `omarchy-shell shell rescanPlugins` (the supported
  rescan IPC) changed nothing, and `~/.cache/quickshell/qmlcache/<sha1-of-panel-path>.qmlc`
  kept the compile-time stamp of the shell's **start**, never updating. A temporary
  `onReportChanged: console.log(...)` added to the plugin fired **zero** times across all
  three reloads and fired **immediately** on `omarchy restart shell`:

  ```
  DEBUG qml: AUDIOCAP-DEBUG sink=bluez_output.58_18_62_8D_55_1A.1 bt=true known=14 cur=ldac
  ```

  So: **verify a plugin edit by effect, never by the reload line** — change something you can
  observe (a row that should appear, or a temporary log line), and if the effect is missing,
  `omarchy restart shell`. A restart is safe for audio: it relaunches the bar and panels and
  touches neither PipeWire nor WirePlumber. Two things this cost: an hour chasing the guard
  (`isBluetooth`) when the guard was correct and simply not running, and one screenshot of the
  user's whole screen. Crop to the panel column (`grim` then `convert -crop`) if you do it
  again.

  Related, and worth knowing before trusting a log line for *ordering*: the same
  instrumentation showed `bt=false known=0` one tick before `bt=true known=14` on an
  identical report. QML handlers fire **during** the assignment, before the derived bindings
  recompute, so a value read inside one is the *previous* value. Sample twice, or read on the
  next tick.

## Maintenance

The stock `omarchy.audio` panel is **untouched**, so both keep working independently and
`omarchy update` cannot clobber either — this plugin lives outside `/usr/share/omarchy` by
construction. Disabling it restores stock exactly:

```bash
omarchy plugin disable mutex-solutions.audio
```

Re-check the helper after a PipeWire or WirePlumber bump — it parses `pw-dump` and
`pw-metadata` output, which are stable but not contractual:

```bash
audio-capability --pretty
```

After the same bump, re-run the per-device gate in
[Verification status](#verification-status) — the rule *format* is stable, but whether
`update-props` still lands on the created node is exactly the thing a WirePlumber release can
change under you. `audio-capability --status` reports both halves and flags drift between the
files on disk and the live clock.

The generated files are owned by the helper: they carry a generated-by header and are
regenerated on every apply. Don't hand-edit them — the edit is silently overwritten, and revert
refuses to delete a file that lacks the header precisely so it can never eat a hand-written one.
The Bluetooth preference (`51-bluetooth-prefs.conf`) is the same bargain under its own door:
`--codec-pref` rewrites it, refuses a file this tool did not write, and `none` deletes it —
while `--revert` leaves it alone.

**Note a consequence of that ownership**: editing the helper's *comments* does not change the
generated file already on disk, because apply is idempotent on **content**. This doc's bluez-rule
comment was corrected after the last apply, so
`~/.config/wireplumber/wireplumber.conf.d/50-audio-capability.conf` still carries the old, wrong
"A2DP is fixed at 48 kHz" text until the next `--apply` rewrites it. The state is converged and
correct; only the comment in that one file lags.

Re-derive `KNOWN_CODECS` after a PipeWire bump alongside the `pw-dump` check below — a new codec
plugin is exactly what a release adds, and `--codec` refusing a codec the build now has is the
symptom.

## Re-create from scratch

```bash
omarchy plugin add https://github.com/mutex-solutions/omarchy-audio
omarchy restart shell

# Confirm the helper.
H=~/.config/omarchy/plugins/mutex-solutions.audio/scripts/audio-capability
$H | jq .                                  # helper
$H --show global | jq .action              # "show"
$H --activate   ; echo "exit=$?"           # 3 while nothing is applied
$H --show       ; echo "exit=$?"           # 2, "needs a value", NOT a hang
$H --codec ldac ; echo "exit=$?"           # 3 unless a Bluetooth sink is current
$H | jq .codec                             # the codec block, always present
$H >/dev/null ; echo "exit=$?"             # 5 = no report could be built; stdout is empty
```

And confirm the plugin actually **loaded** rather than assuming it:

```bash
journalctl -t omarchy-shell --since "-2 min" | grep -i 'reloading: mutex-solutions.audio'
# then check nothing after it failed:
journalctl -t omarchy-shell --since "-2 min" | grep -iE 'ERROR qml|WARNING qml'
```

**Neither of those lines proves the running widget changed** — see the reload trap in the
verification section above. The only honest check is an **effect**: open the panel and confirm
the behaviour you edited is on screen. If it is not, `omarchy restart shell` and look again.
For a change with no visible surface, instrument it temporarily
(`onReportChanged: console.log("DEBUG …")`) and watch `journalctl -t omarchy-shell`.

The plugin is the **viewer** and nothing else. The action modes write nothing until a row is
pressed; at that point the two generated files named in
[Applying the fix](#applying-the-fix) appear, and to undo them:

```bash
audio-capability --revert     # deletes both, restores the clock, safe to run twice
```

No daemon is installed, no stock file is edited, and no `sudo` is used at any point.


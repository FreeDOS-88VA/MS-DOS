# J3c — ROM JFP versus project FEP

| Measured on vaeg m153 | `JFP ROM` | `JFP FEP` |
|---|---|---|
| 22 readings, first / by tap 10 | VA: 18/22 / 20/22; VA2: 17/22 / 21/22 at either RAM size | Same first candidate, rank and phrase focus for every fixture |
| HENKAN → rendered text | First: 4–88 guest frames; next: 2–5 | First: 4–89 guest frames; next: 2–5 |
| CHKDSK free after selection | 525,408 B at 640 KiB, 132,192 B at 256 KiB, unchanged from plain | Same |
| VAIO build-time resident growth | +795 B when originally added | +2,836 B when added on top of ROM; both paths already reside in the comparison build |
| Composition and DOS interaction | More ROM-specific pending keys, including a ZENKAKU mode change; converted Return confirms then submits on the next tap | F7 shows katakana; pending ZENKAKU leaves reading alone; same two-Return behavior on the converted fixture |
| Nested interrupts, stock image | No nested DOS calls; 10–106 nested text-BIOS calls per monitored trial | No nested DOS or text-BIOS calls in the scoped BIOS conversions/confirmation |
| Writes and malformed result | No changed D88 bytes with the default files absent. Unexpected-result injection NOT RUN. | No changed D88 bytes; does not call the learning operation. Rejected one injected bad trail, kept the reading, and recovered. |

## M2 — Conversion quality

[Decoded candidate and segmentation tables](J3c/quality.md): 144 cases and
1,824 TVRAM shots. The two front ends matched within each machine and RAM
setting. The machine mattered: for `kyouhaiitenkidesu`, both VA2 runs
showed `今日はいい天気です` at tap 1; VA gave `今日は言天気です` and did not
reach the expected whole phrase in ten taps on the initial focus. This
test does not search combinations of candidates across segments.

## M3 — Speed and memory

[Frame counts, CHKDSK results and resident-byte calculation](J3c/measure.md).
FEP was one frame slower on two VA first-conversion fixtures and tied
elsewhere in this test. The long example took 88/89 frames on VA but 22 in
both modes on VA2. Those are guest frames to the first matching rendered
sample, not host wall time or a hardware guarantee. The phrase was sampled
in two windows; the test does not establish what happened in the unsampled
gap. CHKDSK found no marginal
activation cost; the historical VAIO additions are already in IO.SYS.

## M4 — Keys and applications

[Per-key matrix and NEC screenshots](J3c/keys.md). The 43-tap idle byte
stream matched per key in both widths. COPY CON and EDLIN saved exactly
the expected Shift-JIS and line terminators. Both passed the shared DOS
CON probe (06h/07h/0Bh/0Ch), restored labels after composition and deferred
an active-mode hide until OFF. The tested pending key differences were
in the front ends, not in idle DOS key delivery. On PC-98 NECAIK, Ctrl+XFER
was the toggle, Space converted, and bare XFER and NFER each confirmed
unconverted kana on the tested reading. BS, ESC and the two-step Return
interaction were checked at the NEC prompt; this is not a claim of exact
key-map parity.

## M5 — Safety and risk

[Scoped interrupt counts and fault test](J3c/safety.md). Both modes had
zero actual nested INT 21h entries in the two monitored input contexts
on all three configurations; the positive control verified the hooks.
ROM's nested INT 83h calls are expected for its firmware-owned display;
FEP's BIOS backend did not enter INT 83h, and its own display work is
outside that scope. All twelve monitored disk copies were byte-identical
to the input image. The FEP limits and validates the result it accepts
from the BIOS and closes with `QuitJFP`, not `Decide`; it is not a memory
sandbox for firmware. The injected malformed-trail fixture confirms
fallback behavior only for that bounded error.

## NOT RUN

- `.DIC`/`.DAT` present or successfully loaded in either mode; no malformed
  placeholders were passed to the BIOS loader. No test of ROM in-memory
  learning, or of either mode's behavior with real external files.
- Injected unexpected ROM keyboard firmware results; FEP overrun,
  unterminated output or other injected faults beyond the malformed trail.
- Physical hardware, VA3, 2D, other ROM revisions, IRQ/DMA stress,
  exhaustive candidate/segmentation coverage, and NEC application tests.

## Recommendation and switch

**Recommend FEP for `JFP ON`.** The corpus showed no quality advantage for
ROM, and the speed and memory differences at selection were small or
zero. FEP keeps pending text and key arbitration in project code, opts
in to the qualified built-in dictionary configuration only, validates
candidate output, and confirms without requesting learning. ROM remains
useful for users who want its front-end keys. Its on-disk learning and
nested-DOS behavior with external files remain unqualified.

[`VAJFP.ASM`](../pc88va/VAJFP.ASM) routes `ON` to the same path as `FEP`
and updates the usage text. `ROM` remains explicit; `OFF` is unchanged.
Boot still leaves CON plain. In particular, `ON` no longer means the old
strict external-default-file ROM selection. No VAIO or AUTOEXEC change
was made. This recommendation and switch are submitted for review.

## M6 — Rebuilt switch gate

The same scratch builder and pins as [J3b.3](J3b.3-bios-backend.md#reproduce)
were used with track `j3c` and the switch source at `5341cab3` (before
amending in the gate results). The rebuilt distribution D88 SHA-256 was
`eddbfacda3753c7e0d1f344ebd9aa16aea9c019d1e03aa701cae3929996663ae`.
The packed gate `bfb56737826d01bb6e3f65d77d72f0088e9f75bc2c4d10cac2258e49155ee267`
was built from that distribution, not by reusing the M1 image. `IO.SYS`
and `AUTOEXEC.BAT` were byte-identical to M1; `JFP.COM` changed from
1,162 to 1,168 B (SHA-256
`a4bbc77e3afdb7ee5b684aa54cd3c3e979174a4035f8123bcb0ea23ec5a7fb35`).
Rebuilding at the final amended commit changes the commit ID in the
boot banner; the selector source is unchanged from the tested build.

To reproduce, set the builder's `msdos.commit` to the switch commit,
`msdos.branch` to `topic/j3c-compare`, and `msdos.track` to `j3c`. Build
in scratch. `$DIST_D88` is that output; `$M1_GATE` supplies only the
named plain regression fixtures. Assemble the monitors as in
[M5](J3c/safety.md#reproduce), including the unmodified `FEPMON.COM`.
`$REFERENCE` is the J3b.3 results tree (only `base-boot` and
`base-regression` TVRAM/screens are read as the expression of the old
plain baseline; the candidate runs below are all fresh). The counted
scripts use shorter inter-action waits than the first attempt, which
hit host wall-time limits under load. They retain the requested key
sequences and check the captures and file bytes; uncompleted early
runs are not counted.

```sh
export PYTHONPATH="$VAEG_SOURCE/tools/qa:$BUILDER_EXP:docs/J1"
python3 -B docs/J3c/pack.py "$DIST_D88" "$S/switch-gate.d88" \
  --reg-from "$M1_GATE" "$S/FEPMON.COM" "$S/ROMMON.COM" \
  "$S/FMONBYTE.COM" "$S/ROMBYTE.COM"
python3 -B docs/J3c/switch_gate.py run-enabled "$VAEG" "$ROMS" \
  "$S/switch-gate.d88" "$S/enabled" --cistat 1000:09AA --screens --wall-timeout 600
python3 -B docs/J3c/switch_gate.py run-plain "$VAEG" "$ROMS" \
  "$S/switch-gate.d88" "$S/plain" --cistat 1000:09AA --screens --wall-timeout 600
python3 -B docs/J3c/switch_gate.py report "$S/enabled" "$S/plain" "$REFERENCE"
```

### Results

**105/105 cold cases reached `exit`**, with **600 TVRAM shots**, on the
rebuilt gate. Pass counts below are grouped checks, not boot counts.
[Per-check evidence](J3c/switch-results.tsv).

| Configuration | Plain J0.3 1/5/9 | Plain J0.4 1–5 + usage | `JFP ON` (FEP) | `JFP FEP` | `JFP ROM` |
|---|---:|---:|---:|---:|---:|
| VA 640 KiB | 10/10 | 11/11 | 13/13 | 13/13 | 11/13 + 2 differences |
| VA2 256 KiB | 10/10 | 11/11 | 13/13 | 13/13 | 11/13 + 2 differences |
| VA2 640 KiB | 10/10 | 11/11 | 13/13 | 13/13 | 11/13 + 2 differences |

Each enabled column covers J3a steps 2 and 6 (seven checks), J3b.3 steps
2, 5 and 8 (five checks), and OFF with labels and plain input restored.
Unconverted and converted Return both confirmed before the second press
submitted, for every selector. The two `ROM` differences per configuration
are the scoped text-BIOS entries in the buffered and byte-API cases. ROM
met the zero-nested-DOS criterion but, as in M5, not the historical FEP
checker's stricter zero-nested-DOS **and** zero-nested-text condition.
There were no unexpected failures. No automatic activation was added.

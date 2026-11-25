# J3d — Space converts in the project FEP

In `JFP ON` or `JFP FEP`, type a reading in kana width, then press **Space**
to convert or advance, or **Shift+Space** to go back. These keys use the
same conversion routines and backend endpoint behavior as **HENKAN** and
**Shift+HENKAN**. **KETTEI** or the first **Return** confirms; Return again
submits the DOS line. With no reading, Space still inserts `20h` in either
width. Plain input is unchanged. **`JFP ROM` is unchanged**; its front end
is firmware-owned.

## Primitive captures and dispatch

[SPACEAX](J3d/SPACEAX.NAS) printed the `PrmGetK` result (`AH` scan, `AL`
internal code) and the separate `PrmSfts` status byte immediately after it.
Both VA and VA2 returned the same values, before and after the change:

| Key | PrmGetK AX | PrmSfts AL |
|---|---:|---:|
| Space | `3420` | `00` |
| Shift+Space | `3420` | `01` |
| HENKAN | `3520` | `00` |
| Shift+HENKAN | `A520` | `01` |
| KANA-held Space | `3420` | `08` |
| KANA-held Shift+Space | `3420` | `09` |
| KANA-held A (control) | `1DC1` | `08` |
| Ctrl+Space | `3420` | `20` |
| GRPH+Space | `3420` | `10` |

[`FEPKEY`](../pc88va/VAFEP.INC) checks the exact Space pair (`3420h`) only
on the pending-reading path (`FEPLEN | FEPPC` nonzero). It samples either
Shift bit (`03h`); KANA does not change dispatch. Ctrl and GRPH retain the
pending-key discard behavior. No code was added to the idle, plain or ROM
paths. Since the Space queue entry carries no modifier bit, Shift is
sampled **when VAIO consumes the key**, not when it enters the queue. If
Shift is released before VAIO polls a queued Space, the key can go forward.
HENKAN retains its distinct queued Shift+HENKAN scan.

## Gate

Japanese 2HD images, vaeg m153 (`6367e5d3`), VA and VA2 at 640 KiB.
Compared release base `46e9cb0` with application commit `b96784d`.

| Check | VA | VA2 | Observation |
|---|---|---|---|
| `JFP ON`, `nihon` and candidate keys | PASS | PASS | Space → `日本`, Space → `にほん`, Shift+Space → `日本`; same text and focus as HENKAN. Return confirms, then Return submits `ECHO`. The base did not convert on Space in project mode. |
| Endpoint parity | PASS | PASS | Shift+Space at the first candidate held on VA and wrapped to `にほん` on VA2. Eight subsequent forward taps alternated the two candidates, matching HENKAN at every tap. No new wrapping rule was added. |
| KANA-held Space/Shift+Space | PASS | PASS | Direct `ち` → `血` → `地` → `血`, matching HENKAN; KETTEI confirms. |
| `JFP FEP`, COPY CON | PASS | PASS | KETTEI + Return writes `93 FA 96 7B 0D 0A` (`日本` and CRLF), exactly as with HENKAN. |
| Idle Space, ASCII and kana widths | PASS | PASS | `ECHO A B` prints `a b`; COPY CON file contains two exact `61 20 62 0D 0A` lines, one with Space entered in each width. |
| Candidate arrows / Shift+arrows | PASS | PASS | J3c phrase plan matches base, including focus changes and confirmation. |
| Plain and ROM spot checks | PASS | PASS | Plain `ECHO A B`; ROM Space/HENKAN candidate sequence and confirmation match base. |
| Historical J3b.2 project input plans | MATCH | MATCH | Ten plans rerun unchanged against both images. All 51 captures per model match in decoded main text and system row words/pixels, except banner and free bytes; `FEPBYTE` reports PASS. Covers BS, ESC, F7, pending ZENKAKU and Ctrl-C, among others. See caveat below. |
| Historical J3b.2 plain regression | 24/24 | 24/24 | J0.3 editing, five F10 cold boots, J0.4 labels, 31 KEY slots, J2a TYPE, and CHKDSK, checked with Japanese DIR/CHKDSK wording. |
| Current J3c EDLIN plan | PASS | PASS | `E.TXT` is `93 FA 96 7B 8C EA 0D 0A 1A` (`日本語`, CRLF, EOF). Also checked on VA2 at 256 KiB. |

The historical J3b.2 project plans predate the BIOS backend and the
change to two-step Return. They are **not** a rerun of the old 52/52
assertions: e.g. their old COPY plan saves the same kana without CRLF on
both builds, and their old EDLIN plan does not save a file on either.
The current COPY and EDLIN checks above verify those file paths with
current confirmation semantics.

MASM listing `RESEND`: `25EAh` → `25FEh`, **+20 resident VAIO bytes**.
CHKDSK reports **524,032 → 524,016 B free** on both models (plain and
project). `IO.SYS` remains 28,797 B in the Japanese image.

**NOT RUN:** original J3b.2 checker with stub-era expectations, full
historical ROM matrix, external dictionaries, other readings at the
candidate endpoints, modifier-release stress, real hardware, VA3, or 2D.

## Reproduce

Build both commits with FreeDOS-88VA/freedos `main` at `1ed657b96f31`,
using the pinned emu2, updating `msdos.commit` in the builder lock for
each build; use track `j3d` for the application commit. Run
`python3 -I experiments/msdos4-va/build.py --output <scratch-output>`
(default Japanese messages). Both VAIO listings have `CISTAT=0A73h`.
Keep all disks and emulator runs in scratch. `$BASE` and `$AFTER` are the
built D88s, `$REG` a project image with `LABELCHK.COM`, `LONG.TXT`, and
`CONKEY.COM`, `$S` scratch, and `$VAEG` / `$ROMS` the emulator and ROM set.
Set `PYTHONPATH` to the builder experiment directory, vaeg `tools/qa`,
and `docs/J1`.

```sh
nasm -f bin docs/J3d/SPACEAX.NAS -o "$S/SPACEAX.COM"
nasm -f bin docs/J3b.2/FEPBYTE.NAS -o "$S/FEPBYTE.COM"
for which in base after; do
  case $which in base) dist=$BASE ;; after) dist=$AFTER ;; esac
  python3 -B docs/J3c/pack.py "$dist" "$S/$which-gate.d88" \
    --reg-from "$REG" "$S/SPACEAX.COM" "$S/FEPBYTE.COM"
  python3 -B docs/J3d/gate.py "$VAEG" "$ROMS" "$S/$which-gate.d88" \
    "$S/$which-gate" --cistat 1000:0A73 --wall-timeout 600
  AFTER_CISTAT=1000:0A73 python3 -B docs/J3b.2/run.py "$VAEG" "$ROMS" \
    "$S/$which-gate.d88" "$S/$which-old"
done
python3 -B docs/J3d/gate.py check "$S/base-gate" "$S/after-gate" \
  "$S/base-old" "$S/after-old"
python3 -B docs/J3d/endpoints.py "$VAEG" "$ROMS" "$S/after-gate.d88" \
  "$S/endpoints" --cistat 1000:0A73 --wall-timeout 600
python3 -B docs/J3d/endpoints.py check "$S/endpoints"
python3 -B docs/J3c/run.py "$VAEG" "$ROMS" "$S/after-gate.d88" \
  "$S/editor" --mode FEP --case edlin --cistat 1000:0A73 --wall-timeout 600
```

For the plain regression, prepare the candidate image with the
[J2a fixtures](J2a-sjis-output.md#reproduce) and run the two `wrap-run.py`
commands in [J3b.2](J3b.2-project-kana-input.md#reproduce), setting both
CISTAT variables to `1000:0A73`. Check with
`python3 -B docs/J3d/gate.py check-plain "$S/plain" "$S/extra"`.

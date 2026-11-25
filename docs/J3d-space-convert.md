# J3d — Space converts in the project FEP

In `JFP ON` or `JFP FEP`, type a reading in kana width, then press **Space**
to convert or advance, just like **HENKAN**. Modifiers do not change what
Space does while composing; use **Shift+HENKAN** to go back.
**KETTEI** or the first **Return** confirms; Return again submits the DOS
line. With no reading, Space still inserts `20h` in either width. Plain input is unchanged. **`JFP ROM` is unchanged**; its front end
is firmware-owned.

## Primitive captures and dispatch

[SPACEAX](J3d/SPACEAX.NAS) printed the `PrmGetK` result (`AH` scan, `AL`
internal code) and the separate `PrmSfts` status byte immediately after it.
Both VA and VA2 returned the same values:

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

The PC-88VA Technical Manual (`603KEYB` §6.3.4) specifies only the
scan/internal-code pair for `PrmGetK`; `PrmSnsK` peeks at that pair and
returns a carry flag for queue availability. The key table lists `34h/20h`
for Space in every column, including either Shift, Ctrl, GRPH and KANA.
The separate `PrmSfts` call reports live modifier state, not queue metadata.
The manual's keyboard interrupt trap can receive shift state, but that is
not a return value of either queue function.

The [delayed-poll capture](J3d/delayed.py) recorded both primitive returns
at VAIO's call sites: Space was `3420h` in both, with no modifier-dependent
change in the other registers or flags across the single-Space cases on
either model. Shift+HENKAN still returned `A520h` after Shift was released.

[`FEPKEY`](../pc88va/VAFEP.INC) checks the exact Space pair (`3420h`) only
on the pending-reading path (`FEPLEN | FEPPC` nonzero). It does not sample
modifiers: Shift/Ctrl/GRPH+Space are indistinguishable from Space in the
queue and always take the forward path. The idle, plain and ROM paths are
unchanged.

## Gate

Japanese 2HD images, vaeg m153 (`6367e5d3`), VA and VA2 at 640 KiB.
Built the fixed VAIO from `9d2754c`. The project-mode check reuses the
J3d captures of release base `46e9cb0`; the plain regression reruns both
builds. Use the same fixture files on both images for the J3b.2 CHKDSK
capture; `POLL.COM` is needed only for the delayed-poll image.

| Check | VA | VA2 | Observation |
|---|---|---|---|
| `JFP ON`, `nihon` and candidate keys | PASS | PASS | Space → `日本`, Space → `にほん`, Shift+HENKAN → `日本`; same text and focus as HENKAN for the forward taps. Return confirms, then Return submits `ECHO`. The base did not convert on Space in project mode. |
| Endpoint parity | PASS | PASS | Shift+HENKAN at the first candidate held on VA and wrapped to `にほん` on VA2. Eight subsequent Space taps alternated the two candidates, matching HENKAN at every tap. No new wrapping rule was added. |
| KANA-held Space | PASS | PASS | Direct `ち`: VA `血` → `地` → `血`; VA2 `値` → `地` → `値`. Two Spaces and Shift+HENKAN match the HENKAN path; KETTEI confirms. |
| Delayed CON polling | PASS | PASS | Paused at `幹事`: plain Space, Shift held/released/pressed late, and Ctrl or GRPH held/released all advanced to `監事`. Both typed-ahead pairs (Space then Shift+Space with Shift released before resume, and two plain Spaces with Shift pressed late) advanced through `監事` to `莞爾`, matching two HENKAN taps. Queued Shift+HENKAN still went back to `漢字` after release. |
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

MASM listing `RESEND`: `25EAh` → `25EFh`, **+5 resident VAIO bytes** vs.
release base, **−15 bytes** vs. the modifier-sampling J3d build (`25FEh`).
CHKDSK reports **524,032 B free** on both models (plain and project), the
same as release base. `IO.SYS` remains 28,797 B in the Japanese image.

**NOT RUN:** original J3b.2 checker with stub-era expectations, full
historical ROM matrix, external dictionaries, other readings at the
candidate endpoints, native host auto-repeat, real hardware, VA3, or 2D.

## Reproduce

Build both commits with FreeDOS-88VA/freedos `main` at `1ed657b96f31`,
using the pinned emu2, updating `msdos.commit` in the builder lock for
each build; use track `j3d` for the fixed commit. Run
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
nasm -f bin docs/J3d/POLL.NAS -o "$S/POLL.COM"
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
python3 -B docs/J3d/gate.py check-edlin "$S/editor"
python3 -B docs/J3c/pack.py "$AFTER" "$S/delayed.d88" "$S/POLL.COM"
python3 -B docs/J3d/delayed.py "$VAEG" "$ROMS" "$S/delayed.d88" \
  "$S/delayed" --cistat 1000:0A73 --wall-timeout 600
python3 -B docs/J3d/delayed.py check "$S/delayed"
```

For the plain regression, extract `LABELCHK.COM`, `LONG.TXT` and
`CONKEY.COM` from `$REG` with the builder's `readfile.py` into a scratch
fixture directory. Prepare the candidate image with the
[J2a fixtures](J2a-sjis-output.md#reproduce), passing that directory to
`--regressions`. Run the two `wrap-run.py` commands in
[J3b.2](J3b.2-project-kana-input.md#reproduce) with the distribution D88s
and the prepared candidate image as `REG_D88`, setting both CISTAT
variables to `1000:0A73`. Check with
`python3 -B docs/J3d/gate.py check-plain "$S/plain" "$S/extra"`.

## J3d.2 — Alt+grave toggles project width

In vaeg's **US** layout, press **left Alt + grave** in `JFP ON` or
`JFP FEP` to switch between ASCII and kana width. Like **ZENKAKU**, it
inserts nothing and is ignored while a reading is pending. Plain CON is
unchanged. **`JFP ROM` still needs ZENKAKU**; the shortcut does not change
firmware-owned conversion.

### Keyboard evidence and dispatch

With vaeg m153, SDL key events went through the US host keymap: Left Alt
sent GRPH, and the grave key sent synthetic left Shift + scan `0Ch`.
On **real hardware**, the corresponding chord is **GRPH+SHIFT+`^`**
(scan `0Ch`, vaeg's `CARET`), which also selects this path in `JFP ON`.
The actual `@` key is scan `1Ah` and is not the shortcut. Before this
change scan `0Ch` with GRPH+SHIFT produced the graphic byte `8Bh`, which
can be treated as a Shift-JIS lead rather than rendered on its own in DOS.

The pre-change `FEPKEY` entry capture on both VA and VA2 was `0C8Bh` for
US Alt+grave. `SPACEAX` measured the primitive pair and **live** status;
a separate `UsrTrap` probe confirmed the **key-event** status in `CL`:

| Keys | Primitive AX | Live `PrmSfts` | IRQ `CL` |
|---|---:|---:|---:|
| US Left Alt+grave | `0C8B` | `10` (VA), `11` (VA2) in the sampled run | `11` |
| GRPH+Shift+scan `0Ch`, held | `0C8B` | `11` | `11` |
| GRPH+scan `0Ch`, no Shift | `0C8B` | `10` | `10` |
| Shift+scan `0Ch`, no GRPH (also US grave) | `0C5E` | `01` | `01` |
| GRPH+Q | `109C` | `10` | `10` |
| US Shift+grave | `1A7E` | `01` | `01` |

`FEPKEY` cannot distinguish the first three rows from their queued pair
alone, and sampling live Shift would miss the chord after release. VAIO
uses the documented keyboard **user trap** only in project mode. The
trap substitutes the ZENKAKU pair (`7B00h`) for `0C8Bh` with GRPH and either
Shift (not Ctrl), keeping the BIOS queue flags. `FEPKEY` makes the width
decision in queue order; the interrupt callback does not run the FEP.
A foreground probe with the documented pop-up trap did not return keyboard
input on VA even with a no-op callback, so this does not use a pop-up trap.

If another program already owns the active user trap, VAIO leaves it in
place and ZENKAKU remains available. `JFP OFF` removes VAIO's trap only
if it still owns the slot. The separate K1 GRPH filter would not affect
this shortcut: it runs in the ordinary VAIO decoder after `FEPKEY`, and
only unmatched graphic bytes would reach it.

### J3d.2 gate

Japanese 2HD, vaeg m153 (`6367e5d3`), VA and VA2 at 640 KiB. Same builder
as above, using `f4e53a9`; candidate `CISTAT=0A79h`. Host-layout tests fed
SDL key down/up events to vaeg, not guest scan codes. The JIS control fed
SDL `LANG5` through the JIS keymap.

| Check | VA and VA2 |
|---|---|
| `JFP ON` and `JFP FEP` | PASS. First Alt+grave leaves `ECHO` unchanged and `nihon` goes to the reading row. Alt+grave during the reading leaves it unchanged. KETTEI confirms `にほん`; the next Alt+grave inserts nothing and `a` goes straight to DOS. |
| Delayed poll (`POLL.COM`) | PASS. With both modifiers already up, Alt+grave still arrives at `FEPKEY` as `7B00h`. GRPH+scan `0Ch` followed by late Shift stays `0C8Bh`. |
| Neighbor keys and JIS ZENKAKU | PASS. GRPH+scan `0Ch` without Shift and GRPH+Q match the baseline. JIS ZENKAKU passes the same width, pending, and no-insertion checks. |
| Bare US grave and tilde | **Unchanged; literal grave gate not met.** These BIOSes produce `^~` from the two US host keys, both before and after the change. Bare host grave arrives as `5Eh`, not `60h`; this change does not remap it. |
| Plain and `JFP ROM` | PASS. Alt+grave still yields the old input (no width change); the existing ROM Space/HENKAN/confirm spot check also matches. OFF restores plain behavior and a new ON restores the shortcut. |
| User-trap ownership | PASS. A test TSR that replaces the callback survives OFF, and a subsequent ON leaves the TSR's active callback alone; ZENKAKU still works. |
| J3d SPACE and J3b.2 regression | PASS. J3d prompt, COPY, idle, endpoints, phrase/arrow, and delayed-poll checks passed. J3b.2 historical project plans: 51 matching captures per model apart from banner and free memory, including `FEPBYTE` PASS (see historical-plan caveat above). Plain 24/24 per model. Current EDLIN test saved the exact expected bytes on both models and on VA2 at 256 KiB. |

MASM listing `RESEND`: `25EFh` → `264Fh`, **+96 resident VAIO bytes**.
CHKDSK free memory: **524,032 → 523,936 B** on both models; `IO.SYS`
remains **28,797 B**. The listed VAIO object matched the distribution
object byte for byte.

**NOT RUN:** physical hardware or native Windows input, host auto-repeat,
exhaustive modifier combinations, VA3, 2D, external dictionaries, or the
full historical ROM matrix. K1 was inspected, not built or tested together
with this change.

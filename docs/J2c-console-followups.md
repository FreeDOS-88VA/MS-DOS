# J2c — CON follow-ups

Baseline: `release/msdos-va` at `55cf974`, including [J2b](J2b-escape-sequences.md).
Reference: NEC MS-DOS 3.3D system disk 1 (SHA-256 `0879cb724de42da021f6adeab447597fcd2553efe421440fb63ae02bfd69907f`) in NP2kai SDL2 `5939e0c6d5985c4c08fc70f289a83290e5d3e6f7`. VA and VA2: vaeg PR #82, `Rel.20261121 (m153, 6367e5d3)`, SHA-256 `a3ab65a03eac9fd2abccca3d51b8e464266a4b6141b9d5132b5b667495655906`.

## 1. Pending wrap

`WRAPTEST` sent identical streams through AH=40h and byte-by-byte AH=02h. NEC leaves the **visible** cursor at column 80 after printing there, but the **logical** position reported by `CSI 6n` is column **81**. It is not the same state as locating to column 80. Rows and columns below are one-based.

| NEC observation | VAIO behavior |
|---|---|
| Printing `T` in the bottom-right cell leaves the top row untouched with labels on (24 rows) or off (25). The next `X` wraps first; in the 24-row fixture it scrolls exactly once. | Keep the physical cursor at 80 and represent logical 81 separately. Advance with CR + `Index` only when needed. |
| `CR` cancels pending and goes to column 1 on the same row. `LF` advances one row **still pending**; the next glyph therefore starts another row. | CR clears the bit; LF calls `Index` without changing it. |
| `BS` and `CSI 1D` back up from logical 81 to physical 80; `X` overwrites `T`. `CSI 1C` leaves a pending cursor at 81. `CSI 1A/B` change the row, not the pending column. `ESC D/M` also preserve logical 81. | The first left step consumes the bit; vertical motion and rightward clamping preserve it. |
| An absolute locate to the *same* row and column 80 clears pending. Save/hop/restore restores logical 81. BEL, SGR, and `CSI 6n` do not consume it. | Save/restore includes the bit; SGR and reports do not move the cursor. |
| `K0` and `J0` leave the `T` at logical 81 intact. | `K0` has no cells left to erase; `J0` starts at the first cell on the next row if there is one. |
| Hiding and showing labels at the tested rows 13/14 retain logical 81. | Preserve pending when restoring the cursor after the split change. |
| A kanji beginning at column 80 goes to the next row, whether column 80 was empty or just filled. In the latter case `T` survives. A kanji **ending** at column 80 occupies columns 79 and 80 and leaves logical 81. | Retain J2a's `FEh` special space only for the first case; do not touch `T` in the second. A pair ending at the edge defers the next wrap, like a single-byte character. |

**ROM choice.** `604TEXT.TXT` §6.4.3 functions 1–3, 7, 12, 27 and 36: leave `WRAP` on but clear `VSCL` in both main `Spltscn` descriptors; keep the label split unchanged. Use `Askloc` to detect an edge write and `Locate` to put the physical cursor back after it. Use explicit `Index` for scroll/line feed. An earlier no-word-wrap build correctly held a single cell but both `Chuput` and `Putstr` clipped the pair starting in column 79; it was not accepted. There are no direct TVRAM writes. The main split now has auto-scroll disabled for **direct INT 83h output as well**. DOS CON explicitly scrolls; behavior of arbitrary applications bypassing CON and depending on the old ROM auto-scroll setting is not asserted.

### VA / VA2 gate results

Side-by-side NEC / VA / VA2: AH=40h [controls and kanji](J2c/block-controls.png), [bottom edge](J2c/block-bottom.png); AH=02h [controls and kanji](J2c/split-controls.png), [bottom edge](J2c/split-bottom.png); [TYPE and DIR /W](J2c/type-dir.png). Cursor blink rendering is ROM-specific; VA cursor position was checked independently from the TSP sprite. TYPE showed the same two long-line breaks and no spurious blank row after the exact 80-byte line. Both shells listed the same 11 selected names in rows of 5, 5 and 1.

| Check | VA | VA2 |
|---|---:|---:|
| J2b page 01 (including cursor), AH=40h / AH=02h | 1/1 / 1/1 | 1/1 / 1/1 |
| WRAPTEST reference pages, AH=40h / AH=02h | 6/6 / 6/6 | 6/6 / 6/6 |
| TYPE exact/long lines and DIR /W | 2/2 | 2/2 |
| J2b reference pages, AH=40h / AH=02h | 19/25 / 19/25 | 19/25 / 19/25 |
| J2a gates 1–6 (including the column-80 wrap and `FEh`) | 7/9 | 7/9 |
| J0.4 steps 1–5, expecting J2b `ESC[2J` clear+home | 10/10 | 10/10 |
| J0.3 steps 1, 5, 9 | 8/8 | 8/8 |
| KEY (one check over 31 slots) and CHKDSK before/after | 1/1 + 2/2 | 1/1 + 2/2 |

The 19/25 count includes page 01, the new match. The other 18 are the previously matching pages: the baseline/new grids were identical on all 26 captures per model/method, and the J2b attribute, report, label, cursor-enable, and half-kanji assertions passed. Pages 10–14 and 23 retain the J2b differences. The two known J2a NEC differences with malformed pending leads remain; all driver-side J2a assertions passed. The old J0.4 expectation that `2J` does not home still gives 9/10. See [check output](J2c/va-checks.txt).

Both models: CHKDSK **529,456 → 529,168 B free** of 655,360 B (**−288 B**). IO.SYS **20,698 → 20,970 B** (**+272 B**), still 21 boot sectors. Only IO.SYS changed in the locked distribution build. [Build record](J2c/build.txt).

**NOT RUN:** physical hardware, 2D boots, arbitrary direct-ROM output with auto-scroll off, bottom-row pending LF, pending HT/raw controls beyond those shown, label show with logical column 81 on row 25 verified in isolation, audible BEL, and throughput benchmarking.

### Reproduce

Build the two revisions in [build.txt](J2c/build.txt) using the scratch builder and locked dependencies from [J2b](J2b-escape-sequences.md#reproduce). Use the same `$REG`, `SJISOUT.COM`, `J1DBCS.COM`, `ESCPROBE.COM` and `sjis-media.py` commands to make `$S/j2btest.d88` from `$AFTER`. With `$S` outside the repository:

```sh
nasm -f bin tests/pc88va/WRAPTEST.NAS -o "$S/WRAPTEST.COM"
PYTHONPATH="$BUILDER_EXP" python3 -B tests/pc88va/wrap-media.py va \
  "$S/j2btest.d88" "$S/test.d88" "$S/WRAPTEST.COM"
PYTHONPATH="$VAEG_SOURCE/tools/qa" BASE_CISTAT=1000:06CD AFTER_CISTAT=1000:06CF \
  python3 -B tests/pc88va/wrap-run.py "$VAEG" "$VA_ROMS" \
  "$BASE" "$AFTER" "$S/test.d88" "$S/runs"
export PYTHONPATH="$BUILDER_EXP"
python3 -B tests/pc88va/wrap-check.py "$S/runs"
python3 -B tests/pc88va/esc-check.py "$S/runs"
python3 -B tests/pc88va/sjis-check.py "$S/runs" --nec-clear --expected-memory 529456 529168
```

For the baseline J2b grid comparison, make the J2b fixture disk from `$BASE`, and use `esc-run.py` with both CISTAT offsets `1000:06CD`, both distribution disk arguments `$BASE`, and the filters `esc-block esc-split`. Compare the character words returned by `rows` from `sjis-check.py` for corresponding captures. On NP2kai, prepare the reference disk copy with `wrap-media.py nec ... --escape-probe "$S/ESCPROBE.COM"`. Use [J2b's boot procedure](J2b-escape-sequences.md#reproduce). Run `WRAPTEST` and `WRAPTEST B`, capturing before each of six Space presses and at `WRAPTEST DONE`; capture page 01 of `ESCPROBE` and `ESCPROBE B`. At the prompt run `TYPE EDGELONG.TXT` and `DIR /W Q*.BIN` (keypad multiply for `*` in the SDL keyboard mapping).

## 2. Underline and blink

NEC page 10 shows normal underline (`4`), visible/blank phases for blink (`5`), red underline when `31;4` are in the same SGR, and white underline after a *separate* `4m`. `7;31;4` and `4;31;7` both draw reverse red with underline. Erasing under reverse still clears to black. The test also checks all eight foreground and reversed colors and the invisible `16;31` case.

**Use mode 1, not mode 0 or 2.** `604TEXT.TXT` §6.4.3 functions 4–6 and 27: mode 0 gives independent per-cell FG/BG but no effects. Mode 2 gives effects but both colors come from the split. Mode 1 gives one per-cell color plus `HL`, `RV`, `BL` and `SE`. Although the mode-1 diagram in `Setatr` repeats `CB`, the `Setcolor` text and the BNN Technical Manual §4.2 explicitly put **foreground** in each cell and **background** in the split. This is enough for the NEC scheme in the fixture: color-on-black or black-on-color, selected by `RV`, not two independent user colors. `HL` draws at the final raster with the text BIOS defaults. The code keeps the system split as-is, leaves the main background black, and sets the current attr once per SGR. Direct BIOS clients relying on the old main mode-0 attribute encoding now see mode 1; no raw mode-0 app compatibility is claimed.

Page 10 evidence: [AH=40h](J2c/block-attributes.png), [AH=02h](J2c/split-attributes.png), with visible and blank blink phases. Underline raster and blink timing need not match the PC-98 hardware pixel for pixel. Other SGR combinations not in the fixture (including simultaneous underline and blink) and physical hardware: **NOT RUN**.

**VA and VA2: 1/1 page (10) through AH=40h and 1/1 through AH=02h on each model.** This brings the J2b parity count to **20/25 per method on each model**; pages 11–14 and 23 remain unmatched. Re-ran all 66 Part 1 scenarios; the remaining Part 1 gate counts stayed the same. Use the same commands above with the Part 2 revision in [build.txt](J2c/build.txt), change `--expected-memory` to `529456 529152`, and add `python3 -B tests/pc88va/attr-check.py "$S/runs"`. NP2kai: sample page 10 of both `ESCPROBE` runs until `05 TEST` appears both visible and blank. [Check output](J2c/va-checks-part2.txt).

Additional cost (both models): **16 B resident** and **32 B in IO.SYS**. Relative to `55cf974`, CHKDSK is **529,456 → 529,152 B free (−304 B)** and IO.SYS is **20,698 → 21,002 B (+304 B)**, still 21 sectors.

## 3. Graph mode

On NEC, `ESC ) 3` renders `95 5C` as two ANK characters and shows `g` at system-line column 2. `ESC ) 0` clears the indicator and re-enables kanji. Hiding and restoring labels while in graph mode restores `g`; clearing graph mode while hidden leaves `g` off when labels return.

**Use the VA font and the existing label split.** `GRAPHROM` compared NEC's graph-mode `80h–9Fh` / `E0h–FFh` table to direct VA `Litout` with an ANK argument (`604TEXT.TXT` §6.4.3 functions 1–2): the two VA models have the needed glyphs. The CON parser sends high bytes as ANK in graph mode, bypassing J2a's lead buffer. The mark uses `Chcsn`, `Locate`, and `Putstr` with a fixed attribute in the system split's reserved left margin; then the main cursor is restored. The ROM still manages function labels. No font data was added or changed.

Side-by-side: J2b pages 13–14 [AH=40h](J2c/block-graph.png), [AH=02h](J2c/split-graph.png), and [the high-byte table and label transitions](J2c/graph-labels.png). For the VA tests the raw 64-code/delimiter grid and glyph pixels were compared to the same model's direct BIOS output. Shift press/release keeps the mark while updating labels. Active-graph `KEY` reassignment, interactions with raw callers that replace splits, and physical hardware: **NOT RUN**.

**VA and VA2: 2/2 graph pages through each DOS write method, plus 64/64 literal codes per model.** The resulting parity count is **22/25 through AH=40h and 22/25 through AH=02h on each model**. Only pages 11–12 (20-row mode) and 23 (known malformed-sequence differences) remain unmatched. The prior gate counts stayed the same; the raw J2b grids changed only on pages 13–14. [Check output](J2c/va-checks-part3.txt).

Reproduce as before with the Part 3 revision from [build.txt](J2c/build.txt). Assemble `GRAPHROM.NAS`, add `--graph-probe "$S/GRAPHROM.COM"` to `wrap-media.py` and use `graph-run.py` in place of `wrap-run.py` with `AFTER_CISTAT=1000:06D0`. Pass `--graph` to `esc-check.py`, use `--expected-memory 529456 529040` for `sjis-check.py`, and run `graph-check.py` in addition to the wrap/attr checkers. On NEC run `GRAPHROM N` with Space between pages and capture pages 13–14 of each ESCPROBE run.

Additional cost: **112 B resident** per model and **96 B in IO.SYS**. Relative to `55cf974`, final CHKDSK is **529,456 → 529,040 B free (−416 B)** on both models and IO.SYS is **20,698 → 21,098 B (+400 B)**, still 21 sectors.

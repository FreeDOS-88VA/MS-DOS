# J2d — direct text BIOS output and CON row modes

Baseline: `release/msdos-va` at `0e4738d`. VA emulation: vaeg m153, VA and VA2.

## 1. Direct INT 83h writers

Restore `VSCL` on the main split. CON still defers its right-edge wrap:
away from the bottom row it can undo the BIOS cursor advance with `Locate`;
at the bottom it temporarily installs the same split with `VSCL` clear. The
write, including a split kanji or the `FEh` pre-wrap filler, still goes through
the text BIOS with word wrap enabled. Both split changes restore the current
attribute and cursor. The system-row geometry and backing storage do not change.
See `604TEXT.TXT` §6.4.3 functions 1–3, 7, 27, 36 and 37.

In the baseline, `ROMWRITE` on VA and VA2 left lines 01–23 intact and only
replaced the last row with line 32, for both `Putstr` and `Chuput`. The probe
uses DOS only to wait and exit. Source audit: `VAJFP`, `VAKEY`, `VAFORMAT` and
`VADCOPY` do not issue INT 83h directly; the resident FEP uses it on the
system split, and COMMAND's `CLS` and the boot error paths also use it.
This is not an audit of third-party DOS binaries.

[ROMWRITE before/after](J2d/romwrite.png) and [check output](J2d/va-checks.txt):

| Part 1 gate | VA | VA2 |
|---|---|---|
| Direct Putstr and Chuput | Both show lines 10–32 and a blank final row | Same |
| Long TYPE and DIR | 40-line file and 40-entry directory scrolled to their ends | Same |
| Labels | Unchanged pixels in direct writer, long TYPE/DIR, and WRAPTEST captures | Same |
| J2c pending wrap | Page 01 and WRAPTEST 6/6 for each write method; exact-edge TYPE and DIR /W pass | Same |
| J2c underline/blink, graph | Page 10 and pages 13–14 pass for both methods; 64/64 graph glyphs match direct Litout | Same |

The temporary split change is limited to CON writes at the bottom edge. No
arbitrary raw BIOS layout changes, custom margins or concurrent BIOS callers
were tested. There is no ROM hook, private workspace dependency or TVRAM
write in this path.

## 2. `CSI >3h` and `CSI >3l`

Track the physical row count separately from label visibility. `Crtctl`
changes the raster height and `Spltscn` applies the corresponding height to
the main split (all rows if labels are hidden, otherwise all but one). Both
layouts use the original 25-row backing buffer and separate system-row buffer.
Restore the current attribute and CON cursor visibility, refresh labels/graph
on the system split without changing key definitions, then clear and home the
main split. A rejected split attempts to restore the previous CRT setup,
attribute and position rather than clearing. Re-selecting the current row
mode also clears and homes. The shared last-row calculation governs absolute
addresses, pending-wrap erase and edge writes, line edits and label toggles.
The ROM continues handling scrolling within the installed split. See
`604TEXT.TXT` §6.4.3 functions 27, 34–37 and 43, and the
[J2c BIOS probe](J2c-console-followups.md#4-20-row-mode--optional-deferred).

| Part 2 gate | VA | VA2 |
|---|---|---|
| J2b pages 11–12, AH=40h and AH=02h | 2/2 each | 2/2 each |
| J2b parity against saved NEC reference | 24/25 each method | 24/25 each method |
| 20 rows, then back to 25 | Both pass | Both pass |
| J2c regression checks and Part 1 scroll checks | Pass | Pass |

Pages 11–12 were compared to the saved NEC 3.3D / NP2kai captures from J2b:
[AH=40h](J2d/pages-block.png), [AH=02h](J2d/pages-split.png). Both VA models
show only `H`/`L` at (1,1) and `R` at (4,60), with the cursor at (4,61) and
labels present. VA character grids outside pages 11–12 are unchanged between
the two parts. Page 23 remains the [recorded malformed-sequence difference](J2b-escape-sequences.md).

In 20 and 25 rows, `ROWSMODE` addressed the bottom with labels shown and
hidden, checked the full `CSI 6n` response at column 81 (rows 19/20 and
24/25), checked the red right-edge cell before scrolling, then verified one
scroll on the next character, label hide/show, graph mark, cursor disable,
and `CSI 2J` clear+home. The shell then ran long TYPE, long DIR, CLS,
`KEY F1 echo KEY-OK\r` followed by F1, and `JFP ON` with an in-progress
system-row reading followed by committed `にほんご`. These were repeated after
returning to 25 rows. See [captures](J2d/row-interactions.png) and
[checks](J2d/va-checks.txt).

**NOT RUN:** fresh NEC guest execution (used existing J2b captures), physical
hardware, 2D boots, third-party direct writers, timing/throughput, forced BIOS
error/rollback, switching CRT modes during live composition, or a separate
matrix for JFP ROM fallback.

## Build and memory

MASM 5.10 / LINK via emu2 `9d8698d06e67359bc8b230c2d19d5b1503e60819`,
using an incremental relink, not a clean distribution build. The base test
image uses the J3b.5 `ecfc8b5` distribution; reassembling and relinking the
`0e4738d` VAIO produced byte-identical IO.SYS. Part 1 replaced IO.SYS;
Part 2 also rebuilt JFP.COM from the current branch sources for the JFP gate.
Emulator: vaeg `Rel.20261121 (m153, 6367e5d3)`.

| | Base | Part 1 | Part 2 |
|---|---:|---:|---:|
| IO.SYS bytes | 28,202 | 28,202 | 28,202 |
| RESEND (listing) | `233Fh` | `23A5h` | `244Ch` |
| CHKDSK conventional bytes free, VA and VA2 | 524,800 | 524,688 | 524,528 |

Resident cost: **112 B** for Part 1 and **160 B** more for Part 2 (**272 B**
total). MASM reported no warnings or severe errors for either VAIO build.

## Reproduce

Use the scratch builder and [J2c fixture procedure](J2c-console-followups.md#reproduce)
with the base and corresponding part builds. Assemble `ROMWRITE.ASM` with MASM
and LINK, then convert the EXE to a COM image at origin `100h` (the builder's
`mz_image`). Assemble `ROWSMODE.NAS` with `nasm -f bin`. Add
`--rom-write "$S/ROMWRITE.COM"` and, for Part 2, `--rows-mode "$S/ROWSMODE.COM"`
to `wrap-media.py`. Use `j2d-run.py` instead of `graph-run.py`, with both CISTAT
offsets `1000:0A3D` for the tested builds. To run only the direct probe, pass
`romwrite` as the final scenario filter; to test the 20/25-row interactions,
pass `rows-mode`. For Part 1, use the runner at the Part 1 revision or omit
`rows-mode` via the scenario filters. Use the J2c checkers, adding
`--rows-mode` to `esc-check.py` for Part 2, and run `j2d-check.py "$RUNS"`
(with `--rows "$RUNS"` for Part 2). All guest images, build products and
captures other than the curated evidence stay in scratch.

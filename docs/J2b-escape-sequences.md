# J2b — NEC CON escape sequences and control codes

**Partial gate on both VA and VA2:** 18/25 reference pages via AH=40h and 18/25 via AH=02h on each model. Cursor addressing, erasing, line editing/scrolling, cursor reports, and the four half-kanji boundary cases work. The full NEC parity gate is **not met**: 20-row and graph modes, underline/blink, three malformed-stream outcomes, and the post-print cursor at the right edge still differ. Conventional memory cost: **896 bytes per model**.

Reference: NP2kai SDL2 `5939e0c6d5985c4c08fc70f289a83290e5d3e6f7`, NEC MS-DOS 3.3D system disk 1 ([guest VER](J2b/nec-ver.png)). VA and VA2: vaeg PR [#82](https://github.com/nakatamaho/vaeg/pull/82), `Rel.20261121 (m153, 6367e5d3)`, SHA-256 `a3ab65a03eac9fd2abccca3d51b8e464266a4b6141b9d5132b5b667495655906`. The NEC behavior was probed before changing VAIO; the evidence below reruns the final [`ESCPROBE.COM`](../tests/pc88va/ESCPROBE.NAS) on all three through DOS CON. Page numbers are the capture headers, not the titles inside the guest. Row and column numbers are one-based.

| Captures | AH=40h | AH=02h, one call per byte |
|---|---|---|
| 01–03: position, movement, save/restore, report | [NEC / VA / VA2](J2b/block-cursor.png) | [NEC / VA / VA2](J2b/split-cursor.png) |
| 04–09: erase | [NEC / VA / VA2](J2b/block-erase.png) | [NEC / VA / VA2](J2b/split-erase.png) |
| 10–14: attributes and modes | [NEC / VA / VA2](J2b/block-attr-modes.png) | [NEC / VA / VA2](J2b/split-attr-modes.png) |
| 15–21: insert/delete, scroll, controls | [NEC / VA / VA2](J2b/block-scroll-controls.png) | [NEC / VA / VA2](J2b/split-scroll-controls.png) |
| 22–26: kanji, parser recovery, hidden labels, completion | [NEC / VA / VA2](J2b/block-kanji-recovery-labels.png) | [NEC / VA / VA2](J2b/split-kanji-recovery-labels.png) |

## NEC behavior and VA results

`CSI` denotes `ESC [`. Except where noted, the observed VA and VA2 results are the same as NEC. Cursor effects are measured by a marker written at the affected position, the captured cursor when its blink phase makes it visible, or the bytes returned by `CSI 6n`. A marker itself advances the cursor.

| Item | NEC 3.3D observation | VA / VA2 result |
|---|---|---|
| `CSI r;cH`, `CSI r;cf` (01) | One-based absolute row/column. `3;10H` and `4;12f` land on the specified cells. Bare `H` homes; `0;0H` also homes; `;74H` goes to row 1, column 74. `5H` leaves the cursor unchanged. `99;11H` clamps to row 24, `9;99f` to column 80. | Same marker positions via `Locate`. `f` uses the same handler as `H`; bare/partial `f` was not separately probed. |
| `CSI nA / nB / nC / nD` (02) | Move up/down/right/left in cells, without scrolling. Omitted `A`, `C`, `D` and zero `A`/`B` move one. Counts 2, 3 and 4 move that many. A count of 99 clamps to the respective edge, retaining the other coordinate. | Same; `Goup`, `Godown`, `Goright`, `Goleft`. |
| `ESC =` row col (01) | Two bytes encoded as zero-based coordinate + `20h`, row first. `(14+20h,21+20h)` goes to (15,22); tested oversized row/column clamp to 24/80. After printing `T` in column 80, NEC still has the cursor on `T`. | Same addressing; **after printing** the VA ROM immediately wraps the cursor to (12,1) instead of waiting at (11,80). This is normal VA ROM output behavior, not a difference in where `ESC =` puts `T`. |
| `CSI s / u` (03) | Save, then restore position even after another locate. Marker `S` lands at saved (3,7). | Same via `Askloc`/`Locate`. |
| `CSI 6n` (03) | Nonblocking reads through AH=06h return `ESC[12;34R` and `ESC[02;07R` at (12,34) and (2,7); two decimal digits each, no echo. | Same exact bytes, including leading zeroes. One unread response is kept in a resident queue; a second request while it is unread is not queued. NEC queue depth and VA queue-full parity **NOT RUN**. |
| `CSI K / 0K / 1K / 2K` (04) | Erase cursor to end, cursor to start, or whole line. Cursor stays in place. `3K` has no effect. | Same via `Eralin`; half-kanji handling below. |
| `CSI J / 0J / 1J` (05–07) | Erase from cursor to end of text area, or to start for `1J`, without moving the cursor or erasing the label row. | Same via `Erascn`; `3J` reference **NOT RUN**. |
| `CSI 2J`, `ESC *` (08–09) | Clear the text area **and home**; the label row remains. | Same. `2J` now homes without a separate `CSI H`, unlike J0.4. COMMAND's CLS and redirected bytes are unchanged. |
| `CSI m`, `0m`, `1m` (10) | Bare `m` and `0m` reset to white on black. `1m` looks normal and resets prior red in this probe; separate SGRs start from normal, not the previous SGR. | Same visual result. |
| `CSI 4m`, `5m` (10) | Underline; blink (the `05 TEST` cell is visible in one capture phase and blank in another). `31;4m` gives red underline; a separate `4m` after red gives white underline. | **Partial:** colors and character positions match; underline and blink are not set, so blinking text appears steady. |
| `CSI 7m`, `8m`, `16m`, `17m` (10) | Reverse; invisible text still occupies columns; `16` is blank and remains blank even with following `31` in the same SGR; `17` is red. No vertical line was visible for the tested values. | Reverse swaps foreground/background; secret (`8` or `16`) uses equal colors. `17` is red. No vertical-line attribute is implemented; any NEC code that draws one was **NOT RUN**. |
| `CSI 30–37m`, `40–47m`, combinations and erase (10) | 30–37 give black/red/green/yellow/blue/magenta/cyan/white. 40–47 show black text on that color. `41;32m` is reverse green, not a separately colored foreground/background. `7;31;4` and `4;31;7` give reverse red with underline. `K` under reverse or color erases to normal black; new text retains its selected attribute (`AFTER`). | Same eight colors by RGB meaning, not exact monitor shades. Reverse and erase behavior match; underline combinations lack the line. |
| `CSI >5h / >5l` (13–14) | `h` hides the cursor, `l` shows it blinking, at the same position (10,1 in the fixture). | Same via `Csrctl`. The graph-mode text on those same pages differs independently. |
| `CSI >3h / >3l` (11–12) | Both clear and home. `h` selects 20 rows (20 raster lines per character); `l` returns to 25 rows. Column 60 is still addressable. | **Deferred.** Consumed, but VA keeps the existing 25-row layout and does not clear/home for these modes. |
| `ESC ) 0 / ESC ) 3` (13–14, then reset) | `)0` allows the Shift-JIS pair `95 5C` to draw `表`. `)3` displays the bytes as single characters and puts `g` in the system line; `)0` restores kanji and clears the indicator. | **Deferred.** Both forms are consumed; the driver stays in kanji mode and does not write an indicator. |
| `CSI ?25h/l`, `CSI ?3h/l` (13) | Tested forms are ignored; `EFGH` prints consecutively. | Ignored as on NEC. Other `?` modes **NOT RUN**. |
| `CSI nL / nM` (15–16, 24) | Insert/delete lines from the current row; omitted count is one, `2` acts on two. Cursor returns to column 1 of the same row. Scroll/dropped lines stay in the text region. | Same via `Insline`/`Delline` and `Locate`. Larger/zero insert/delete counts on NEC **NOT RUN**; VA defaults zero to one and clamps to remaining main rows. |
| `ESC D / ESC M / ESC E` (17–18, 24) | Index down or reverse-index up, scrolling at the appropriate margin, preserving column. `E` is next line at column 1, scrolling at bottom. The label row stays put. | Same via `Index` and `Rindex`, with CR before `Index` for `E`. |
| `07h`, `09h`, `0Bh` (19) | `07h` leaves `AB` adjacent, no visible glyph. Tab advances to the right (`B` at column 14 in this cooked sequence). `0Bh` moves up one row, retaining column. | Same screen/markers. VA passes BEL and tab to the documented ROM path if they reach the driver. Audible BEL and independent raw-handle tab positions **NOT RUN**. |
| `0Ch`, `1Ah`, `1Eh` (19–20) | `0Ch` occupies one blank slot; it is **not** linefeed. Cooked AH=40h stops at `1Ah`; via AH=02h `1Ah` clears and homes. `1Eh` homes without clearing. | Same. The DOS 4 cooked stop is in `DISK.ASM` (`WRCONLP`). VA maps `0Ch` to a space because VA `Litout` draws a visible FF glyph; `1Ah` clears/homes when it reaches VAIO. |
| Other controls (21) | `00h` and `7Fh` occupy one blank column. `01–06`, `0E–19`, `1C`, `1D`, `1F` occupy one visible glyph column (mnemonics or arrows). `08` backs up, `0A` advances a row keeping column, `0D` returns to column 1; `1B` is the escape introducer. | Same positions and visible/blank distinctions; font shapes come from the respective ROMs. J2a's explicit discard of `7Fh` *after a pending lead* is unchanged. |
| `CSI >1h / >1l` and half-kanji (22, 24–26) | 24 rows with labels, 25 hidden; line edits, scrolling and erase reach row 25 only when hidden. Overwriting or erasing either half of `表` blanks the other half. | Same in the tested 25-row layout. Four kanji tests per write method: overwrite either column, erase suffix at right half, erase prefix at left half. |
| Unknown/malformed (23) | `12;34z` is ignored. `12;?K` and `>X` also swallow the immediately following marker in the fixture. A second ESC inside an ordinary CSI is consumed; following `[` and text print literally. Unknown `z` with 40, 80 or 120 decimal bytes consumes the whole sequence and displays the subsequent marker. | Same for the ordinary unknown final, 40/80 decimal bytes and second ESC. VA deliberately resumes earlier on `12;?K` and `>X`, printing `? OK`/`X OK`; the 120-byte stream reaches the hard limit and its suffix prints before `HARD OK`. No hang on either model. Exact NEC parameter-storage and recovery limits were not established. |

## Implementation decisions

- `OUTCHR` retains one Shift-JIS lead as in [J2a](J2a-sjis-output.md), independent of the pending escape state. A lead followed by ESC is dropped. Preserve the J2a `[>` replay case when interrupted by a Shift-JIS lead. An ordinary unknown printable final ends a CSI. There are eight numeric slots, saturating at 255. At 64 parameter bytes a sequence becomes invalid; the parser looks for its final until a hard limit of 96 parameter bytes, then resets and processes that byte normally. These are VA safety limits, not asserted NEC constants.
- Use public INT 83h functions from `604TEXT.TXT` §6.4.3: `Locate` (7), movement (8–11), `Index`/`Rindex` (12–13), line edit (17/19), erase (21–22), `Csrctl` (35) and `Askloc` (36). Leave the resident split and ROM-managed label buffer from [J0.4](J0.4-label-line.md) intact. `CSI 6n` appends a single response to the CON read path, not to the ROM's keyboard buffer. Already selected input precedes it; the normal flush clears it.
- Keep VA **attribute mode 0** (`Setatr`, function 4), so previously drawn cells retain their own foreground/background colors. `Setcolor` (function 6) would change split-wide colors in the effects modes, not add independent per-cell blink/underline to mode 0. Software secret is a same-color mapping; colors and reverse remain per cell. Exact underline/blink with arbitrary colors and any vertical-line effect need a different rendering approach.
- ROM overwrite already cleans up a paired neighbor, but bare `Eralin` left a half visible. Use `Getadr` (function 24) to read the two boundary words; widen the erase only for a matching pair in the same row, then restore the cursor. The VA uses bank 1 of the documented V3 system-memory window (`_MemMode`, BNN technical manual §2, port `0152h`); mask only the bank field and restore the original register and interrupt state before returning to the BIOS. No ROM-internal addresses or direct TVRAM writes.

## Gate results

Page counts require the same observed text/attributes and cursor behavior, not identical font pixels or synchronized blink phases. The page 01 post-print wrap difference is counted against both methods; pages 10–14 and 23 also differ. Page 26 confirms completion but is not a reference item. Smaller rows below break out some of the same tests; do not add them to the page totals. See [checker output](J2b/va-checks.txt).

| Brief gate | VA | VA2 | Notes |
|---|---:|---:|---|
| 1. NEC parity, AH=40h | **18/25** | **18/25** | Positions/erase/line editing and controls apart from the specified differences. Audible BEL **NOT RUN**. |
| 2. NEC parity, AH=02h | **18/25** | **18/25** | Within VA, 25/26 character grids identical across methods, excluding the known cooked `1Ah` difference on page 19. |
| 3. Labels visible / hidden | 48/48 + 4/4 | 48/48 + 4/4 | Label pixels unchanged on 24 visible captures per method, including the return to prompt; two 25-row fixtures per method. |
| 4. Malformed, strict NEC parity | 4/7 per method | 4/7 per method | Both runs reached `ESCPROBE DONE`; three differences per method detailed above. |
| 5. Half-kanji | 8/8 | 8/8 | Four overwrite/erase cases per method; no orphan visible. Wrapped pairs and half-kanji on an `Erascn` boundary **NOT RUN** separately. |
| 6a. J2a gates 1–6 | 7/9 | 7/9 | The known J2a differences (pending lead + CR and pending lead + CLS) remain; all J2a driver expectations passed. |
| 6b. J0.4 steps 1–5 | 9/10 | 9/10 | The old `LABELCHK E` expectation that `2J` preserves row 24 fails by design; J2b clear+home matches NEC and redirected CLS still has exactly seven bytes. |
| 6c. J0.3 steps 1, 5, 9 | 8/8 | 8/8 | DIR/F3, three COPY CON/F10 runs, and four editing/EOF/break regressions. |
| 6d. KEY, CHKDSK | 1/1 + 2/2 | 1/1 + 2/2 | KEY compared all 31 entries with IO.SYS; CHKDSK measured before/after. |

On each model CHKDSK reports **530,352 → 529,456 B free** out of 655,360 B. `RESEND` grew from `0D81h` to `1110h` (+911 B before paragraph rounding, +896 B resident). `IO.SYS` grew from 19,786 to 20,698 B (+912 B) and now occupies 21 rather than 20 boot sectors. The boot sector, kernel, COMMAND and the other shipping files are unchanged. See [build records](J2b/build.txt). Physical hardware, 2D boots, unlisted modes/sequences, exhaustive range/parameter combinations, and behavior with unread cursor reports interleaved with function keys: **NOT RUN**.

## Reproduce

Build `3aafe18` and `8768bce` in scratch using unmodified FreeDOS-88VA/freedos `experiments/msdos4-va/build.py` at `7f467a2187a9e15c0c1bb84f179f214fe925153f`; set `msdos.commit` per scratch lock and use emu2 `9d8698d06e67359bc8b230c2d19d5b1503e60819`, as in [J2a](J2a-sjis-output.md#reproduce). Use the two distribution D88s as `$BASE` and `$AFTER`. With `$S` outside the repository, assemble the probe and reuse the J2a fixtures (`SJISOUT.COM`, `J1DBCS.COM`, `$REG`):

```sh
nasm -f bin tests/pc88va/ESCPROBE.NAS -o "$S/ESCPROBE.COM"
PYTHONPATH="$BUILDER_EXP" python3 -B tests/pc88va/sjis-media.py va \
  "$AFTER" "$S/test.d88" "$S/SJISOUT.COM" "$S/J1DBCS.COM" \
  --regressions "$REG" --escape-probe "$S/ESCPROBE.COM"
PYTHONPATH="$VAEG_SOURCE/tools/qa" BASE_CISTAT=1000:06B5 AFTER_CISTAT=1000:06CD \
  python3 -B tests/pc88va/esc-run.py "$VAEG" "$VA_ROMS" \
  "$BASE" "$AFTER" "$S/test.d88" "$S/runs"
PYTHONPATH="$BUILDER_EXP" python3 -B tests/pc88va/esc-check.py "$S/runs"
PYTHONPATH="$BUILDER_EXP" python3 -B tests/pc88va/sjis-check.py "$S/runs" \
  --nec-clear --expected-memory 530352 529456
```

The runner verifies each requested capture and the final `exit` event; the checker verifies screen cells, selected pixels, labels, exact report bytes and completion. For NEC use the [NP2kai setup from J0.3b](J0.3b-editing-keys.md#reproduce) and the SHA-verified NEC system disk 1. Use `pack_nec` from `docs/J1/media.py` with only `('ESCPROBE.COM', probe.read_bytes())` in a scratch image, then boot its absolute path. Cancel INSTDOS (Escape, Enter) and exit MENU (F9). Run `ESCPROBE` and `ESCPROBE B`; capture before each of the 25 Space taps, sampling another blink phase on the cursor and SGR pages. Capture `ESCPROBE DONE` after the last tap. All NEC media, manuals and ROMs used by the tests stay outside the repository.

# J3b.2 — Project kana input in VAIO

Run **`JFP FEP`** to select the project front end. Type `ECHO `, tap
**ZENKAKU**, type `nihongo` and press **Return** to print `にほんご`. Tap
**F7** before confirming to get `ニホンゴ` instead. **KETTEI** inserts the
reading without submitting the DOS line. ZENKAKU returns to ASCII between
readings; `JFP OFF` returns to plain CON. Use `JFP OFF` before switching
between this front end and `JFP ROM` / `JFP ON`.

[Prompt capture](J3b.2/prompt.png): top, hiragana pending and after Return;
bottom, katakana pending and after confirmation/submission. The four
screens were pixel-identical on VA and VA2. **No kanji conversion in project
mode yet**: HENKAN uses a two-entry kana stub, not a dictionary.

## Design and key choices

- **Three exclusive modes.** Plain remains the boot default. The existing
  `JFP.COM` gains `FEP`; no new tool or packaging change beyond the existing
  [J3a builder patch](J3a/build-jfp.patch). Private `INT DCh`, `CL=F0h`,
  `AX=4A46h` gains request `BX=4` to select project mode from plain and
  reply mode `BX=3` (`AX=464Ah`, other registers and return flags as before).
  Query and release keep their original operation numbers. Selection does
  not initialize ROM JFP, request its main keyboard functions or use its
  buffers. J3a remains the ROM path when selected.
- **Primitive keyboard arbitration.** [`VAIO.ASM`](../v4.0/pc88va/VAIO.ASM)
  hands each primitive key to [`VAFEP.INC`](../pc88va/VAFEP.INC) before the
  VAIO key-table decoder. ZENKAKU toggles width only between readings,
  as in [J3.0](J3.0-jfp-probe.md#2-initialization-ordinaryfunction-keys-and-the-conversion-key).
  In kana width, alphabetic input, `-`, an apostrophe after `n`, and the
  primitive half-width kana codes start or extend a reading. Other idle
  keys use their normal VAIO mapping ([J0.3](J0.3-fkeys-input.md#table-and-sources));
  in particular F7, F10 and F3 are still DOS keys when idle. The scan/internal
  codes and `PrmSnsK`/`PrmGetK` are from the PC-88VA Technical Manual,
  `603KEYB` §6.3 and its key tables. Kana is recognized from the code in
  the queue, not from the current state of the KANA modifier at poll time.
- **Composition keys.** BS removes one unresolved letter or one kana cell.
  ESC cancels. Ctrl-C while pending cancels the reading without breaking the
  DOS line; idle Ctrl-C is passed through. These follow the ROM behavior
  observed at the DOS boundary in [J3a](J3a-rom-jfp-input.md). KETTEI confirms
  the current display (hiragana by default) without sending a space or CR;
  Return also queues a CR, so a single tap can submit `ECHO` or a line in
  an application. F7 adopts the full-width katakana convention cited in the
  brief, not a claim of ROM F7 equivalence; it changes the script without
  using the backend. HENKAN begins conversion or moves forward; Shift+HENKAN
  goes backward in an open candidate session. Both directions wrap. Editing
  exits candidate or F7 view and resumes the hiragana reading; other DOS
  function/editing keys, toggles and ordinary non-composition bytes are
  ignored while a reading is pending.
- **Bounded parser.** The 145-entry table (870 B) was written for this driver
  from Hepburn/Kunrei spellings and the standard Shift-JIS kana chart. It
  includes `shi/si`, `chi/ti`, `tsu/tu`, `fu/hu`, `ja/zya`, yōon, x/l small
  kana, `nn` and `n'`, doubled-consonant sokuon, and `-` for `ー`. A trailing
  lone `n` resolves to `ん`; unresolved non-`n` spelling is kept as literal
  lowercase ASCII rather than silently discarded. The queue's half-width
  kana codes map to full-width kana/punctuation; dakuten/handakuten modify
  an eligible preceding kana. Voiced `う` is represented as `ヴ` because
  standard Shift-JIS has no `ゔ`. The reading has 30 cells and a four-letter
  pending suffix; input beyond the bound is discarded. Two-kana table
  entries are appended together or not at all. This is a kana editor, not
  a full punctuation/foreign-syllable IME.
- **System row.** Same reservation policy as J3a: selecting the mode gives
  a 24+1 split even if the user had hidden labels. `ESC[>1h`/`ESC[>1l` record
  the requested layout; the last request takes effect on `JFP OFF`. Only
  during composition, VAIO disables shift-driven labels (`SftCtl`), paints
  the system split (`Chcsn`/`Locate`/`Eralin`/`Putstr`, `604TEXT` §6.4.3),
  and returns to the main cursor with no attribute change. `[H]`, `[K]`,
  `[1]`, and `[2]` mark reading, explicit katakana, and stub candidate views.
  Clearing the composition restores `SftCtl` and repaints the idle row
  using VAIO's existing label painter. The [J0.4 split](J0.4-label-line.md)
  keeps the system row separate from all 25 main text rows.
- **DOS byte delivery.** While composing, no reading bytes are ready to
  DOS. On confirmation a project-owned byte stream drains lead then trail,
  before any further primitive key or pending cursor report. Status may
  process composition keys and cache one byte, but peeking does not remove
  that byte. A project-mode flush cancels the reading and candidate, drops
  the entire confirmed stream including any cached byte, and drains the
  remaining primitive queue without interpreting keys. It retains the
  selected width. Plain and ROM retain their own flush paths.

## Backend seam and execution context

The resident hooks in `VAFEP.INC` are `FEPBEGIN`, `FEPNEXT`, `FEPPREV`,
`FEPCANCEL`, and `FEPCOMMIT`:

| Operation | Contract |
|---|---|
| `begin(reading)` | Receives `DS:SI` and `CX` reading cells. Each word is lead:trail for Shift-JIS or a zero-extended ASCII byte. The frontend owns the immutable input for the session. Selects and materializes the first candidate. |
| `next` / `previous` | Select and materialize the adjacent candidate in the current session, wrapping. The stub alternates katakana and hiragana. |
| `cancel` | Closes the session with no output. Editing, ESC, pending Ctrl-C and flush can take this path. |
| `commit` | Returns the selected candidate and ends the session. No learning or persistence. The frontend, not the backend, decides whether to append Return's CR and publish the bytes to CON. |

The candidate is ASCIIZ Shift-JIS in the owned `FEPBUF`, with `DI` at its
terminator; `FEPCHOICE` is the session/candidate tag. Nothing in these hooks
executes in a keyboard IRQ. They are called by serialized CON request
processing, including **status** while DOS can already be active; the
private foreground release can cancel a session too. The stub touches
only bounded resident buffers and calls no interrupts or device routines.
That is why it is safe at this call site, not because the site is safe
for arbitrary conversion code. **J3b.3 must not put `ResJFP`, file I/O,
or unqualified BIOS conversion behind these synchronous calls.** Keep
initialization in the foreground and qualify conversion in this context
before wiring it in, or use a foreground owner and explicit deferral that
still works for a blocking DOS read. Define error/miss handling, accepted
reading encodings, and validated output bounds for the real backend. See
[J3b.1](J3b.1-dictionary-feasibility.md#3-documented-bios-as-a-conversion-engine).

## Gate

**VA 52/52; VA2 52/52** on 2HD, with vaeg PR #82
`Rel.20261121 (m153, 6367e5d3)`, SHA-256
`a3ab65a03eac9fd2abccca3d51b8e464266a4b6141b9d5132b5b667495655906`.
Used local ROM sets, no saved config or backup RAM. Counts are assertions
or grouped checks, not boots: 31 counted-run cold starts per model.
See [checker output](J3b.2/observations.txt) and [build data](J3b.2/build.txt).

| Brief item | VA | VA2 | Checked |
|---|---:|---:|---|
| 1. Plain | 24/24 | 24/24 | J0.3 steps 1/5/9 (10 checks including five F10 cold boots), J0.4 steps 1–5 (10), KEY (1; all 31 slots), J2a TYPE (1), CHKDSK before/after (2). Editor baseline comparison uses decoded main text, excluding the differing release banner. |
| 2. ROM JFP | 7/7 | 7/7 | J3a steps 2 and 6: `日本` candidate/confirm/ECHO; BS, ESC, pending and idle Ctrl-C, pending F1, F1/F3 recall, and DOS two-column erase. |
| 3. Project prompt | 13/13 | 13/13 | `nihongo` in hiragana and F7 katakana, seven spelling fixtures (including `kyou`, `sshi`, `nn`, `xtu`, `ko-`, `n'`, and a Kunrei/x-l alias string), direct KANA plus dakuten, BS/ESC/Ctrl-C. Also checked pending F1 and ZENKAKU do not leak and idle F3 recalls the confirmed template. |
| 4. Candidate cycle | 1/1 | 1/1 | HENKAN → `[1] ニホンゴ`, HENKAN → `[2] にほんご`, Shift+HENKAN → `[1]`, then forward and confirm hiragana. |
| 5. COPY CON | 1/1 | 1/1 | Return submits the composed line; F10 + Return ends input while still in kana width. TYPE shows the line. `J.TXT`: `82 C9 82 D9 82 F1 82 B2 0D 0A`. |
| 6. EDLIN | 1/1 | 1/1 | Insert, F10, list, save, TYPE. `E.TXT`: `83 6A 83 7A 83 93 83 53 0D 0A 1A`. |
| 7. Labels | 2/2 | 2/2 | Held Shift does not overwrite composition; idle Shift and release work, with labels restored pixel-for-pixel. Hidden at start, reserved row and untouched main row 1 while enabled, hide deferred, row 25 returned to DOS on OFF. |
| 8. INT 21h input | 3/3 | 3/3 | `FEPBYTE` checks 06h/07h order and repeated 0Bh peeks, 0Ch during the reading and after the lead with a cached trail; subsequent input verifies width was kept. |
| **Total** | **52/52** | **52/52** | |

Supplemental on both models: opposite-mode selection refused both ways;
30-cell limit and atomic rejection of a two-kana entry with only one slot
left; CHKDSK after selecting project mode matches the plain measurement.

**Memory on both models:** 655,360 B total. CHKDSK free **528,256 → 525,952 B
(−2,304 B)**. Resident VAIO grew **2,298 B** before DOS paragraph rounding.
IO.SYS grew **21,898 → 24,186 B** (22 → 24 boot sectors). `JFP.COM` is
1,025 B and nonresident. There is no additional measured cost to select FEP.

**NOT RUN:** physical hardware, VA3, 2D, smaller RAM, alternate vaeg builds,
NEC OEM DOS/FEP comparison, exhaustive spelling or kana/diacritic matrix,
queue-overflow/IRQ stress, external screen/layout or KEY mutations during
composition, ESC hide/show issued by another caller during a pending reading,
ROM→OFF→FEP composition (opposite-mode rejection and OFF were tested),
successfully loaded ROM default dictionary files, or any real kanji backend.

## Reproduce

1. Build in scratch outside the repository, following the [R1 setup](R1-boot-banner.md#reproduce)
   with the [J3a builder changes](J3a-rom-jfp-input.md#reproduce): apply only
   the `build.py` hunks from R1 and apply `build-jfp.patch` in both scratch
   experiments. Use the full pins in [build.txt](J3b.2/build.txt), branches
   `release/msdos-va` and `topic/j3b2-project-kana-input`, respectively.
   Leave `msdos.release_date` unset. The builder already copies the includes
   from `pc88va/`, including `VAFEP.INC`.
2. Prepare `$REG_D88` from the candidate as in the [J2a reproduction](J2a-sjis-output.md#reproduce),
   with `LABELCHK.COM`, `LONG.TXT`, `CONKEY.COM`, `SJISOUT.COM` and `J1DBCS.COM`.
   Make a second image for the project cases:

   ```sh
   nasm -f bin docs/J3b.2/FEPBYTE.NAS -o "$S/FEPBYTE.COM"
   PYTHONPATH="$BUILDER_EXP:docs/J1" python3 -B - "$REG_D88" "$S" <<'PY'
   import sys
   from pathlib import Path
   from media import pack_va
   base, scratch = map(Path, sys.argv[1:])
   pack_va(base, scratch / 'project.d88', [('FEPBYTE.COM', (scratch / 'FEPBYTE.COM').read_bytes())])
   PY
   ```
3. From the repository root use the same vaeg m153 binary for both models.
   Set `$BASE_D88`/`$AFTER_D88` to the distributions, `$ROMS` to the local
   ROM directory, and `$S` to scratch. The breakpoint is in **VAIO's DOS
   code**, from the MASM listings. Use Pillow and vaeg's QA decoder:

   ```sh
   export PYTHONPATH="$BUILDER_EXP:$VAEG_SOURCE/tools/qa"
   export BASE_CISTAT=1000:0954 AFTER_CISTAT=1000:099B
   python3 -B tests/pc88va/wrap-run.py "$VAEG" "$ROMS" "$BASE_D88" "$AFTER_D88" \
     "$REG_D88" "$S/plain" base-boot after-boot base-mem after-mem dir display \
     toggle erase eof-1 eof-2 eof-3 ctrl-z cancel-break base-regression \
     after-regression type j1-key
   python3 -B tests/pc88va/wrap-run.py "$VAEG" "$ROMS" "$BASE_D88" "$AFTER_D88" \
     "$REG_D88" "$S/extra" eof-1 eof-2
   python3 -B docs/J3a/run.py "$VAEG" "$ROMS" "$REG_D88" "$S/rom" prompt edit
   python3 -B docs/J3b.2/run.py "$VAEG" "$ROMS" "$S/project.d88" "$S/fep"
   python3 -B docs/J3b.2/check.py "$S/plain" "$S/extra" "$S/rom" "$S/fep"
   ```

Only checker output and screenshots are published. Disks, raw TVRAM,
ROM files and emulator state stay outside the repository.

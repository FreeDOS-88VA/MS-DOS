# M5 — Interrupt scope, file writes and unexpected BIOS results

**Gate:** run the same converted reading under DOS buffered input and
status/byte/flush calls on all six paths. Check scoped interrupt counts,
image changes, and one bounded malformed-result case in the FEP.

Both monitor COM variants reuse the J3b.3 INT 21h/83h hooks and positive
control. In the FEP they scope counts to public INT 8Dh conversion and
session-close calls (03h–0Ah). In ROM mode the additional scope is the
actual VAIO INT 82h main `SnsChar` / `GetChar` calls, which encompass ROM
composition and confirmation. The hooks count interrupt entry, not all
firmware execution; a nested INT 21h is blocked rather than allowed to
reenter DOS. Ordinary VAIO painting outside the wrapped calls does not
increment the INT 83h counter. Scope includes typing, first/next/previous
conversion and KETTEI in the buffered case; the byte case covers first
conversion, confirmation and both flushes.

Compare each entire writable disk to the read-only starting D88. This is
an **on-disk observation with both default files absent**, not a probe of
in-memory ranking or a claim about external files. In FEP, source also
shows confirmation calls `QuitJFP`, not the learning `Decide` operation.

**NOT RUN (both modes):** `.DIC`/`.DAT` present, successful external-file
loads, and learning with real dictionary/gaiji files. `ResJFP` opens and
can parse them *before* `VAJFP` evaluates the open results. Empty stand-ins
would not establish valid-file behavior, and could exercise an unknown
parser with malformed files. No placeholder or real files were used.
**NOT RUN (ROM):** injected unexpected firmware output, and whether the
ROM learns in memory on confirmation. The monitor does not observe
private firmware operations. **NOT RUN (FEP):** output overrun, missing
terminator, or arbitrary firmware fault scenarios beyond the one fixture.

**15/15 cases to `exit`, 81 TVRAM shots.** All twelve real monitored
trials finished without nested INT 21h and left the image byte-identical.
The ROM keyboard path did enter INT 83h on all configurations; the
FEP's scoped conversion/confirmation calls did not. Counts are for the
whole probe, not broken down by individual key. The eight INT 8Dh
columns are Quit, First, Next, Previous, Right, Left, Long and Short.

| Configuration | Mode | Context | INT 8Dh calls 03h–0Ah | INT 82h main calls | Nested 21h / 83h | D88 unchanged |
|---|---|---|---|---:|---:|---|
| va-640 | ROM | monitor-line | 0 0 0 0 0 0 0 0 | 20 | 0 / 10 | yes |
| va-640 | ROM | monitor-api | 0 0 0 0 0 0 0 0 | 38 | 0 / 18 | yes |
| va-640 | FEP | monitor-line | 1 1 1 1 0 0 0 0 | — | 0 / 0 | yes |
| va-640 | FEP | monitor-api | 3 3 0 0 0 0 0 0 | — | 0 / 0 | yes |
| va2-256 | ROM | monitor-line | 0 0 0 0 0 0 0 0 | 20 | 0 / 47 | yes |
| va2-256 | ROM | monitor-api | 0 0 0 0 0 0 0 0 | 38 | 0 / 106 | yes |
| va2-256 | FEP | monitor-line | 1 1 1 1 0 0 0 0 | — | 0 / 0 | yes |
| va2-256 | FEP | monitor-api | 3 3 0 0 0 0 0 0 | — | 0 / 0 | yes |
| va2-640 | ROM | monitor-line | 0 0 0 0 0 0 0 0 | 20 | 0 / 47 | yes |
| va2-640 | ROM | monitor-api | 0 0 0 0 0 0 0 0 | 38 | 0 / 106 | yes |
| va2-640 | FEP | monitor-line | 1 1 1 1 0 0 0 0 | — | 0 / 0 | yes |
| va2-640 | FEP | monitor-api | 3 3 0 0 0 0 0 0 | — | 0 / 0 | yes |

| Configuration | FEP malformed-trail injection |
|---|---|
| va-640 | Reading retained, confirmed as にほんご; next genuine conversion printed 日本語 |
| va2-256 | Reading retained, confirmed as にほんご; next genuine conversion printed 日本語 |
| va2-640 | Reading retained, confirmed as にほんご; next genuine conversion printed 日本語 |

The injection substitutes `81 7F 00` for the first Sug1st output using
its public ES:DI buffer. The input was the same `nihongo` fixture. FEP
rejected the bad trail, displayed `[H] にほんご`, confirmed kana only,
and converted normally on the next reading. This tests one bounded
fault in the return buffer, not protection against firmware overwrites.

## Reproduce

Use an M4 image containing `FEPMON.COM` from the J3b.3 M1 gate image.
The unmodified NASM configuration produced an identical `FEPMON.COM`.

```sh
export PYTHONPATH="$VAEG_SOURCE/tools/qa:$BUILDER_EXP:docs/J1"
I=docs/J3b.3
nasm -I "$I/" -DROM_FRONTEND -f bin "$I/FEPMON.NAS" -o "$S/ROMMON.COM"
nasm -I "$I/" -DBAD_SUGGESTION -f bin "$I/FEPMON.NAS" -o "$S/BADBIOS.COM"
nasm -I "$I/" -DMONITORED -f bin docs/J3c/CONBYTE.NAS -o "$S/FMONBYTE.COM"
nasm -I "$I/" -DMONITORED -DROM_FRONTEND -f bin docs/J3c/CONBYTE.NAS -o "$S/ROMBYTE.COM"
python3 -B docs/J3c/pack.py "$S/key-gate.d88" "$S/monitor-gate.d88" \
  "$S/ROMMON.COM" "$S/BADBIOS.COM" "$S/FMONBYTE.COM" "$S/ROMBYTE.COM"
python3 -B docs/J3c/safety.py "$VAEG" "$ROMS" "$S/monitor-gate.d88" "$S/m5" \
  --cistat 1000:09AA
python3 -B docs/J3c/safety.py report "$S/m5" "$S/monitor-gate.d88"
```

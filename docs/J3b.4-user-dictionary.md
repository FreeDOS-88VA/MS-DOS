# J3b.4 — Project FEP user dictionary

## Gates (defined before implementation)

1. On vaeg, ADD/DEL/LIST, exact FAT file format, malformed/oversized input,
   duplicate and full-table rejection.
2. On vaeg, load, reload and confirm user candidates before the BIOS;
   reverse across the boundary, and verify a reading with no user match.
3. On VA 640 KiB and VA2 256/640 KiB, run the nested-interrupt monitor,
   COPY CON/EDLIN byte checks, the J3c switch gate and CHKDSK in three modes.

## Foreground commands and format

`JFP ADD <reading> <word>`, `JFP DEL <reading> <word>` and `JFP LIST`
operate on `A:\JFPUSER.DIC` independently of the current directory and
input mode. The current VABOOT/VAIO boot path uses A:; the port did not
return a usable boot drive via INT 21h AX=3305h in the first gate attempt.
Revisit the path when a different boot drive is supported. Type both arguments
as full-width Shift-JIS; use ASCII spaces/tabs as separators. Each argument
is 1–30 cells. A reading accepts hiragana and the prolonged sound mark
(`ー`), the same repertoire as the conversion backend. A word accepts
structurally valid two-byte Shift-JIS with leads 81h–9Fh/E0h–EFh and trails
40h–FCh except 7Fh. This is not an assigned-character or font check.

Version 1 starts with five ASCII bytes `JFPUD` followed by byte `01h`.
Zero to eight 122-byte records follow, in registration order, with no
terminator: one reading-byte count, one word-byte count, 60 bytes for
the reading and 60 for the word. Each field contains its counted bytes
followed by zero padding. Exact duplicate pairs are invalid; different
words for the same reading are permitted. Maximum file size: 982 bytes.
The file contains user input, not a copy of any ROM dictionary.

Saves stage a complete file in `JFPUSER.TMP`, rename an existing dictionary
to `JFPUSER.BAK`, then rename the staged file into place and remove the
backup. An existing staging or backup file is never overwritten. On a
failed publish the command attempts to restore the backup. This is not
a crash-atomic filesystem transaction: after interruption or an I/O error,
inspect the three files before removing a stale temporary file or restoring
a backup. Keep backups of important registrations.

## Firmware reference

PC-88VA Technical Manual `618JFP` §6.18.4 documents `AddWd` and `DelWd`
(INT 8Dh CL=14h/15h), and `GetUDEnv` / `SetUDEnv` for the firmware's user
dictionary name. The manual explicitly describes `AddWd` opening, writing
and closing the ROM-managed file. We use none of these functions: the
format and lifetime are project-owned, and J3b.3 qualifies only the
built-in conversion backend (its activation guard requires both firmware
default files absent). The project file does not change that guard.

## Resident lookup and candidate order

`JFP FEP` and `JFP ON` both load and validate the entire file in the
foreground and replace the resident table. Missing means empty; an
invalid file or I/O error prints a warning and loads an empty table.
ADD and DEL do not touch resident memory: run `JFP ON` again to reload
without restarting the BIOS. `JFP OFF` discards the resident table;
`JFP ROM` never reads or consults the project dictionary.

The eight slots use 976 bytes in VAIO, plus candidate-navigation state
and code. The fixed allocation costs the same in all modes but does not
require a TSR, retained DOS block, or DOS memory management in CON. The
private VAIO call copies the validated records from the foreground COM;
it checks the size and source offset and rejects an update while a
candidate is open. No pointer into the transient COM is kept.

HENKAN checks the complete composed reading byte-for-byte. Matching user
words come first in registration order; HENKAN after the last starts
`Sug1st`. Shift+HENKAN goes backward. For a matched reading, VAIO compares
the visible text and focus against the initial BIOS result to recognize
the boundary, then goes directly back to the last user candidate. It does
not call `SugPrv` at the boundary: despite the documented endpoint, VA2
wrapped on the gate reading. A later BIOS result indistinguishable from
its first can also be treated as the boundary.
Without a user match the same BIOS calls and endpoint behavior as J3b.3
apply. The first user entry does not wrap on previous. User words have no
phrase focus to move or resize; starting phrase navigation on a BIOS
candidate leaves the session in BIOS until it is closed. User words are
not considered for an individual segment of a longer reading. Accepting
or cancelling a user-only candidate makes no conversion BIOS call.

## Safety and memory

File I/O is in `VAJFP.ASM`. The CON path does a bounded linear scan of
resident records and copies a validated word into the existing delivery
buffer. The user-only path does not enter INT 8Dh. The BIOS path still
uses `QuitJFP`, not learning/`Decide`.

[USERMON](J3b.4/USERMON.NAS) reuses the J3b.3 INT 21h/83h/8Dh monitor
and adds an INT 21h trap covering the **entire** outer DOS buffered
CON read (AH=0Ah). Both scopes have positive controls. The outer trap
counts and blocks any software DOS interrupt entered during the read,
including outside a firmware call. The INT 83h counter remains scoped
to the backend, so ordinary system-row painting does not count as a
nested firmware text call. The gate cold-boots with the file saved by M2.
On each configuration, the user-only case made no conversion firmware
calls; the user→BIOS→user case made one each of `Sug1st`, `SugNxt`,
`SugPrv` and `QuitJFP`. Both measured zero nested DOS entries over the
whole read and zero nested DOS/text entries inside the BIOS. All six
monitored images were byte-identical to the input disk. These are scoped
interrupt observations, not qualification of arbitrary firmware or
external ROM dictionaries.

| Configuration | CHKDSK free, plain | FEP, no file | FEP, user file loaded |
|---|---:|---:|---:|
| VA 640 KiB | 524,000 B | 524,000 B | 524,000 B |
| VA2 256 KiB | 130,784 B | 130,784 B | 130,784 B |
| VA2 640 KiB | 524,000 B | 524,000 B | 524,000 B |

VAIO `RESEND` moved from `20D3h` to `265Dh`: **+1,418 B** resident,
**1,408 B** less free DOS memory after paragraph rounding, relative to
J3c. IO.SYS is 26,154 B (was 24,730 B, 25 → 26 boot sectors at 1,024 B
per sector); JFP.COM is 3,647 B and nonresident. COPY CON saved the
expected full-width word bytes plus CR LF; EDLIN saved those same bytes
plus Ctrl-Z. `TYPE` displayed the word from both files.

## Gate results

[Build pins](J3b.4/build.txt) · [M1](J3b.4/m1-results.txt) ·
[M2](J3b.4/m2-results.txt) · [M3 user-hit checks and memory](J3b.4/m3-results.tsv) ·
[Stock switch regression](J3b.4/switch-results.tsv).

| Gate | VA 640 KiB | VA2 256 KiB | VA2 640 KiB |
|---|---:|---:|---:|
| M1: foreground commands, validation and exact format | 2/2 | 2/2 | 2/2 |
| M2: candidate order/reload and corrupt-file fallback | 2/2 | 2/2 | 2/2 |
| M3: cold load with user hits, monitors, COPY CON and EDLIN | 4/4 | 4/4 | 4/4 |
| M3: CHKDSK in all three modes | 1/1 | 1/1 | 1/1 |
| M3 stock: plain J0.3 1/5/9, J0.4 1–5 and usage | 21/21 | 21/21 | 21/21 |
| M3 stock: `JFP ON` | 13/13 | 13/13 | 13/13 |
| M3 stock: `JFP FEP` | 13/13 | 13/13 | 13/13 |
| M3 stock: `JFP ROM` | 11/13 + 2 known differences | 11/13 + 2 known differences | 11/13 + 2 known differences |

The first four rows count cold cases; the stock rows count grouped checks
from 105 counted cold cases and 600 TVRAM captures. Each selector runs
J3b.3 gates 2, 5 and 8 as part of J3c M6. The two ROM differences per
configuration are the same as J3c: zero nested DOS entries but firmware
text-BIOS calls in both scoped monitor contexts. There were no unexpected
failures in the counted runs.

**NOT RUN:** physical hardware, VA at 256 KiB, VA3, 2D and HDD,
other ROM revisions, present firmware default `.DIC`/`.DAT` files,
firmware registration or learning, interrupted/failed publish and
rollback fault injection, exhaustive encodings or candidate sequences,
and IRQ/DMA stress. The monitor establishes the observed behavior of
buffered CON reads on these fixtures, not a proof for arbitrary software
or firmware.

## Reproduce

Use the [J3b.3 builder and tool pins](J3b.3-bios-backend.md#reproduce),
with `msdos.branch=topic/j3b4-user-dictionary`, `msdos.track=j3b4`. The
foreground-only source is `f9bf9ac`; the final product source is
`53f41e0` (the M3 commit changes only evidence). The final distribution
was fully rebuilt; its IO.SYS and JFP.COM were byte-identical to the
incremental M2 test build. Build and run with all artifacts in scratch.
Set `PYTHONPATH` to include `docs/J3c`, `docs/J1`, the builder experiment,
and vaeg's `tools/qa` directory. `$M1` and `$DIST` are the distributions,
`$S` is scratch, and `$VAEG` / `$ROMS` point to m153 and the local ROM set.

```sh
F=docs/J3b.4/format_gate.py
R=docs/J3b.4/resident_gate.py
G=docs/J3b.4/safety_gate.py
python3 -B "$F" pack "$M1" "$S/format.d88"
python3 -B "$F" run "$VAEG" "$ROMS" "$S/format.d88" "$S/format" --cistat 1000:09AA
python3 -B "$F" check "$S/format"
python3 -B "$R" pack "$DIST" "$S/resident.d88"
python3 -B "$R" run "$VAEG" "$ROMS" "$S/resident.d88" "$S/resident" --cistat 1000:09F4
python3 -B "$R" check "$S/resident"
nasm -I docs/J3b.3/ -f bin docs/J3b.4/USERMON.NAS -o "$S/USERMON.COM"
python3 -B "$G" pack-user "$DIST" "$S/user.d88" "$S/USERMON.COM" "$S/resident/va-640/fep/resident"
python3 -B "$G" pack-mem "$DIST" "$S/mem.d88"
python3 -B "$G" run-user "$VAEG" "$ROMS" "$S/user.d88" "$S/user" --cistat 1000:09F4
python3 -B "$G" run-mem "$VAEG" "$ROMS" "$S/mem.d88" "$S/mem" --cistat 1000:09F4
python3 -B "$G" check-user "$S/user" "$S/user.d88"
python3 -B "$G" check-mem "$S/mem"
```

For the stock regression, follow [J3c M6](J3c-comparison.md#m6--rebuilt-switch-gate)
using `$DIST` from J3b.4 and `--cistat 1000:09F4` in both runs. The
breakpoints are entries in **project VAIO**, from its MASM listings.
Some compact enabled runs captured an unfinished paste or startup
message. The counted result replaces the `j3a-prompt`, `return-candidate`,
and FEP `return-reading` / `monitor-line` cases with cold reruns using the
original waits (no key or assertion change). To generate these, call
`run.main(switch_gate.enabled, ('ON', 'ROM', 'FEP'))` from Python with the
same arguments, filtering `--case` / `--mode` as above. Use those case
directories in the stock report instead of the compact ones.

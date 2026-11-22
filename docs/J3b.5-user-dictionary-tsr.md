# J3b.5 — DOS-owned user dictionary

## Gates

On vaeg m153, run the J3b.4 foreground, candidate, corrupt-fallback and
nested-DOS checks, plus v1 migration, a 64-record table, CHKDSK lifetime
checks and the J3c M6 switch checks. Matrix: VA 640 KiB and VA2 256/640
KiB. Measure lookup-only worst-case miss latency on VA 640 KiB.

## Commands and file formats

`JFP ADD reading word`, `JFP DEL reading word`, `JFP LIST` and `JFP ON`
use `\JFPUSER.DIC` on the DOS boot drive, regardless of the current
working drive or directory ([F1](F1-small-fixes.md#3-user-dictionary-on-the-boot-drive);
originally fixed to A:). JFP falls back to A: if DOS does not report a
valid boot drive. Temporary `.TMP` and backup `.BAK` names use the same
root. Input and staged save/recovery rules are unchanged from
[J3b.4](J3b.4-user-dictionary.md#foreground-commands-and-format). In
particular ADD and DEL only modify the file; run `JFP ON` again to reload.

Both formats begin with ASCII `JFPUD` followed by one version byte. Both
allow an empty file payload and reject exact duplicate pairs. Valid fields
are 1–30 full-width cells (2–60 Shift-JIS bytes); the reading is hiragana
or the prolonged sound mark. On disk, records are in registration order.

- **v1 (`01h`):** up to eight 122-byte records, each with two one-byte
  lengths, then the zero-padded 60-byte reading and 60-byte word. Max
  file size 982 bytes. JFP validates the padding and normalizes to v2
  in memory; LIST and ON do not rewrite the file.
- **v2 (`02h`):** up to 64 records, each with two one-byte lengths,
  exactly those reading and word bytes, and one byte containing the
  entire record size (7–123 bytes). No padding or terminator. The last
  byte allows a backward scan without an offset array. A successful
  ADD or DEL saves v2 even when the input was v1. Maximum payload 7,872
  bytes; maximum file 7,878 bytes. There is no `/U` override.

## DOS memory and lifetime

Only `JFP.COM` does file I/O or DOS allocation. On a nonempty load that
cannot reuse the current arena, the COM first shrinks its own allocation
(INT 21h AH=4Ah). The transient arena is 21,104 bytes including the PSP,
parsing buffers and 2 KiB stack. The program checks the initial PSP arena
size before moving its stack. It then uses AH=48h and temporarily selects last-fit with
AX=5800h/5801h, restoring the original strategy even if allocation fails.
Last-fit normally places the persistent allocation at the high end of the
free arena, not immediately after the temporary COM allocation.

For this DOS version, [`ARENA.INC`](../v4.0/src/INC/ARENA.INC) defines
MCB owner at byte offset 1, and [`SYSINIT1.ASM`](../v4.0/src/BIOS/SYSINIT1.ASM)
uses owner 8 as an impossible process owner for system blocks. JFP sets
owner 8 on the block it just allocated, never on its own PSP. In
[`ALLOC.ASM`](../v4.0/src/DOS/ALLOC.ASM), `alloc_set_owner` initially sets
`CurrentPDB`, `alloc_scan` recognizes only owner 0 as free, and
`arena_free_process` only frees blocks matching the exiting PSP (called
by [`CTRLC.ASM`](../v4.0/src/DOS/CTRLC.ASM)). DOS therefore neither reuses
this allocation nor frees it on JFP.COM exit. `$DEALLOC` (AH=49h) checks
the MCB signature and marks it free without comparing owners. No copy of
JFP.COM or of its environment is left resident.

The block starts with a 16-byte `T` subarena header, so DOS
[`MEM /DEBUG`](../v4.0/src/CMD/MEM/MEM.C) can enumerate a non-final owner-8
arena without interpreting dictionary bytes as system subarena headers.
The VAIO pointer addresses the following paragraph at offset zero. The
64-entry ceiling therefore costs at most **7,904 bytes** of arena space
(payload rounded to a paragraph, subarena header, MCB). That is about 6%
of the plain-mode contiguous free memory measured at 256 KiB; shorter
records use less. Reloading a smaller nonempty file keeps the reusable capacity;
missing, invalid or unreadable files detach it. A malformed file or I/O
error also produces a warning. If a larger allocation fails, the old
valid table stays installed and JFP reports the failure.

VAIO holds **6 bytes** for table lifetime: payload segment, used bytes,
and capacity, all words. Candidate navigation additionally uses a 2-byte
cursor, 1-byte bridge flag, 2-byte focus and 73-byte first-BIOS-candidate
buffer (78 bytes, already present in J3b.4). Plain mode, FEP with no file
and `JFP ROM` retain no dictionary arena. `RESEND` is `233Fh` vs `267Ch`
at the branch base (**829 B less** resident). It is still **620 B above
J3c** (`20D3h`): that comparison includes the lookup/candidate bridge,
external-block management and intervening non-dictionary changes. Caching
no records in VAIO does not remove the code needed to support them. On the
2HD distribution IO.SYS shrinks from 28,714 to 28,202 bytes (29 → 28
1,024-byte sectors); the new JFP.COM is 2,914 bytes.

The private INT DCh protocol changes signature to prevent an old JFP.COM
from passing old-format records, or an old VAIO from being mistaken for
the new one. With interrupts masked, VAIO copies validated payloads into
the existing block or a newly allocated one and publishes the new state.
A load is refused if a candidate cursor is active; it never changes a
live cursor. The foreground command frees a replaced block after the
handler returns. `JFP OFF` flushes the mode, detaches the pointer and
returns the old segment for foreground AH=49h. CON scans only memory,
then uses the existing BIOS fallback; no DOS call is made by the scan.
Existing user/BIOS order and reverse crossing are unchanged.

When growing, the old high block cannot be freed until the new one is
installed. The resulting free space *above* the new block is real but
not part of the contiguous room reported by CHKDSK. It becomes contiguous
again on OFF. This is temporary fragmentation, not retained dictionaries.

## Results

[Build and artifact pins](J3b.5/build.txt) ·
[Dictionary checker output](J3b.5/dictionary-results.txt) ·
[Per-check stock M6 output](J3b.5/switch-results.tsv).

| CHKDSK free (bytes) | VA 640 KiB | VA2 256 KiB | VA2 640 KiB |
|---|---:|---:|---:|
| Plain, empty FEP, and ROM with a file present | 524,800 | 131,584 | 524,800 |
| 8 maximum-size entries, fresh | 523,776 | 130,560 | 523,776 |
| 64 maximum-size entries, fresh | 516,896 | 123,680 | 516,896 |
| 64 entries, grown from 8 | 515,872 | 122,656 | 515,872 |
| Grown table after 5 consecutive `JFP ON` reloads | 515,872 | 122,656 | 515,872 |
| After 5 `JFP ON`/`JFP OFF` cycles | 524,800 | 131,584 | 524,800 |

The 1,024-byte difference between fresh and grown 64-entry loads is the
old block plus its MCB above the new allocation. `MEM /DEBUG` enumerated
the grown payload as a single `INSTALL=` subarena of `001EC0h` bytes.
CHKDSK's figures are for contiguous room, not the sum of all free MCBs.
J3c reported 525,408 B free at 640 KiB and 132,192 B at 256 KiB; this
build is 608 B below those figures with no dictionary allocated.

On VA 640 KiB the worst-work fixture (64 records, each reading
matching until byte 60) crossed **0 frame ticks** from scan entry to
BIOS fallback entry. Both captures occurred in the same frame. This
measures the lookup only, at the tested frame phase; it does not bound
firmware conversion or wall-clock time on physical hardware.

| Gate | VA 640 KiB | VA2 256 KiB | VA2 640 KiB |
|---|---|---|---|
| ADD/DEL/LIST, v2 bytes, validation, v1 lookup and migration | PASS | PASS | PASS |
| User before BIOS, reverse crossing, reload, v1/v2 corrupt fallback | PASS | PASS | PASS |
| User-hit monitor, COPY CON and EDLIN | PASS | PASS | PASS |
| Entries 1/33/64 convert, ADD 65 refused | PASS | PASS | PASS |
| CHKDSK ownership, growth, reuse, release; MEM /DEBUG | PASS | PASS | PASS |
| Stock plain J0.3 1/5/9, J0.4 1–5 and usage | 21/21 | 21/21 | 21/21 |
| Stock `JFP ON` | 13/13 | 13/13 | 13/13 |
| Stock `JFP FEP` | 13/13 | 13/13 | 13/13 |
| Stock `JFP ROM` | 11/13 + 2 known differences | 11/13 + 2 known differences | 11/13 + 2 known differences |

Stock M6 reached exit in 105 cold cases (600 captures). The two ROM
monitor differences per configuration match J3c: zero nested DOS
entries but nested firmware text-BIOS calls in both scopes.

Both user-hit monitor cases on each configuration observed zero nested
INT 21h calls during buffered CON input. The user-only case also made no
conversion BIOS calls. The monitor disks remained byte-identical. The
stock suite used the immediately preceding COM, with the same VAIO and
no dictionary file, so it did not exercise the final subarena-header
change; the dictionary and memory gates used the final COM. The clean
full distribution rebuild also passed the capacity and corrupt-v2 cases
and the basic conversion scenario through all three selectors on each
configuration.

**NOT RUN:** physical hardware, other models/RAM or ROM versions, 2D
and HDD boot at J3b.5 (see F1 for boot-drive tests), IRQ stress,
allocation-failure and save/rollback fault injection, exhaustive
malformed inputs, other DOS implementations and a full stock M6 replay
after the final MEM-header change at J3b.5.

## Reproduce

Use the builder setup from [D4](D4-hdd-boot.md), including R1, J3a and
D1/D4 support. Build the product source commit listed in the evidence
with MASM 5.10 and LINK from the pinned builder. Set `$S` to an external
scratch directory, `$BASE`/`$DIST` to the pre-milestone/candidate disks,
`$VAEG` to m153 and `$ROMS` to the local ROM set. Set `PYTHONPATH` to
include `docs/J3b.4`, `docs/J3c`, `docs/J1`, the builder experiment and
vaeg's `tools/qa`. All generated fixtures, binary files, ROM files and
emulator captures remain outside the repository.

```sh
G=docs/J3b.5/gate.py
R=docs/J3b.4/resident_gate.py
PC=1000:0A3D # CISTAT in this VAIO listing
python3 -B "$G" pack "$DIST" "$S/core.d88"
python3 -B "$G" run "$VAEG" "$ROMS" "$S/core.d88" "$S/core" --cistat "$PC"
python3 -B "$G" check "$S/core"
python3 -B "$G" check-detail "$S/core"
python3 -B "$R" pack "$DIST" "$S/resident.d88"
python3 -B "$R" run "$VAEG" "$ROMS" "$S/resident.d88" "$S/resident" --cistat "$PC"
python3 -B "$G" check-resident "$S/resident"
python3 -B "$G" pack-corrupt-v2 "$DIST" "$S/corrupt-v2.d88"
python3 -B "$R" run "$VAEG" "$ROMS" "$S/corrupt-v2.d88" "$S/corrupt-v2" \
  --cistat "$PC" --case corrupt
python3 -B "$G" check-corrupt-v2 "$S/corrupt-v2" "$S/resident"
nasm -I docs/J3b.3/ -f bin docs/J3b.4/USERMON.NAS -o "$S/USERMON.COM"
python3 -B "$G" pack-user "$DIST" "$S/user.d88" "$S/USERMON.COM"
python3 -B "$G" run-user "$VAEG" "$ROMS" "$S/user.d88" "$S/user" --cistat "$PC"
python3 -B "$G" check-user "$S/user" "$S/user.d88"
# FEPUFIND and FEPSTARTBIOS in the same project listing, not in ROM:
JFP_SCAN_POINTS=1000:17ED,1000:1701 python3 -B "$G" run-timing \
  "$VAEG" "$ROMS" "$S/core.d88" "$S/timing" --cistat "$PC"
python3 -B "$G" check-timing "$S/timing"
```

Use the [J3c M6 pack and report](J3c-comparison.md#m6--rebuilt-switch-gate)
for stock tests. For the plain reference, pack `$BASE` the same way and
run only `after-boot` and `after-regression` using `1000:0A02`; map those
case directories to `base-boot` and `base-regression` in the reference
profile tree. For enabled cases run `run.main(switch_gate.enabled,
('ON', 'ROM', 'FEP'))` with the same arguments, using original waits.
For the full-distribution selector smoke, run
`run.main(run.scenarios, ('ON', 'FEP', 'ROM'))` on the rebuilt `$DIST`
with `--case prompt`, then `gate.py check-selectors "$S/product-selectors"`.

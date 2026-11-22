# D4 — Boot from a PC-88VA SASI disk

## M1 — ROM and reference boot

**Gate: PASS, vaeg m153 on VA and VA2, 5 MB target 0, both floppies absent.**
Run with `--sasi1 disk.hdi --fdd1 none --fdd2 none --bkupmem memory.dat`
(use a separate backed-up setup file for each model). With `--no-bkupmem`,
our cold starts did not boot the disk. `sdl2/np2.c` applies the CLI mount;
`machine/pccore.c` opens the media and `io/bkupmemva.c` enables fixed-disk
boot when a valid setup record and a fixed disk are present. Keep backup
memory enabled; if setup was just initialized, restart. `cbus/sasiio.c`
implements the bus and DMA; it is not an HDI-to-IPL loader.

References: *PC-88VA Technical Manual* §1.4 (V3 startup flow, PC key,
SW7, floppy IPL and its stack), and `602HDD.TXT` §6.2.1–3 (SASI command
registers, status and read/write functions). SW7 controls intelligent
floppy boot; the fixed disk is a separate setup choice. vaeg's boot
setup code documents drive 1 floppy priority even when fixed disk is
enabled. The manual's startup flow does not specify a SASI entry ABI.

On each model, `SYS C:` in PC-Engine 1.1 on a copy of a 5 MB HDFORM
volume changed IPL blocks 0–1, both FATs, the root and data. It installed
ENGINEIO.SYS, PCENGINE.SYS, ADVGBIOS.SYS and PCENGINE.COM. No partition
or boot menu appeared; the disk went straight to Ready ([VA](D4/pc-engine-va-hdd.png),
[VA2](D4/pc-engine-va2-hdd.png)). NEC DOS 2.11 `SYS C:` copied IO.SYS and
MSDOS.SYS without changing any IPL blocks on the same starting volume;
it did not provide a standalone boot in this test.

A scratch build logging CDBs showed that the first boot read is two
256-byte blocks from target 0, block 0. A target-1-only run still sent
that read to target 0. Replacing all four reserved blocks with a small
independent probe and zero padding worked on both models: no standard
boot signature or filesystem ID embedded in the IPL was needed. The
probe ran in native V3 with CS, DS, ES and SS at 3000h, entry offset 0,
SP FFFCh (VA) or FFFAh (VA2), IF set and DF clear. AX=2, BX=CX=0; DX
varied by model (0040h/0070h). Do not rely on these incidental register
values or on the incoming stack. INT 83h text output worked at entry.

## Design

Place our IPL in reserved blocks 0–3. The ROM enters the first 512
bytes, which can use INT 81h to fetch the remainder. Use target 0 (the
ROM boot target observed on both models); derive fixed geometry from
SENSE, load the two files by name and bounded FAT12 traversal, and pass
an explicit SASI boot marker to IO.SYS. Keep floppies A: and B:.

Use one IPL per disk; do not try to chain the PC-Engine IPL. Back up
before replacing it, warn and require confirmation. The replacement
changes boot ownership, not the filesystem layout. Real hardware,
physical switch combinations and alternate hardware boot targets:
**NOT RUN**.

## M2 — Project IPL and IO.SYS

MASM 5.10 and LINK 3.65 assembled and linked the updated IPLs and IO.SYS.
The [builder patch](D4/build-hdd-boot.patch) generates `VAHDBOOT.INC` for
SYS and FORMAT; dry-run applied to the builder template.

| Model | Host-built 5 / 10 / 20 / 40 MB NEC volumes |
|---|---|
| VA | PASS / PASS / PASS / PASS |
| VA2 | PASS / PASS / PASS / PASS |

All eight IPL runs started with no floppies and produced the same
[final screen](D4/dos-va-hdd.png): DOS banner, HDD AUTOEXEC marker,
C: prompt, correct C: label, and successful DIR A: after inserting a
floppy. The label precedes IO.SYS in the root. Each file size limits
traversal to at most 64 sectors and each read is 1 KiB aligned; a short
chain, an out-of-range cluster or missing end marker is fatal. The IPL
passes the target and IO.SYS derives its letter from mounted NEC units.

## M3 — Install from DOS

Boot a floppy with the matching VA system files and leave A: current.
Back up the disk before installing. `SYS C:` copies IO.SYS, MSDOS.SYS
and COMMAND.COM from the current drive and installs the IPL. It accepts
only a mounted, online NEC-layout unit and uses normal DOS file writes;
existing root entries and non-system files may remain. SYS asks for a
console confirmation before replacing any nonblank IPL other than the
exact one it would install. It refuses the current and boot drives.

`FORMAT C: /S` or `FORMAT /H0 /S` creates a fresh bootable filesystem
and retains the D3 confirmation and mounted-drive quarantine. The same
warning is shown before confirmation when FORMAT would replace a foreign
or older IPL. FORMAT stages the source files before making changes, then
writes their data, both FATs and the root through the SASI BIOS.
[F1](F1-small-fixes.md#1-system-file-dates) preserves the source
last-write dates and times in both commands, on SASI and floppy.
Both commands publish the new IPL last. Neither command is transactional on
error. `/H1 /S` can install on the second target, but to boot it in vaeg,
attach the resulting disk as target 0. Reboot after FORMAT. Neither
command installs CONFIG.SYS or AUTOEXEC.BAT; place them on the hard disk
if wanted. The stock prompt on an empty installation is `C>`; `PROMPT
$P$G` in AUTOEXEC.BAT displays `C:\>` at the root.

MASM 5.10 assembled the changed programs with zero warnings and errors;
LINK 3.65 reported only the expected no-stack-segment warnings. Used
vaeg m153 (640 KiB, initialized backup settings) on VA and VA2.

| Gate | VA | VA2 |
|---|---|---|
| Blank HDI, `FORMAT /H0 /S /V:D4HDD` | PASS: 5/10/20/40 MB | PASS: 5/10/20/40 MB |
| Mounted `FORMAT C: /S /V:D4HDD`; `SYS C:` on empty NEC volume | PASS: 10 MB both | PASS: 10 MB both |
| PC-Engine 1.1 media and NEC DOS 2.11, `DIR C:` and `TYPE C:\RESULT.TXT` | PASS: 40 MB | PASS: 40 MB |
| DOS floppy boot, bootable HDD attached, C: readable | PASS: 40 MB | PASS: 40 MB |
| HDD boot from target 0, target 1 mounted D: | PASS: 40 + 20 MB | PASS: 40 + 20 MB |
| SYS refusal: native-prefix FAT16 or unrecognized/blank disk | PASS: 10 MB / 5 MB | PASS: 10 MB / 5 MB |
| Cancel foreign IPL replacement, disk byte-identical | PASS: 5 MB | PASS: 5 MB |
| Confirm foreign IPL replacement with SYS | NOT RUN | PASS: 5 MB, including HDD-only reboot (Fix 1) |
| Raw `FORMAT /H1 /S` with target 0 present | NOT RUN | PASS: 20 MB; host confirmed target 0 unchanged |
| Raw FORMAT without `/S`: empty NEC root/FAT, IPL and data untouched | PASS: 5 MB | PASS: 5 MB |
| Fragmented IO.SYS, second root sector and high physical block, then a self-loop in that chain | NOT RUN | PASS: 40 MB, boot and bounded refusal respectively |

For each of the first two rows, cold-boot with no floppy, accept the
initial date/time prompts, insert a floppy in B:, COPY its marker to C:
and run CHKDSK. Copy the HDD AUTOEXEC.BAT fixture and write `BREAK=ON`
to C:\CONFIG.SYS; reboot with no floppies and check the HDD-only marker,
`BREAK` reports on, and DIR shows C:. The [gate table](D4/gate.tsv) gives
per-run CHKDSK and final free cluster counts (the two startup files each
consume one cluster). [Host verification](D4/verify-gate.py) compared
installed files byte-for-byte with the project source floppy and checked
both FATs and the reserved IPL.

Screens: [FORMAT](D4/format-va.png), [CHKDSK and COPY](D4/chkdsk-va.png),
[HDD reboot](D4/reboot-va2.png), [two targets](D4/dual-va2.png),
[SYS cancellation](D4/sys-cancel.png), [PC-Engine](D4/interop-engine.png),
[NEC DOS 2.11](D4/interop-nec211.png), [bad chain](D4/bad-chain.png).

## Fix 1 — Distribution build and floppy regressions

The D4 builder patch originally overlapped the D1 patch at the module
list. It now inserts the HDD IPL build before the floppy IPL build.
The scratch builder template needed the [D1 patch](D1/build-diskcopy.patch)
for `DISKCOPY.COM`; applied it first, then the D4 patch. The lock pinned
`components/msdos` to `3381f653c451187d3be338b44fc2955746d95d26` on
`topic/d4-hdd-boot`, release track `d4`, and retained emu2
`9d8698d06e67359bc8b230c2d19d5b1503e60819`.

On the initial full build (`9650b898`), `FORMAT B:` followed by `SYS B:`
reported success but standalone boot stopped at `Bad or missing Command
Interpreter` on both models. Floppy SYS now transfers `COMMAND.COM` as
well as `IO.SYS` and `MSDOS.SYS`. On the 256 KiB VA2, `FORMAT B: /S`
also failed with `Insufficient memory`: the shared loader required a full
64 KiB of free staging space before each read, even for smaller files.
It now measures each file first, checks its paragraph-rounded size
against the available memory, and requires an exact-length read.

The full emu2/NMAKE/MASM/LINK pipeline produced `msdos4-pc88va-2hd.d88`
(1,331,888 bytes), SHA-256
`c71b51cd45d38595376a5d9632af9b613b413d121ebeaa67c2b17e0be2dbda57`.
Read all 38 expected files back from the D88 and matched their lengths
and SHA-256 values against the builder's output manifest. This includes:

```text
APPEND.EXE ASSIGN.COM ATTRIB.EXE AUTOEXEC.BAT BACKUP.COM CHKDSK.COM
COMMAND.COM COMP.COM CONFIG.SYS COUNTRY.SYS DEBUG.COM DISKCOPY.COM
EDLIN.COM EXE2BIN.EXE FASTOPEN.EXE FC.EXE FIND.EXE FORMAT.COM IO.SYS
JFP.COM JOIN.EXE KEY.COM LABEL.COM LICENSE.TXT MEM.EXE MORE.COM MSDOS.SYS
NLSFUNC.EXE README.TXT RECOVER.COM REPLACE.EXE RESTORE.COM SHARE.EXE
SORT.EXE SUBST.EXE SYS.COM TREE.COM XCOPY.EXE
```

Regression gates used vaeg m153 and fresh emulator starts for each
boot. In the floppy runs no SASI disk was attached; the target moved
from B: to A: and booted with the second drive empty. Each target boot
showed the release banner, the expected DOS prompt and a successful
`DIR`.

| Distribution gate | VA 640 KiB | VA2 640 KiB | VA2 256 KiB |
|---|---|---|---|
| `FORMAT B: /S /V:FLOPPY`, boot target and check `FLOPPY` label | PASS | PASS | PASS |
| `FORMAT B:`, `SYS B:`, boot target without a separate `COPY` | PASS | PASS | NOT RUN |
| `DISKCOPY A: B: /V`, boot the copy | PASS | PASS | NOT RUN |
| Blank 40 MB HDI, `FORMAT /H0 /S`, boot HDD alone, then boot distribution floppy and `DIR C:` | PASS | PASS | NOT RUN |
| 5 MB PC-Engine 1.1 HDD, confirm `SYS C:` IPL replacement and boot HDD alone | NOT RUN | PASS | NOT RUN |

Both `DISKCOPY` runs reported `Copy complete.`; every copied track
matched the distribution's sector IDs, density and data (allowing for
sector rotation), and the source D88 was unmodified.

On the 5 MB VA2 run, the HDD booted PC-Engine to `Ready` before `SYS`.
MS-DOS then warned about the foreign IPL, accepted `Y` and reported
`System transferred`. The subsequent floppy-free boot reached `C>`;
all preexisting PC-Engine files were unchanged. On both 40 MB runs,
HDD-only boot reached `C>` and floppy boot with the HDD mounted reached
`A:\\>` with C: readable. Host checks matched the installed system files
to the distribution and verified both HDD FAT copies and the new IPL.

**NOT RUN:** real hardware, physical boot switches, and write-protect
and interrupted-write recovery.

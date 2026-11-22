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

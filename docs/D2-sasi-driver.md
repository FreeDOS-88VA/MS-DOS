# D2 — SASI through the PC-88VA hard disk BIOS

## M1: layout decision

The primary reference is **NEC PC-Engine 1.1 `HDFORM C:`** on VA2 (vaeg
m153). The m75 SASI harness started with an otherwise zero 40 MB HDI with
its own marker in block 0. HDFORM reported 40,435,712 bytes free. The
harness subsequently copied a file to C:, read it back in a separate
emulator process and compared the bytes, then deleted it. On a copy of
that disk NEC MS-DOS 2.11 PC-88VA booted from its original floppy and
`DIR C:` displayed an accessible, empty root directory. The 2.11 floppy
ships FORMAT and SYS but no separate FDISK; it has built-in SASI I/O and
fixed BPBs for four disk types. PC-Engine 1.00 and 1.05 also ship HDFORM;
their formatters were inspected, not run.

| Physical block(s), 40 MB | Meaning | Observed/inferred |
|---|---|---|
| 0–3 | 1 KiB reserved for IPL, no BPB or partition table | HDFORM left the harness marker untouched; no new IPL installed |
| 4–19 | FAT12 copy 1 | Media D3h; reserved entries followed by free clusters on format |
| 20–35 | FAT12 copy 2 | Same allocation data |
| 36–419 | Root directory | 3072 entries of 32 bytes; unused entries initialized by formatter |
| 420 onward | Data | 16 KiB clusters; 40435712 bytes in full clusters |

One implicit volume starts at block 0. Logical sectors are 1024 bytes
(four 256-byte SASI blocks); reserved sectors = 1; FATs = 2. No on-disk
partition fields or types were observed. The table below describes the
fixed 2.11 driver BPBs, not four independently formatted disks.

| Type | Media | Total logical sectors | Sectors/cluster | Sectors/FAT | Root entries |
|---:|---:|---:|---:|---:|---:|
| 5 MB | D0h | 4950 | 8 | 1 | 608 |
| 10 MB | D1h | 9900 | 8 | 2 | 992 |
| 20 MB | D2h | 19800 | 8 | 4 | 1504 |
| 40 MB | D3h | 39593 | 16 | 4 | 3072 |

**Alternatives.** PC-98 MS-DOS 3.3D Installation Guide, chapter 4,
“Preparing the fixed disk,” distinguishes physical initialization from
allocating an MS-DOS area and marking it bootable. This is the PC-98
IPL + separate partition-table family (CHS start/end and IPL location,
not a PC/AT MBR); the guide describes the user operations, not the byte
encoding. It is not what the tested NEC VA formatter wrote. The VA
Technical Manual §5.7.5 “HD interface” describes hardware compatibility,
not disk-format interchangeability. FreeDOS-88VA M17 “SASI native-prefix
fixtures” specifies a four-block IPL reservation and a 512-byte FAT12/16
VBR at block 4, with zero hidden sectors. That shares the reservation but
is **different** from NEC, which has FAT data at block 4. M19 banked-memory
notes, M19 and M20 reports do not establish native SASI compatibility.

**Decision for D2–D4.** Default to NEC's single-volume layout for VA
interchange; this is what D3 will write. Also recognize the FreeDOS
native-prefix profile without conversion (512-byte logical sectors;
power-of-two clusters up to 32 KiB). D4 can install the IPL within the
first 1024 bytes without moving either the NEC FAT or the FreeDOS VBR.
Physical initialization (FORMAT DRIVE) is separate from creating the
filesystem. D2 does not install the IPL or select an HDD boot target.
There is at most one volume per target: A/B floppy, then accepted SASI
targets 0 and 1 in that order. DOS SYSINIT raises a smaller LASTDRIVE
setting to at least the number of built-in units.

### Proposal (not implemented)

An opt-in `VASASI` table was considered for multiple volumes. It is not
recognized by D2, not planned for D3, and neither FreeDOS nor NEC uses it.

| Table offset in block 4 | Encoding |
|---|---|
| 0–7 | `VASASI`, version byte 1, zero byte |
| 8 onward | Four 12-byte slots in DOS enumeration order |
| slot +0 | Type (`00` unused, `01` FAT12, `06` FAT16, others unsupported) |
| slot +1…3 | Reserved, zero |
| slot +4…7 | Little-endian start in physical blocks, even and ≥6 |
| slot +8…11 | Little-endian length in physical blocks, positive and even |

The table occupies blocks 4–5. Non-empty extents may not overlap or
exceed the drive. Each supported extent contains a self-contained FAT
with 512-byte sectors. Clusters are powers of two in sectors; fixture
sizes follow the FAT12/FAT16 cluster-count split. This proposal has no
extended partitions, active flag, or PC-98 partition-table parsing.

## M1: BIOS probe (vaeg m153)

Sources: 602HDD §6.2.1 “Overview,” §6.2.2 “Status codes,” §6.2.3
“Function details” (SENSE, READ DATA, WRITE DATA, FORMAT DRIVE), §6.2.4
“Work area,” and the Technical Manual §3.7 “DMA memory access (V3 mode).”
INT 81h SENSE returns type 0–3 in AL; READ/WRITE use a block count in AL,
80h + target in BH for relative addressing, DL:CX for the block index,
and ES:BP for DMA. Commands 81h/82h suppress ROM retries. The manual
warns against DMA across the 1 MiB wrap and DMA to backup memory; this
driver additionally splits conventional-memory transfers at 64 KiB.
There is no documented write-with-verify command.

`tests/pc88va/HDPROBE.ASM` (DOS COM; destructive to synthetic block 0)
was assembled with MASM/LINK and run from a floppy with stdout
redirected to a binary file. An early version shrank the PSP allocation
without relocating SP and hung during DMA; results below are from the
version using a private in-allocation stack. A successful crossing read
is a status observation only, not a cross-page payload check.

| Model | HDI sizes | Results |
|---|---|---|
| VA | none | Both SENSE calls CF=1, AH=0Dh |
| VA2 | none | Same |
| VA | 5 / 10 / 20 / 40 MB | SENSE 0/1/2/3; aligned and page-crossing two-block reads, block-0 write/readback and last backing block read completed; target 1 SENSE CF=0 AL=FFh |
| VA2 | 5 / 10 / 20 / 40 MB | Same |
| VA and VA2 | 5 / 10 / 20 / 40 MB | An extra read one block past backing capacity did not return within the 1300-frame run (seven progress records visible); no BIOS error code observed |

See [probe records](D2/m1-probe.tsv). vaeg `fdd/sxsi.c` selects SASI
by geometry and 256-byte blocks. Its type-2 VA geometry is 615×4×33
(81180 blocks), not the manual's 308×8×33; CLI rejected a 308×8 HDI.
Use the smaller capacity to bound requests: 20,196 / 40,920 / 81,180 /
162,360 blocks for SENSE types 0/1/2/3 respectively. The other three
geometries agree (153×4×33, 310×4×33, 615×8×33). `cbus/sasiio.c` implements
DMA through channel 0, controller commands and status/IRQ; do not assume
it reproduces all physical format, seek or not-ready behavior.
A distinct not-ready state, write-protected image and real hardware:
**NOT RUN**.

## M2: read-only integration

`VAHDD.INC` probes SENSE before SYSINIT and only links the fixed disk
header when at least one volume is accepted. First check block 4 for
`D0h`–`D3h FFh FFh` and require the media byte to match the SENSE type.
Use the fixed per-type NEC BPB, mapping logical sector 0 to block 0.
Otherwise look for a FreeDOS-profile VBR (`EB xx 90` or `E9`, `55 AA`
trailer, 512-byte BPB, F8h media, two FATs, aligned fixed root, zero
hidden sectors, FAT12/16 cluster count and sufficient FAT capacity).
The declared volume plus the four-block prefix must fit the SENSE
capacity. An unreadable or unrecognized present target gets a boot
message and no drive letter. Track geometry in get-device-parameters
is logical; NEC uses 1 sector and 1 head, not physical CHS.

The driver checks the end of the logical request before converting it
to physical blocks (including DOS 4's long sector number). A valid
logical range is within the capacity established at discovery. DMA is
bounded by conventional memory and split at physical 64 KiB boundaries
and the ROM's 255-block count limit. A single 256-byte block straddling
a page uses a resident bounce buffer. Media check returns "not changed";
command 15 reports fixed media.

| vaeg m153 model | Attached image | Observed |
|---|---|---|
| VA and VA2 | 40 MB FreeDOS-profile FAT16 | DIR, TYPE marker, CHKDSK summary with no reported errors; COPY of 131,328 bytes to A: compared byte-for-byte |
| VA and VA2 | None | A: boots and C: is invalid; no SASI message |
| VA and VA2 | Blank/unrecognized 5 MB | Target 0 warning, no C: |
| VA and VA2 | 40 MB NEC HDFORM | DIR sees empty C:; stock CHKDSK rejects the 3072-entry root (its limit is 512) |

M2 did not test writes or real hardware. See M3 for NEC CHKDSK.

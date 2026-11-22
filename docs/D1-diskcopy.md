# D1 — BIOS floppy copying on the PC-88VA

## M1 inspection

`tests/pc88va/FDPROBE.ASM` runs from A: and issues non-retrying READ ID
calls against B:. `docs/D1/probe.py` builds the probe, boots it on VA and
VA2, and recovers the binary DOS redirection file from the boot disk.
`docs/D1/mkd88.py` creates original (non-DOS) test media. The gate is
an observed successful ID cycle or a recorded BIOS/emulator failure for
each sampled layout on both models. The first record is not necessarily
at index; the comparison allows rotation but not reordering.

### BIOS interface

References are to 601FDD, sections “Floppy Disk BIOS”, “Floppy Disk BIOS
Work Area”, and the final FM/MFM parameter tables.

- **SET DISK MODE** (0Ah, AL = mode, CH = unit) selects rotation, track
  density and FDC clock: 2D = 300 rpm/48 TPI/4 MHz, 2DD = 300 rpm/96
  TPI/4 MHz, 2HD = 360 rpm/96 TPI/8 MHz. 01h, 12h and 23h are valid
  default choices respectively. The low size bits do not limit N on
  explicit READ/WRITE DATA calls. 22h is the nominal 2HD 15 × 512
  format. The manual documents the 26 × 128 FM first track for **2HDs**
  (29h, with 26 × 256 MFM elsewhere), not as the 2D layout. `hd-fm`
  is a synthetic disk with that 2HDs geometry; `d16` is 2D 16 × 256.
- **READ ID** (85h): CH = unit, CL = physical cylinder × 2 + head in
  double-sided mode, DL bit 7 set for FM, clear for MFM. CF/AH give
  error status; AL/BH/BL give ST0/ST1/ST2; CH/CL/DH/DL give C/H/R/N
  on success. This returns a normal ID, not an index pulse or a
  count of revolutions. Repeated identical IDs cannot be distinguished
  reliably from a wrap with this interface. The probe stops at the
  first repeat of the initial tuple or after 42 calls.
- **READ DATA / WRITE DATA** (81h/82h, without BIOS retries): AL =
  count, DH = R, DL = N plus FM bit, ES:BP = DMA buffer. Physical
  location is independent of ID C/H when BIOSMODE.IDR is set and
  BH/BL supply C/H. `pc88va/VAFDXFER.INC` demonstrates checking
  the low 16 bits of the physical DMA address, not just the offset.
- **FORMAT TRACK** (83h without retries) takes the fill byte in AL,
  physical location in CH:CL, N and FM in DL, and a packed CHRN table
  at ES:BP with IDR set. GET BOOK (0Dh) returns the BIOS work-area
  pointer; documented BIOSMODE.PARM selects USERPARM (MAXCYL, EOT,
  RWGPL, FMGPL, DTL). The FDC receives one FORMAT N, sector count
  and gap for the whole track. An ID table can describe mixed N but
  does not select separate physical data field lengths during format.
  The ROM's format result check also compares N. The manual lists
  standard gaps by density/size, not a gap value recovered by READ ID.
- Positioning is implicit in the data, ID and format operations.
  **RECCALIBRATE** [manual spelling] (06h) moves the unit to cylinder
  zero, including a seek to cylinder 5 in its recovery sequence.
  **SENSE** (07h) returns ST3; **CHECK DRIVE READY** (08h) checks
  readiness; **CHECK DOOR OPENED** (09h) reports possible media change,
  not a definitive disk identity (especially when the motor is off).

### vaeg source inspection

This is source inspection, not proof that the supplied m153 binary
was built from the identical source. `fdd/fdd_d88.c` walks an ordinal
sector cursor for READ ID, wrapping on the D88 sector count, without
rotational timing. It checks the sector density flag and drive mode;
2D short tracks are mapped based on 48/96 TPI and whether the D88 is
already double-stepped. A D88 with a missing track pointer has no IDs.
Mixed N and independent C/H are represented in sector headers. Data
lookup matches all four ID bytes. D88 READ ID search is capped at 40
records; READ DATA copies bytes according to N but clamps the bytes
fetched from the image to its stored length.

`fdd/fdd_d88.c`'s format path stores ID N from the table but gives all
sectors a data field of the command's single N and leaves the D88 FM
flag clear. The read backend assigns the D88 status byte to
`fddlasterror`, but `io/fdc.c` does not turn it into a CRC result in
its normal READ DATA path. Its normal/deleted commands also share
implementation without modelling the D88 deleted-data mark. Thus
neither a CRC nor a deleted mark in a fixture proves the ROM error
path was exercised. SENSE and drive checks use the D88 write-protect
flag. `sdl2/debug_harness.c` provides `resource NAME PATH` followed by
`mount-fdd UNIT NAME`; a resource with path `none` ejects media.

### M1 gate: PASS (vaeg m153)

[READ ID rows](D1/m1-read-id.tsv) were identical on VA and VA2. The
DOS boot disk was the existing MS-DOS 4.00 J3b.4 build at `53f41e0e`;
its copy in scratch carried `FDPROBE.COM` and a no-op AUTOEXEC.BAT to
avoid the initial date/time prompts. MASM and LINK ran under emu2.

| Image | Mode | Sampled physical tracks returning a complete ID cycle (VA and VA2) |
|---|---:|---|
| hd77 | 23h | 11; sampled tracks 154, 158, 159 returned no IDs |
| hd80 | 23h | 14 |
| hc | 23h | 14 (15 × 512) |
| dd9 | 12h | 14 |
| dd8 | 12h | 14 |
| d16 | 01h | 7; other sampled addresses exceed the geometry |
| hd-fm | 23h | 14, including FM on track 0 |
| exotic | 23h | 13: track 0 mixed N/odd R, track 1 independent C/H and high R; track 2 has no IDs |

The CRC-marked data sector in `exotic` track 3 has a readable ID. This
run did not issue READ DATA. Both 01h and 12h yielded some IDs on each
of `d16`, `dd8`, and `dd9`; in particular the tested 2D disk has no IDs
on logical tracks 2–3 in 12h but does in 01h. A successful READ ID on
track 0 alone does not distinguish the media modes.

Real hardware, FORMAT/WRITE DATA, CRC data handling, media swap,
deleted-data copying, and protection schemes beyond the listed layouts:
**NOT RUN in M1**.

## M2 — Read-only track analysis

`pc88va/VADCOPY.ASM` builds as `DISKCOPY.COM` with MASM and LINK and
stripping the MZ header and 100h origin. `DISKCOPY B: /T` reads B:; keep
redirected output on a different drive. Preferred 2HD mode is tried
first if selected; the low-density probes check cylinder 1 in 2DD
mode to avoid mistaking an accessible 2D cylinder 0 for 2DD. This is
an inference, not physical media identification. Media with blank
initial cylinders can defeat auto-detection. Both MFM and FM are
tried on each track, assuming one encoding per track.

A track ends when the first full C/H/R/N identity repeats; an
out-of-order repeat or more than 40 distinct tuples is an error.
READ ID does not determine the original angular index or reliably
distinguish identical IDs. The conventional-memory buffer holds one
track, with each DMA slot physically 1 KiB aligned, so a single
128–1024-byte sector cannot cross a 64 KiB page. READ DATA uses a
single sector per call, IDR for independent C/H, and USERPARM for
non-standard R and N. The sector slot is cleared first; on Ignore,
any bytes actually DMA'd are retained. A failed layout scan is
reported and skipped after Ignore. An absent tail (77 vs 80
cylinders) looks like any other absent track and prompts too.

### M2 gate: PASS (VA, vaeg m153)

[`read_gate.py`](D1/read_gate.py) checks the complete diagnostic output
against the fixture: track count, density, ID sequence up to rotation,
ROM read status and a rolling 16-bit payload checksum per sector. The
read-only gate did not write the fixture image.

| Image | Tracks scanned | Sectors checked | Result |
|---|---:|---:|---|
| hd77 | 160 | 1,232 | PASS, ignored six absent tracks |
| hd80 | 160 | 1,280 | PASS |
| hc | 160 | 2,400 | PASS |
| dd9 | 160 | 1,440 | PASS |
| dd8 | 160 | 1,280 | PASS |
| d16 | 80 | 1,280 | PASS |
| hd-fm | 160 | 4,160 | PASS including FM/N=0 |
| exotic | 160 | 1,272 | PASS including mixed N, high R and independent C/H; ignored one absent track |
| exotic, Abort | 2 before error | 16 | PASS, returned to DOS after the track 02h prompt |

In `exotic`, the CRC-marked sector returned ordinary data and success
on m153. The actual CRC-error Ignore path and VA2 `/T` were **NOT RUN**.
The FDC trace on `hd80`, `hd-fm`, `d16` and `exotic` showed no READ DATA
DMA range crossing a 64 KiB page; the tested allocations did not span
multiple pages.

## M3 — Two-drive copy (amended gate)

The gate is a verified two-drive copy and D88 comparison for **each**
fixture, plus a copied MS-DOS disk that boots. `D1/copy_gate.py` checks
track presence, cyclic ID order, density, N and full sector bytes.
It ignores D88 status, write-protect and other metadata outside the
comparison (including the CRC and deleted-data flags). Debug
`mount-fdd` worked when the script waited for DOS to load the program
and for the emulator's delayed insertion before sending Enter.

The program selects the source mode and checks that it can configure
that mode on the target drive. If the target has enough readable IDs
to identify its mode and it differs, the program refuses the copy.
Otherwise it selects the source mode and allows FORMAT to try the
media; blank and unreadable media cannot be distinguished by this
probe. FORMAT uses user EOT as the number of IDs and a gap selected
from the manual's tables. `/V` compares a readback byte for byte.
Ignore on a mixed-N or unreadable ID track leaves the target track
untouched; Ignore on a data read writes whatever DMA supplied with
zeros for the bytes not transferred. The final incomplete summary
lists all affected tracks in hex. A skipped track is not erased:
use a blank target if it must remain unformatted.

| Case (VA, vaeg m153) | Observed result |
|---|---|
| hd77 | Tracks matched; program correctly reported incomplete after Ignore on 6 absent tracks |
| hd80, hc, dd9, dd8, d16 | Tracks matched and `/V` completed |
| boot | Tracks matched; copied disk booted to the MS-DOS 4.00 prompt |
| Target guards | Mode mismatch, write-protected target and missing target each produced the expected refusal; target seed bytes were unchanged. |
| hd-fm | **FAIL.** The FM FORMAT command (`0Dh` at the FDC) transferred all 26 IDs, but the target's density was `00h` instead of `40h`. The first FM verify read failed, and track 00h did not match. |
| exotic | PASS under amended gate: ignored mixed-N 00h and absent 02h; summary listed both. All remaining tracks matched, including the independent C/H and high R on 01h. |

Blank targets passed for `hd77`, `hd80`, `hc`, `dd9`, `dd8` and `d16`
(on m153) and `hd-fm` (on the fixed build below). All seven standard
fixtures were refused without changing a preformatted target of another
mode on m153: `d16` targets for all but `d16`, which used an `hd80`
target. The blank images had no tracks and the appropriate D88 type.

VA2 on m153: `hd80`, `dd9`, `d16` and `boot` passed `/V` and the
D88 comparison; `boot` also reached the DOS prompt on the copy.
Real hardware, a CRC data failure, deleted-data copying, recovery
by choosing Retry after inserting writable media, and copy protection
beyond the listed layouts: **NOT RUN**.

### vaeg FM format fix

`fix/d88-format-fm` commit `64e55e11` (based on `origin/main`
`3c2c9cd0`) sets the D88 density bit to the inverse of the FDC MF bit
in `fdd_formating_d88`, matching the READ ID and READ DATA checks.
The m153 comparison failed at track 00h; on the fixed SDL2 build,
`hd-fm` passed `/V` and matched on both a formatted and a blank
D88 target. No emulator changes were pushed.

## M4 — One drive

`DISKCOPY A: A: /V` reads a batch before prompting for the target.
Each record contains an encoding flag, a sector count, the data
segment and a packed ID table. Uniform sectors are aligned to their
own size (a power of two that divides 64 KiB); a format/verify slot
is reserved separately. The batch fills the available DOS allocation
up to the PSP's end segment, without splitting a track. The next track
that will not fit is read after the next SOURCE prompt. The two-drive
and `/T` paths still use one track of fixed 1 KiB slots.

The swap count excludes initial source insertion and restoration of
the DOS diskette. After answering N (or aborting), restore the system
disk before pressing Enter: a large copy can overwrite the transient
part of COMMAND.COM, which DOS then reloads. Always follow the SOURCE
and TARGET prompts; the BIOS cannot reliably identify two diskettes
of the same media mode. The fixed vaeg build's debug script can mount
images, but must leave time for delayed insertion and for `/V` to
finish before ejecting the target. `D1/swap_gate.py` checks the D88
layout and bytes after `/V`, checks the source was untouched, confirms
the configured RAM from the emulator log, and checks the return to
DOS after restoring the boot disk. It uses a blank target.

| Fixture | VA2 256 KiB | VA2 640 KiB |
|---|---:|---:|
| `d16` (2D) | PASS, 5 swaps | PASS, 1 swap |
| `dd9` (2DD) | PASS, 13 swaps | PASS, 3 swaps |
| `hd80` (2HD) | PASS, 25 swaps | PASS, 5 swaps |

[Gate output](D1/m4-results.txt). These six checks used the fixed SDL2
build (`64e55e11`). The other fixtures were not gated in one-drive mode
on the final build. The two-drive Y/N loop ran on m153 (two successful
copies, then N, then boot of the copied disk); `/T` also passed its
`exotic` and `hd-fm` comparisons on m153 with the final M4 binary.

## M5 — Builder integration

The builder template did not ship DISKCOPY. The Microsoft program in
`v4.0/src/CMD/DISKCOPY` uses generic track IOCTL and INT 13h; this port
instead talks directly to the ROM floppy BIOS. Apply
[`D1/build-diskcopy.patch`](D1/build-diskcopy.patch) with `patch -p1`
from the builder root, and update the `msdos` pin in
`experiments/msdos4-va/lock.json` to a source commit containing D1.
The patch adds VADCOPY to the existing MASM/LINK pass and installs the
origin-100h image as `DISKCOPY.COM`. No Microsoft source is changed.

The integration gate uses `D1/copy_gate.py run … --packaged` to boot
and exercise the generated distribution without injecting a replacement
COM or AUTOEXEC. On the boot case it also boots the target disk.
The scratch builder pinned `3480e45`. The COM extracted from its
D88 matched the independently assembled M4 executable byte for byte
and matched the builder's recorded SHA-256.

[Integration output and hashes](D1/m5-results.txt): all amended M3
cases passed on the distribution on the same model/build combinations,
including a boot of the copied distribution on both VA and VA2. The
known m153 FM format failure was not repeated here; the FM copies used
the fixed build. The first packaged `exotic` run stopped before copy
completion at the script's 4000-frame cutoff; it passed at 5400 frames
without rebuilding the image.

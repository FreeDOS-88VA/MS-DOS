# D5 — SASI dual boot

## M1 — Chain probe

**PASS:** on vaeg m153, both VA and VA2 booted to PC-Engine `Ready` and
ran `DIR` after chainloading, on copies of the 5 MB HDFORM volume.
Tested the 1.00, 1.05 and 1.1 system disks. `SYS C:` from 1.05 and 1.1
changed only blocks 0–1 of the zeroed IPL area; 1.00 also changed
block 3. The disk version and the banner version are not always the
same. See [VA](D5/probe-va.png) and [VA2](D5/probe-va2.png) for 1.1.

The direct boot traces start with the ROM reading blocks 0–1. The
loader then reads file data and filesystem metadata; the trace did not
show it fetching additional blocks from the reserved area. In the chain
run, the probe relocated a stub past the first 1 KiB, read a saved copy
of all four blocks back into 3000:0 with INT 81h, restored the D4
entry segment/flag conventions and jumped to offset zero. File reads
still came from the same SASI disk. Save all four blocks, not just the
two the ROM loads. See D4 for the ROM entry observations and Technical
Manual §6.2.3 (`602HDD.TXT`) for the disk BIOS calls.

## M2 — Three-way coexistence and the installation prerequisite

**Manual coexistence gate: PASS**, vaeg m153, VA and VA2, 640 KiB,
5 MB HDFORM-layout SASI. **The proposed add-version procedure without a
preparation step fails** on both models. No menu or installer was built
for this test.

### Files and boot lookup

Both the 1.05 and 1.1 system disks installed exactly these files on the
empty root, in addition to writing the IPL. Directory order was not
identical between VA and VA2.

| Root file | 1.05 attributes | 1.1 attributes |
|---|---|---|
| `ENGINEIO.SYS` | `27h` (archive, system, hidden, read-only) | `27h` |
| `PCENGINE.SYS` | `27h` | `27h` |
| `ADVGBIOS.SYS` | `27h` | `27h` |
| `PCENGINE.COM` | `21h` (archive, read-only) | `21h` |

Running 1.1 `SYS C:` with 1.05 still under the real names replaced the
installation on both models: all four names remained in the same root
slots, but their contents matched a fresh 1.1 install. No separate copy
of 1.05 was retained. This is the observed result, not a claim about
which internal delete/write operations SYS uses.

On VA, renaming only `PCENGINE.SYS` in a 1.05 install changed the HDD
boot from the 1.05 banner to the 1.0 banner; renaming only `PCENGINE.COM`
left the screen blank at the observation point. Renaming only
`ENGINEIO.SYS` or only `ADVGBIOS.SYS` still reached 1.05 `Ready` and
`DIR`; that test did not exercise the features those files provide.
This demonstrates boot-time name lookup for the first two cases, not
that all four files are necessary for `Ready`. Preserve all four as a
set. Use explicit installer labels: the 1.1 disk gave `v1.0` on VA, and
1.05 and 1.1 both gave `v1.1` on VA2. The host checks used the IPL and
file contents, not the banner alone, to distinguish the versions.

### Adding the second version

Tested on both models: after installing MS-DOS with D4 `SYS C:` and
parking all four 1.05 names on scratch, booting the 1.1 floppy and
running `SYS C:` returned `Ready` but left the entire HDD image
byte-identical. On separate scratch runs without MS-DOS files, it also
did not install with the names parked, including with free directory
slots first, with the parked files made visible, or with a zeroed IPL.
Do not interpret `Ready` as a successful transfer.

**Smallest tested workaround:** before booting the second PC-Engine
floppy, create four zero-length files in the root under the real names,
with the attributes in the table above, but only if the names are all
free. The test created the placeholders on the host after installing
MS-DOS and parking 1.05. 1.1 `SYS C:` then filled all four, wrote the
same IPL as on a fresh 1.1 installation, and left all four parked 1.05
payloads unchanged. Separate copies of the first payloads under the
real names also worked, but were unnecessary. No NEC code was patched.

Proposed installer change: add an explicit **prepare for another
PC-Engine install** operation from MS-DOS. Record preparation in state
before creating placeholders and keep the boot path on MS-DOS while
preparation is pending. On recapture, require a replaced IPL and a
complete, nonempty file set; do not capture leftover placeholders or
replace unknown files. Do not prepare as a side effect of choosing
MS-DOS at boot. Placeholder creation/cancellation and interruptions
need their own gate; the scratch test does not prove their crash safety.

- **Proposed flow (EN):** Boot MS-DOS and park the active PC-Engine set.
  Run the preparation operation, then boot the next PC-Engine floppy and
  run `SYS C:`. Boot the MS-DOS floppy and run `SYS C:` to capture the
  new set. The preparation operation is not implemented yet.
- **提案手順 (JA):** MS-DOS を起動し、使用中の PC-Engine システムファイルを
  退避する。追加インストールの準備を実行してから、別バージョンの PC-Engine
  フロッピーで起動し、`SYS C:` を実行する。MS-DOS のフロッピーで起動し直し、
  `SYS C:` で新しい版を登録する。追加インストールの準備機能は未実装。

### Startup-file observations and countdown (M2 only)

On both models, both PC-Engine installations reached `Ready` and ran
`DIR` with the distribution template's `CONFIG.SYS` (`FILES`, `BUFFERS`,
`LASTDRIVE`) and `AUTOEXEC.BAT` (`@ECHO OFF`, `PATH`, `PROMPT`, `VER`)
in the root. No startup-file swap was needed for those tested files.
With a second fixture, both versions read the `CONFIG.SYS` data sector
in the SASI trace and executed an `ECHO` marker from `AUTOEXEC.BAT`.
The `DEVICE=` line naming an absent driver did not report a visible
error; a read is not evidence of DOS-compatible directive parsing.
Do not assume arbitrary MS-DOS startup files are safe to share.

Use the *PC-88VA Technical Manual* §6.14.2, calendar-clock BIOS
(`614CALEN.TXT`), INT 8Ch/AH=02h, which returns hour, minute and second.
Measure elapsed seconds across minute/midnight rollover, with a bounded
fallback to MS-DOS for invalid or stalled time readings. For an emulated
10-second gate, use vaeg's virtual calendar, not host wall-clock mode.
Keyboard polling can use INT 82h/AH=0Ah followed by AH=09h only when a
key is available (Technical Manual §6.3.4, `603KEYB.TXT`); text output
uses §6.4. Countdown timing and key handling are **NOT RUN**.

### M2 gate evidence

On each model the scratch HDD held both sets and the MS-DOS system
files. Booted 1.1 after the placeholder-assisted install, then manually
changed only the PC-Engine directory names/hidden attributes and
selected the saved 1.05 IPL by restoring it to blocks 0–3. Both boots
ran `DIR`. The rename did not allocate or share clusters. A subsequent
MS-DOS floppy boot ran `CHKDSK C:`: both reported 616 total and 577 free
allocation units with no errors or lost chains.

| vaeg m153, 640 KiB, 5 MB | 1.05 | 1.1 | CHKDSK |
|---|---|---|---|
| VA | [PASS](D5/m2-va-boot05.png) | [PASS](D5/m2-va-boot11.png) | [PASS](D5/m2-va-chkdsk.png) |
| VA2 | [PASS](D5/m2-va2-boot05.png) | [PASS](D5/m2-va2-boot11.png) | [PASS](D5/m2-va2-chkdsk.png) |

**NOT RUN in M2:** product installer or menu, 40 MB, 256 KiB,
interrupted writes, real hardware, physical boot switches, and
coexistence with PC-Engine 1.00 (M1 tested chaining only).

## M3/M4 preflight — Capture recovery boundary

On vaeg m153 at 640 KiB, `HDFORM C:` on a fresh 40 MB HDI produced
an empty root and matching D3 FAT headers on both VA and VA2. In
separate runs, stock 1.05 and 1.1 `SYS C:` each populated the four
root files and booted from the HDD alone to `Ready`. The initial run
using reused 40 MB images did not transfer the files; those copies
lacked the NEC FAT headers and were not valid reference volumes.

On each valid 40 MB volume, installed 1.05, ran the **D4** MS-DOS floppy
`SYS C:`, then parked 1.05 and inserted the prepared placeholders by
editing the scratch root. The stock 1.1 floppy `SYS C:` filled all four
placeholders. Host checks matched the resulting IPL and four payloads to
the separate 1.1 install and all four parked payloads to the original
1.05 install. The next floppy-free boot went directly to PC-Engine and
ran `DIR` ([VA](D5/preflight-40mb-va.png),
[VA2](D5/preflight-40mb-va2.png)), even though the MS-DOS system files
were still on the disk. This was a manual reproduction, not a D5
capture or recovery run. Separate 5 MB runs at 256 KiB reached `Ready`
on VA and VA2 for both stock installers; these were not coexistence
runs.

### Gate decision (accepted in continuation 2)

The HDD-only recovery promise cannot cover **every point of capture**
with the specified installation procedure. The ROM enters the IPL from
blocks 0–1 (D4/M1). Stock `SYS C:` has replaced those blocks before
D5 capture starts. A marker in `BOOTMENU.DAT`, a backup of the DOS IPL,
or a journal elsewhere on disk cannot run until the ROM is once again
entering our IPL. At the first capture there need not be any MS-DOS
system files yet, so writing our IPL first does not provide a DOS
fallback either. The 40 MB add-version run above demonstrates the
handoff to the foreign IPL; it is not power-off injection.

Proposed gate split: for **prepare and menu switches**, keep the
HDD-only MS-DOS/recovery requirement. For **capture before the new IPL
is published**, require booting the MS-DOS floppy and retrying or
repairing `SYS C:` without loss of either PC-Engine file set. Once a
bootable D5 IPL is published, require HDD-only recovery again. If the
requirement is instead HDD-only recovery throughout capture, the
handoff must change so that the foreign installer never replaces the
ROM-visible dispatcher. Neither patching the foreign installer nor
changing the ROM is part of D5.

### M4 sequence (with preparation)

1. `HDFORM C:` → PC-Engine 1.05 floppy `SYS C:` → MS-DOS floppy
   `SYS C:` and label the first capture. Boot MS-DOS from the HDD menu
   to leave all real PC-Engine names free.
2. Prepare, cancel and verify only the zero-length placeholders were
   removed. Prepare again and verify HDD boot goes straight to MS-DOS
   with a note. Verify capture refuses the untouched placeholders.
3. Boot the 1.1 floppy and run `SYS C:`. Boot the MS-DOS floppy and
   capture with a distinct label. Check the saved IPLs and payloads
   after each transfer and run CHKDSK. Exercise interrupted prepare
   and interrupted capture separately from interrupted menu switches.

| vaeg m153 | 5 MB, 640 KiB | 40 MB, 640 KiB | 5 MB, 256 KiB |
|---|---|---|---|
| VA | M2 manual coexistence | Manual preparation + 1.1 install | Stock installers only |
| VA2 | M2 manual coexistence | Manual preparation + 1.1 install | Stock installers only |

The table above records only the preflight, not the product gate below.

## M3 — Implementation

The builder applies [the D5 patch](D5/build-boot-menu.patch) after D1
and D4. The four IPL blocks (1024 bytes) still contain the D4 DOS
loader. Byte 255 opts into the menu. `FORMAT /S` and plain DOS-only
`SYS` leave it off; neither a root scan for menu files nor model
probing runs on that path. When enabled, the IPL bounds FAT12 reads
and verifies the exact generated size and CRC of `BOOTMENU.SYS`
(2229 bytes in the fix-1 direct assembly; see fix 2 below). A missing, truncated or bad file falls
back to DOS. The stage runs at segment 3400h so it can restore the
selected saved IPL at 3000:0 using the entry convention verified in
M1. CRC-16 checks accidental corruption, not malicious image edits.

### On-disk state

Both files are in the root with read-only, hidden and system bits set
(the archive bit may also be set). `BOOTMENU.DAT` is exactly 4096
bytes, occupies one ordinary FAT12 cluster, and uses little-endian
words. Its layout:

| Offset | Bytes | Meaning |
|---:|---:|---|
| 0 | 4 | `VBM1` signature |
| 4 | 4 | Owner ID, last choice, phase (0 clean, 1 switch, 2 prepared, 3 capture, 4 active removal), pending target ID |
| 8 | 8 | Four root slot numbers reserved by `/P`, when prepared |
| 16 | 102 | Three 34-byte entry records (IDs 1–3); DOS is ID 0 |
| 118 | 1 | State version: 0 = original D5; 1 = replayable switch; 2 = per-system startup files |
| 119 | 1 | Switch flags: bit 0 preserves the previous default during SYS |
| 120 | 1 | Set during standalone capture to park the captured system's startup files |
| 122 | 16 | Version 2 startup journal: four `(root slot or FFFFh, CRC-16/IBM)` records, CONFIG then AUTOEXEC for the outgoing and incoming owners |
| 254 | 2 | CRC-16/IBM (initial 0) of bytes 0–253 |
| 1024 | 3072 | Three saved 1024-byte IPLs, in ID order |

Unused bytes are reserved. Each record is a NUL-terminated 16-byte
ASCII label (first byte zero means unregistered), the saved IPL CRC,
and four `(root slot, metadata CRC)` pairs. The latter CRC covers the
20 bytes after the name and attributes. File order is `ENGINEIO.SYS`,
`PCENGINE.SYS`, `ADVGBIOS.SYS`, `PCENGINE.COM`. Parked names are
`VAij0000.SYS`, where `i` is the persistent entry ID (1–3) and `j` is
the zero-based file index (0–3). Do not defragment/reorder the root or
edit these entries behind the installer; consistency checks refuse
ambiguous names or changed slots and boot DOS instead.

On the first capture, `SYS` stages the CRC-checked menu and state data
in two free clusters (free in both FATs) before allocating them. It
writes a temporary zero-length `BOOTMENU.JRN` entry in one of two
consecutive unused root slots. The entry records both cluster IDs.
Then it claims the two clusters in each FAT, publishes `BOOTMENU.SYS`
in the second slot, and replaces the journal with `BOOTMENU.DAT`.
Only FAT12 entries contained in a single physical block are selected.
On retry, the journal identifies and rechecks the staged contents
and lets SYS replay those claims before normal DOS file writes. Do
not run a DOS disk repair or write other files between interruption
and retry; a partially completed allocation can look like a lost
chain before SYS finishes it. Use a clean filesystem and back up the
disk before installing. The write-order guarantees assume atomic
256-byte physical-block writes; torn-sector behaviour was not tested.

A switch writes phase 1 and the target before changing any names. It
parks the owner's PC-Engine system files and activates the target's
(nothing for DOS), then parks the owner's startup files and activates
the target's. It commits the owner and last choice while clearing the
marker. The startup records are used only during an in-flight transaction:
a file may be created, deleted or edited between switches without changing
state. The CRC covers the attribute byte with the hidden bit masked off,
and the remaining 20 metadata bytes. A missing file is not a rename;
`FFFFh` records its absence. Duplicate, non-file or unexplained names
refuse the transaction. Renames set the hidden bit when parking and clear
it on activation, preserving all other attributes. Renames are in-place
updates of the name and attributes; no FAT or file-data sectors are
written. A repeat of the active and last choice writes nothing.
Refreshing DOS with `SYS` may park the active version, but preserves
its last menu choice. On the next HDD-only boot the stage checks for a
valid prefix of the ordered renames (all owner files park before any
target file activates), skips completed steps, and rolls forward before
showing the menu. Plain `SYS C:` and `/L` can also replay the marker.
An unexplained name, slot, attribute, record CRC, or FAT chain is a
read-only failure: the stage prints a warning and falls back to the DOS
loader. Such a fallback does not change ownership; the real startup names
may still belong to another system. Do not edit them until the disk has
been recovered. The chain walk requires exactly the number of clusters
implied by the file size and an end marker; it is bounded even on a cycle. Capture also checks
the incoming set and the registered sets it depends on.

Preparation writes phase 2 and four
reserved slots before creating zero-length files. In that phase the
HDD boots only DOS. Retry `/P` after an interrupted prepare, or use
`/C` to remove still-empty placeholders; neither operation overwrites
or deletes a filled placeholder. Raw state and root updates each
write a single 256-byte physical block.

Capture requires the four nonempty files with the expected attributes
and a foreign IPL. For additional entries the files must occupy the
slots recorded by `/P`. Confirm replacement only if these files and
the IPL are from the intended PC-Engine `SYS`; the project does not
fingerprint NEC binaries. The installer saves the full foreign IPL
before setting phase 3. For a standalone capture it snapshots the
startup files in that phase as well. The phase-3 journal is published
before DOS file transfer, so even a retry after installing `IO.SYS`
uses the original ownership decision. SYS then parks the four system
files and any captured startup files. It commits the new default before
publishing our IPL. Publication writes blocks 2–3
first, then block 0 alone; block 1 is left untouched and our loader
ignores it. Until block 0 changes, the ROM still enters PC-Engine's
IPL; some of the files it expects may already be parked. Boot the
MS-DOS floppy and rerun `SYS C:` to resume the allocation, a committed
phase-3 capture, or a capture parked before publication. Recover
before using the HDD from other software. With a foreign or blank IPL,
the transfer of `IO.SYS`, `MSDOS.SYS` and `COMMAND.COM` is ordinary DOS
file I/O. Back up the disk first.

M2 found that stock PC-Engine 1.05 and 1.1 `SYS C:` install four system
files, not `CONFIG.SYS` or `AUTOEXEC.BAT`. For a prepared capture the
real startup names still belong to DOS, so the newly added entry starts
empty. For a first capture without menu state, if neither DOS kernel
name (`IO.SYS` or `MSDOS.SYS`) exists, the root startup files are treated
as the standalone PC-Engine installation's; DOS starts empty. If either
DOS kernel name exists, SYS conservatively keeps the root pair with DOS.
Back up and move the files yourself if that heuristic does not describe
your disk.

### Refresh and upgrade

`FORMAT /S` puts both DOS kernel entries in one 256-byte root block,
even with a volume label. SYS refresh publishes both replacements in
one physical write, allocating missing entries and relocating a
straddling entry as needed. Capture and `SYS /P` also try to group the
entries; capture reports success with a warning if already committed but
neither kernel block has a vacancy. Free an entry in one of those blocks
(e.g. move a file into a subdirectory) before the next refresh. SYS never
moves a user's or PC-Engine's entry to make room.

**Fix 5 is not release-ready.** The current implementation still uses
fix 4's out-of-volume log. Do not run this SYS on a real SASI disk:
blocks beyond the volume may contain HDFORM alternate tracks, even if
an emulator fills the same addresses with `E5`.

Fix 4 reserves up to 40 physical blocks immediately beyond the fixed NEC
BPB's last logical sector. These blocks are outside the DOS volume, but
within the supported SASI capacities (see [D2](D2-sasi-driver.md)). SYS
claims this space only if blank or already marked as its own. The redo
area holds a CRC-checked table of destination blocks and pre/post CRCs,
the final 256-byte metadata images, and the original block 0 as the last
image. There is no change to the on-volume geometry.

1. SYS checks all three source files, FAT agreement, destination root
   slots and cluster capacity before staging. A small transaction then
   creates a hidden, system, read-only `VASYS.JRN` with a real FAT chain
   for the payload. Interrupted staging leaves an ordinary allocated
   file, not free clusters DOS can reuse; SYS can reuse this reservation
   on retry with the same floppy. Do not modify or delete `VASYS.JRN`.
2. SYS writes the three source files into the reservation. A second
   transaction splits its chain among the replacement files, publishes
   the names, and removes the reservation and the accounted old chains.
   A broken old chain (e.g. bad size or cycle) is not freed; SYS leaves
   the superseded DOS chains allocated in that case and asks the user
   to run CHKDSK. The operation does not attempt a general FAT repair.
3. For each transaction SYS writes the complete redo log and a helper
   in reserved IPL block 1 (ignored by a normal DOS IPL), then arms
   replay by writing block 0. The target-0 ROM loads both blocks. The
   replay code validates the entire log and requires each live block
   to match its recorded before or after CRC before writing anything.
   This avoids clobbering a DOS write made after a cut. The final write
   restores block 0. This assumes atomic 256-byte SASI writes. Block 1
   retains the helper after a successful transaction. D4-era SYS
   compares all four IPL blocks against its own and will warn that
   this IPL is foreign, even on a plain DOS disk.
4. If replay fails, the temporary IPL tells the user to boot the DOS
   floppy and run `SYS C:`. If both FATs agree and the DOS files, staging
   reservation (if present) and menu state are structurally consistent,
   SYS rebuilds the reserved IPL area with the D4-style DOS or D5 menu
   loader and continues. Missing DOS directory entries do not by
   themselves block this repair; plain SYS installs the missing files
   from the floppy. If the recovery checks fail, do not write to this
   drive; restore a known good backup. Do not run CHKDSK during a pending
   transaction. The recovery checks are not a full volume check.

After an interruption, boot the HDD directly as SASI target 0 if the
DOS floppy has been removed. Otherwise run this distribution's `SYS C:`
from the floppy **before writing to C:** or running CHKDSK repair. Never
run D4 or fix-1/2/3 SYS on a disk with an armed transaction. The new SYS
can replay an intact fix-3 log or recover its IPL after log loss, and
also recognizes the older fix-1/2 `VASYS.JRN` format.

Target 1 (normally D:) has no pre-boot replay or automatic access block.
C: can still boot and report D: as mounted even if a D: transaction is
partially replayed. Do not access D: in that case; rerun `SYS D:` from
this DOS floppy before using the drive.

中断後にフロッピーから起動した場合は、C: への書き込みや CHKDSK での修復より
先に、本配布版の `SYS C:` を実行してください。更新途中には旧版 SYS (D4、fix
1～3) を使用しないでください。SASI 装置 1 (通常 D:) は自動復旧しません。
中断後は D: にアクセスする前に、フロッピーから `SYS D:` を再実行してください。

New SYS must recognize the old IPL, validate and retain the old state
entries, and install a matching IPL and stage as a pair. D5 releases
share the same DOS loader and differ only in IPL block 0. On the next
plain `SYS C:` from the new DOS floppy, a fix-1 installation upgrades
to version 2 without changing the saved IPLs or the menu default. Root
startup files are assigned to the owner recorded by fix 1 (after replay
of any pending fix-1 switch). If SYS then parks that owner to restore
DOS, it parks that owner's pair in the same switch. SYS writes the new stage, updates its length in the root,
then commits block 0 and the state version. Until publication a stage
length or CRC mismatch falls back to DOS; retry with new SYS. A future
format change must migrate the state explicitly and must not assume a
new IPL layout can be published in the same order. The old format did
not distinguish a SYS-initiated pending switch from a menu selection.

### Fix 5 partial verification — gate failed

On 5 MB vaeg scratch images, an intentionally damaged first-armed log
and a deleted `IO.SYS` (VA/D4) or `MSDOS.SYS` (VA2/D5) recovered with
floppy `SYS C:`, then booted from HDD and passed guest CHKDSK. The patched
VA/D4 refresh trace had no duplicate root-chain ownership at any of its
441 physical write prefixes. At write 439, CHKDSK returned after `N` to
its lost-chain prompt, but still reported invalid entries and lost
chains. The old and new FAT entries can share a physical block, so
coalescing their updates can free the old chains before switching the
names. This is not the all-prefix consistency gate.

CHKDSK follow-up: on the same plain VA/D4 volume, an extra root entry
pointing at the existing `IO.SYS` chain (without changing either FAT or
any other file) made floppy CHKDSK stop after the volume label for the
rest of a 4,800-frame run. The unmodified fixture completed CHKDSK and
returned to the prompt. No SYS transaction was active in either run.

[VA2 Japanese redo-failure message](D5/fix5-redo-failed-ja-va2.png).
These were scratch test floppies with a rebuilt SYS, not new releases:
English SHA-256 `ee61881b0a746dbe7669d454462894124a7928a931bb607d69afce6bb6440ada`;
Japanese SYS SHA-256 (floppy image)
`6c74b1eb520f9eebd32e56fa4599f96e436956d385d658899c69f0fad0f11ad3`.
The missing-file traces still had 13 (VA) and 12 (VA2) out-of-volume
writes. FAT-owned redo, stale-reservation resizing, and the full
fix-5 distribution gate are outstanding. In particular, a legacy disk
without an owned log file needs a bootstrap protocol: the two FATs and
root entry cannot be published by one 256-byte write. Merely moving the
initial redo log to a free cluster leaves it vulnerable to a DOS write
before that reservation is published. The replacement must ignore any
old tail marker and leave those blocks untouched.

### Clock and model display

The timeout uses the calendar BIOS, *PC-88VA Technical Manual*
§6.14.2 (`614CALEN.TXT`), INT 8Ch/AH=02h. It counts elapsed seconds
modulo 60 (including minute and midnight rollover). It waits for eleven
second boundaries, so ten full seconds pass even if the first boundary
is immediate. Invalid readings or a bounded poll loop expiring fall back
to DOS. Keyboard uses §6.3.4 (`603KEYB.TXT`): INT 82h/AH=0Ch flushes
the primitive buffer after the menu is drawn, AH=0Ah polls it, and
AH=09h consumes a key. Text output uses INT 83h, §6.4; the prompt
counts down in place.

The model text uses the text VRAM aperture, not firmware bytes:
*PC-88VA Technical Manual* §§3.3 and 4.2.1 document selecting text
VRAM with port 153h and the original VA's 64 KiB aperture. NEC's
[VA2](https://support.nec-lavie.jp/support/product/data/spec/cpu/b048-1.html)
and [VA3](https://support.nec-lavie.jp/support/product/data/spec/cpu/b049-1.html)
specifications list 256 KiB, versus [64 KiB for the VA](https://support.nec-lavie.jp/support/product/data/spec/cpu/b047-1.html).
The bounded probe saves the bank and a word in the upper aperture,
tests two values, then restores both. The labels are `PC-88VA` when the
upper aperture is absent, `PC-88VA2/VA3/VA-91` when present, and
`PC-88VA?` when inconclusive. No expansion-ROM port is used to identify
a VA-91.
No entries are filtered by model. vaeg m153 offers `va` and `va2`
(`sdl2/cliopts.c`, `sdl2/np2.c`). The VA-91 code in `io/va91.c` is not
a selectable SDL2 model in that build. VA3 (distinct hardware) and
VA+VA-91: **NOT RUN**.

### User procedure (EN)

1. Back up the SASI disk. On a fresh disk use PC-Engine `HDFORM C:` and
   PC-Engine 1.05 `SYS C:`. Boot the project DOS floppy and run `SYS C:`.
   Confirm the replacement and enter a label such as `PC-Engine 1.05`.
2. Put this distribution's `SYS.COM` on the HDD (`COPY A:\SYS.COM
   C:\SYS.COM`) if you intend to run the maintenance switches without
   the floppy. Each system owns its own optional `CONFIG.SYS` and
   `AUTOEXEC.BAT`. A first capture from standalone PC-Engine keeps its
   root pair for that entry if no DOS kernel names exist; otherwise the
   root pair stays with DOS. An additional PC-Engine entry starts empty:
   stock 1.05 and 1.1 `SYS C:` don't install these files.
3. Boot **MS-DOS** from the HDD menu to free the real file names. Run
   `SYS C: /P`. Then boot the PC-Engine 1.1 floppy and run its `SYS C:`.
   Boot the project DOS floppy and run `SYS C:` again; label the new
   entry `PC-Engine 1.1`. The new entry is the first default.
4. A digit boots immediately; Enter or the 10–11 second timeout boots
   the default. `SYS C: /L` lists persistent IDs (menu digits may differ
   after removal). Use `SYS C: /C` before installing to cancel preparation,
   or `SYS C: /D n` to unregister ID `n`, even if its files are missing.
   `/D` retains parked system and startup files. Select MS-DOS before
   unregistering a healthy active set. If removing the active entry,
   `/D` journals parking its startup files and restoring DOS's, but
   leaves the PC-Engine system files alone. Back up and move any real
   PC-Engine system files left behind before using the menu again.
5. Edit or create the real startup files while booted into their owner.
   From MS-DOS, `SYS C: /L` shows the names for other entries, e.g.
   `VACFG1.SYS` and `VAEXEC1.BAT` for ID 1 (DOS uses ID 0). You can edit
   or create those files directly, using an editor that can open hidden
   files or temporarily clearing `ATTRIB -H`. Set `ATTRIB +H` on the
   parked files afterward. The menu never deletes or overwrites them.
   Upgrade fix 1 with plain `SYS C:` from the new DOS floppy before using
   the new maintenance options; the recorded owner keeps the old pair.

PC-Engine 1.05 is for the VA; 1.1 is for the VA2. On the other model,
PC-Engine can display the built-in version instead of the disk version.
Check the selected label and the installation, not just the banner.

### 利用手順 (JA)

1. SASI ディスクをバックアップします。新規のディスクには PC-Engine で
   `HDFORM C:` を実行し、1.05 で `SYS C:` を実行します。本配布版 MS-DOS
   のフロッピーで起動して `SYS C:` を実行し、IPL の置き換えを確認して
   `PC-Engine 1.05` などの名前を登録します。
2. HDD だけで保守コマンドを使うには、`COPY A:\SYS.COM C:\SYS.COM` で
   本配布版の SYS を HDD に置きます。`CONFIG.SYS` と `AUTOEXEC.BAT` は
   システムごとに管理し、どちらも省略できます。初回登録時、DOS のカーネル名が
   どちらもなければ既存の起動設定は PC-Engine に、それ以外の場合は MS-DOS に
   引き継がれます。追加登録した PC-Engine の起動設定は空です。1.05 と 1.1 の
   純正 `SYS C:` はこの 2 ファイルを作成しません。
3. HDD メニューで **MS-DOS** を選び、PC-Engine のファイルを退避します。
   `SYS C: /P` を実行してから、PC-Engine 1.1 のフロッピーで起動し、
   その `SYS C:` を実行します。MS-DOS フロッピーで起動し直し、`SYS C:`
   で `PC-Engine 1.1` などの名前を登録します。登録直後は新しい項目が
   既定値です。
4. 数字キーで直ちに起動します。Enter または 10～11 秒経過で前回の選択が
   起動します。`SYS C: /L` は登録 ID を表示します (メニューの番号とは
   異なる場合があります)。準備の取り消しは `SYS C: /C`、登録解除は
   `SYS C: /D n` です。退避したシステムファイルと起動設定ファイルは残ります。
   通常は MS-DOS を選んでから登録を解除してください。使用中の項目を解除すると
   起動設定は退避され、DOS の設定が戻りますが、PC-Engine のシステムファイルは
   移動しません。元の名前で残ったファイルはバックアップ後に移動してください。
   登録処理が中断した場合は MS-DOS フロッピーから再起動し、他の書き込みや
   ディスク修復をする前に `SYS C:` を再実行します。
5. 使用中のシステムでは通常の名前で編集・作成できます。別のシステムの設定は
   MS-DOS で `SYS C: /L` が表示する退避名 (ID 1 なら `VACFG1.SYS` と
   `VAEXEC1.BAT`、MS-DOS は ID 0) で編集・作成できます。必要に応じて
   `ATTRIB -H` で隠し属性を外し、編集後に `ATTRIB +H` で戻します。
   fix 1 から更新するときは、新しい DOS フロッピーから `SYS C:` を実行します。
   既存の起動設定は、記録されていた所有システムに引き継がれます。

1.05 は VA 用、1.1 は VA2 用です。別の機種で起動すると、ディスク版と
異なる本体内蔵のバージョンが表示されることがあります。

## M4 — Original D5 gate results (before fix 1)

The D1 → D4 → D5 builder with MASM 5.10 and LINK 3.65 built source
commit `7835850` into a 1,331,888-byte D88 with SHA-256
`77b14f6aaa92e1e909dd6579e252812af7c5f8bec831615248ade2df9ba97d2e`.
The assembled IPL and stage match the direct assembler build used
in the fault tests.

vaeg m153, virtual calendar, HDD target 0. For 5 MB the starting
1.05 image came from the M1 `HDFORM`/`SYS C:` scratch fixture. For
40 MB the gate ran `HDFORM` on fresh blank images and each stock
installer. All captures below used the DOS `SYS` on the emulator;
the images were not assembled on the host. The host compared the IPL
and all four payloads at capture and after each switch, and checked
both FATs; [the independent checker](D5/check-menu.py) also checks
for lost or shared clusters and validates ownership and directory slots.

| Model | SASI | RAM | Two captures, prepare/cancel, three choices, persisted timeout, removal | CHKDSK free clusters after capture / removal |
|---|---:|---:|---|---:|
| VA | 5 MB | 640 KiB | PASS | 571 / 571 |
| VA | 40 MB | 640 KiB | PASS | 2440 / 2440 |
| VA2 | 5 MB | 640 KiB | PASS | 571 / 571 |
| VA2 | 40 MB | 640 KiB | PASS | 2440 / 2440 |
| VA2 | 5 MB | 256 KiB | PASS | 571 / 571 |

The normal sequence left all four placeholders empty before stock
1.1 `SYS`, showed DOS-only while prepared, and refused to capture
untouched placeholders. Digits exercised `1.05 → 1.1 → MS-DOS → 1.05`;
PC-Engine ran `DIR`, DOS booted to `C:\>` with shared startup files,
and the keyless restart selected the saved default without changing
any bytes. Enter on VA and VA2 also chose the displayed default
without writing. From the first keyboard poll to the timeout's switch call,
separate measurements observed 519 frames (9.20 s) on VA and 545
(9.66 s) on VA2 at vaeg's 56.4 Hz virtual calendar. Second-boundary
sampling accounts for up to one second of quantization.

Screens: menu [VA](D5/menu-va.png) / [VA2](D5/menu-va2.png),
[1.05 on VA](D5/switch-va-engine105.png),
[1.1 on VA2](D5/switch-va2-engine11.png),
[DOS at 256 KiB](D5/switch-va2-dos-256.png),
[40 MB CHKDSK](D5/capture-chkdsk-va2-40.png).

### Interruption tests

The debugger killed only the emulator started for each test, breaking
before a selected `sxsi_write` so earlier 256-byte writes had completed.
These are write-boundary cuts, not torn writes. In VA 5 MB initial
capture, six cuts sampled staging, the two FAT copies, root publication,
parking, and the write that would replace block 0. Every retry from the
DOS floppy installed one entry with the original IPL and clean CHKDSK.
On VA2 at 5 MB/640 KiB a cut during placeholder creation left the HDD
bootable in DOS-only mode; `/P` resumed and `/C` safely cancelled it.
Two cuts during a third capture (after the phase-3 marker and after a
rename) resumed from the DOS floppy with exactly three registered
entries and clean CHKDSK. `/P` refused the full table without
changing the disk.

For menu switches, VA and VA2 at 5 MB/640 KiB each passed three cuts
(after the marker and after further root writes). Reboot fell back to
DOS. Host byte differences were confined to marker bytes and root
name/attribute fields; the next floppy DOS `CHKDSK` was clean.

### Fallback and regressions

- VA and VA2, 5 MB: removed or truncated stage, CRC-damaged stage,
  and truncated or CRC-damaged state all fell back to DOS without a
  menu or a disk write. SYS refused a missing PC-Engine file without
  changing the disk. On VA2 a pre-DOS screen capture verified both
  the prepared and damaged-stage notes. DOS may overwrite that
  screen area during initialization.
- VA and VA2, 40 MB: `FORMAT /H0 /S`, HDD-only boot with no menu,
  followed by floppy boot and `DIR C:` passed. Both FAT copies and
  the installed DOS files matched the build. On VA and VA2 at 640
  KiB, and on VA2 at 256 KiB, `FORMAT B: /S` and `FORMAT B:` then
  `SYS B:` both produced independently bootable floppies.
- Refresh from the DOS floppy with 1.05 active parked the real names
  and kept default 1.05. A second refresh left `BOOTMENU.DAT`
  byte-identical. The Japanese catalog applied to a disposable export;
  the translated `SYS` assembled and linked.

### Remaining coverage

**NOT RUN:** real hardware, physical boot switches, distinct VA3,
VA+VA-91, torn sectors, PC-Engine 1.00 coexistence, 10/20 MB D5 menu
runs, and a full Japanese distribution boot. See the model detection
notes above for why VA-91 is not identified by an expansion indication
alone.

## Fix 1 verification

The D1 → D4 → D5 builder assembled `618e2c7` into a 1,331,888-byte
D88 with SHA-256
`ccf6c8b477093af3408bd931186f8517fc36942099e3c11a80a4bf6963fa198b`.
The rebuilt distribution passed HDD-only `FORMAT /H0 /S` boot on VA
and VA2 (40 MB), and both 2HD `FORMAT B: /S` and `FORMAT B:` + `SYS B:`
booted on VA/640 KiB and VA2/640 and 256 KiB. The builder's file
manifest was verified against the disk contents. The complete M4
three-way sequence passed on VA and VA2 at 5 and 40 MB/640 KiB and
on VA2 at 5 MB/256 KiB. The independent image checker passed on all
five resulting three-way volumes.

With a digit queued at frame 400, the default booted unchanged. From
first poll to selection the vaeg m153 virtual calendar measured VA
569 frames (10.09 s) and VA2 594 frames (10.53 s), at 56.4 Hz.
On both models a cyclic PC-Engine chain fell back to DOS without any
write. Capture also refused an incoming cyclic chain without writing.
`/D` unregistered an entry with a missing file and changed only the
state block. A stray `BOOTMENU.SYS` on D4 did not block a
refresh. A simulated original D5 installation upgraded on both models
with saved IPLs, records, and the default intact.

All 76 debugger cuts in the switch matrix passed: after the marker
and after every root write for 1.05 → 1.1, 1.1 → DOS, and DOS → 1.05,
on VA and VA2 at both 5 and 40 MB. HDD-only boot replayed before
displaying the menu, the complete image matched the expected switched
image, and guest CHKDSK was clean. A pending switch also replayed
with `SYS C: /L` (VA) and plain `SYS C:` (VA2). On VA2 an out-of-order
root change fell back to DOS and left the image unchanged.

Eight representative refresh cuts covered D4 and D5 across VA/VA2 and
5/40 MB, including before and after publishing the kernel pair and
before removing the journal. The next HDD boot reached `C:\>`; retry
from the floppy completed the update and CHKDSK reported no lost
chains. Separately, actual SASI writes from all eight combinations of
VA/VA2, 5/40 MB, and D4/D5 were replayed into host-side snapshots (477
writes per 5 MB refresh, 453 per 40 MB). After every write, FAT1 resolved
both kernel files to the old or the new pair, and `COMMAND.COM` remained
loadable. This was a trace check, not an HDD boot and guest CHKDSK after
every write.

**NOT RUN:** exhaustive guest refresh cuts at every write, and the
original capture/prepare cut matrix on this build. The refresh layout
limitation above remains; this is not a pass of the full fix-1 gate.

## Fix 2 verification

MASM 5.10 / LINK 3.65: the IPL is still 1024 bytes. The stage is 2968
bytes (was 2229), still three 1024-byte logical sectors and within the
same single-cluster and loader limits. The Japanese ASM catalog applied
and translated `SYS` assembled and linked. The D1 → D4 → D5 builder
built `8cd9c51` into a 1,331,888-byte D88 with SHA-256
`e9d0c9474e64f1437009e1eb6b762cfe202dcdfab0b371d29b4715f6f2c1dd5e`.
Its IPL, stage, `SYS.COM` and `FORMAT.COM` match the direct build used
in the tests byte for byte.

On vaeg m153, VA and VA2 passed the full two-capture sequence at both
5 and 40 MB (640 KiB), including prepare/cancel and a keyless restart.
A standalone first capture parked its existing pair; the prepared 1.1
capture kept the DOS pair in place and started empty. Booting 1.1 with
only an `AUTOEXEC.BAT` ran `11` and the file stayed with 1.1 on the next
switch. Once all three pairs were populated, all six switch directions
ran the selected `DOS`, `105` or `11` marker. DOS `TYPE CONFIG.SYS`
showed `FILES=27`; host checks matched the other two distinct `FILES=`
fixtures to their owners. CHKDSK passed after the captures and again
after `/D` (567 free clusters at 5 MB; 2436 at 40 MB). On each model a
separate 5 MB test created `AUTOEXEC.BAT` from the DOS prompt on a
system with no pair. The next switch parked it and a return to DOS ran
its `CREATED` marker, with `CONFIG.SYS` still absent.

For `1.05 → 1.1`, `1.1 → DOS`, and `DOS → 1.05`, on both models at
both sizes, replayed durable snapshots after the marker and each root
write from actual SASI write traces (124 cuts). Every HDD-only reboot
rolled forward before showing the menu, and the complete image matched
the committed switch. The independent checker verified FATs, file chains
and all six startup files in those committed images. Guest CHKDSK was
not rerun on each identical replay image. A real debugger kill on each
model at 5 MB, after parking the old pair and before activating the new
one, produced the same snapshot and also recovered HDD-only.

On vaeg m153 at 640 KiB, a fix-1 image with the 1.05 entry owning the
real pair upgraded on both VA and VA2 using plain `SYS C:`. The test
used the actual fix-1 IPL and stage with version-1 state. Saved IPLs,
entry records and default were unchanged, and `105` ran after the next
menu selection. A digit queued at frame 400 was ignored. Timed from
first keyboard poll to selection, VA waited 574 frames (10.18 s) and
VA2 599 frames (10.62 s) at 56.4 Hz.

On both models one 5 MB refresh cut each on D4 and D5 (after SASI
write 430) left an HDD that reached DOS; retry from floppy passed
CHKDSK. D4 had no menu. Both `FORMAT B: /S` and `FORMAT B:` followed
by `SYS B:` produced independently bootable 2HD floppies on both
models. Active `/D` parked the removed entry's startup files, restored
the DOS pair and left its four PC-Engine system files untouched.

**NOT RUN:** a new exhaustive capture/prepare or refresh-cut matrix,
active-removal cut injection, torn writes, or physical hardware.

## Fix 3 verification

The D1 → D4 → D5 builder rebuilt `2513ffc` into a 1,331,888-byte
`msdos4-pc88va-2hd.d88` with SHA-256
`d881e9f701ab21677626ca0dcd48a9dc78e291be64b0429ca119c3f9816e7748`.
The permanent IPL and menu stage are unchanged (1024 and 2968 bytes).
The Japanese catalog applied in a disposable export and the translated
SYS assembled and linked with MASM 5.10 / LINK 3.65. SASI SYS stages
one source file at a time; it reuses that buffer for metadata planning
rather than requiring space for all three source files at once.

On vaeg m153, VA and VA2 (5 MB, 640 KiB), a first capture without
startup files put the kernel entries in slots 6/7. Repeating the
reviewer's `ECHO FILES=30>C:\CONFIG.SYS` case put them in slots 10/8
instead of 7/8. Both layouts refreshed from the rebuilt floppy, passed
CHKDSK and booted MS-DOS from HDD. An aligned plain 40 MB disk also
refreshed; a separate VA2 `FORMAT /S` with a label put the kernels at
slots 1/2 and booted without a menu. On a straddling 5 MB volume with
neither block vacant, SYS refused without writing; deleting a file in
one of those blocks let the next SYS complete.

Power-loss simulation used the durable prefix after every 256-byte
write captured at vaeg's SASI write boundary. For each prefix the host
checked the live volume (or the volume obtained by applying the armed
redo table): equal FATs, no lost or cross-linked chains, no duplicate
root names, and file bytes matching either the old or the new DOS set
with non-DOS files unchanged. Guest boots with CHKDSK covered every
armed prefix plus one example of each distinct unarmed layout/boot set.
Unarmed prefixes that differed only in unused staging data did not get
separate guest boots.

| vaeg, 640 KiB | Starting volume | Host snapshots | HDD-only boots + CHKDSK |
|---|---|---:|---:|
| VA, 5 MB | Actual fix-2 capture, slots 7/8 | 434 | 10 (3 relocation, 4 refresh, 3 unarmed) |
| VA2, 5 MB | Actual fix-2 capture, slots 7/8 | 434 | 10 (3 relocation, 4 refresh, 3 unarmed) |
| VA2, 40 MB | Plain D4, already aligned | 426 | 6 (4 refresh, 2 unarmed) |

The two fix-2 disks kept their saved IPL, menu state and parked files;
SYS moved the old entry first, then installed the rebuilt DOS binaries.
[VA CHKDSK after refresh write 432](D5/fix3-replay-chkdsk-va.png).
Booting the floppy on that same cut and retrying SYS also recovered it
and passed CHKDSK.

The M4 rerun used the rebuilt floppy for both captures (including
prepare/cancel), the three-way menu, startup ownership, keyless restart
with the last default, and `/D` with CHKDSK. The VA2/5 MB/256 KiB run
started from an HDFORM/1.05 fixture and resumed from its DOS selection
checkpoint with more frames for `TYPE CONFIG.SYS`; it showed `FILES=27`.
On VA, HDFORM and 1.05 SYS were rerun before both captures. A separate
VA2 refresh at 256 KiB passed CHKDSK and kept all files other than the
three replaced system files unchanged.

The regression cases covered corrupt stage and truncated state fallback,
occupied menu IDs, three cut points in a VA menu switch, and floppy
`SYS B:` and `FORMAT B: /S` with independent boots on VA. The corrupt
fixtures reached DOS without changing the HDD; the transient warning
was not asserted by the final-screen check.

**NOT RUN:** torn writes, physical hardware, 10/20 MB, or an exhaustive
new capture/prepare interruption matrix.

## Fix 4 verification

The D1 → D4 → D5 builder rebuilt `2cf8894` into a 1,331,888-byte
`msdos4-pc88va-2hd.d88`, SHA-256
`8084e4541f283b1282fb0bbba79757a8613e09aa192740d76f2e5ca5378448cb`.
The Japanese catalog applied in a disposable export; the translated SYS
assembled and linked with MASM 5.10 and LINK 3.65.

On vaeg m153, the damaged-table test replaced the table immediately
following the write that arms replay, separately for reservation and
publication. HDD boot displayed the [recovery instruction](D5/fix4-redo-failed-va2.png).
Floppy SYS restored the IPL, finished the transfer and passed CHKDSK;
the HDD booted afterward. A separate cut followed by
`ECHO RETAINED>C:\EARLY.TXT` from the floppy left both the redo log and
staged clusters unchanged. SYS retained that file and CHKDSK passed.
On VA, the final SYS also handled a legacy fix-3 armed disk both with an
intact log (`/L` replayed it) and with a damaged log (`/L` restored the
IPL), and refused without writing when the FAT copies disagreed.

For each missing-file case, a host check reconstructed every durable
prefix of the actual 256-byte SASI write trace and applied its redo
images when armed. It checked the pre/post guards, FAT equality, unique
root names, chain ownership, matching old or replacement DOS file bytes,
and unchanged non-DOS files. For each case a guest booted a cut with the
reservation in place and retried SYS, and booted an armed publication
cut directly. Both paths reached DOS and passed CHKDSK.

| vaeg, 5 MB / 640 KiB | Missing file (each tested separately) | Host snapshots per file | Guest checks per file |
|---|---|---:|---:|
| VA and VA2, D4 | `IO.SYS`, `MSDOS.SYS`, `COMMAND.COM` | 443 | 2 |
| VA and VA2, D5 | `IO.SYS`, `MSDOS.SYS`, `COMMAND.COM` | 441 | 2 |

The fix-3 straddling layouts (VA and VA2, actual fix-2 captures), an
aligned VA2 D5 disk and a plain VA2 40 MB disk each passed host checks
at all 441 writes. Each distinct metadata/boot state (13 per layout)
booted with CHKDSK; redundant cuts in staging data were checked on the
host, not booted independently. Fresh captures with and without an
existing `CONFIG.SYS` on both 5 MB models also refreshed, passed CHKDSK
and booted DOS from HDD.

The final distribution on VA2 (5 MB) reported capture success plus a
layout warning with both kernel blocks full. On VA it replaced a kernel
with a cyclic chain, retained the old allocation for CHKDSK, and booted.
VA2 also refreshed a 5 MB menu volume and passed CHKDSK at 256 KiB.
On VA, an incomplete source floppy and an occupied, unmarked tail were
both refused with the target image unchanged.

The M4 sequence on VA (5 MB, 640 KiB) used the rebuilt floppy after
HDFORM and both PC-Engine SYS runs. Both captures, preparation/cancel,
all three menu choices, startup-file switching, the default after a
restart, and unregister + CHKDSK passed. Saved IPLs and parked file
contents matched at the checkpoints. Corrupt-stage and truncated-state
fallback, occupied menu slots, and three sampled menu-switch cuts also
passed.

**NOT RUN:** torn writes, physical hardware, 10/20 MB, target-1
interruption, and new exhaustive capture/prepare interruption tests.

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

### Shared startup files and countdown

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
(2229 bytes in the fix-1 direct assembly). A missing, truncated or bad file falls
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
| 4 | 4 | Owner ID, last choice, phase, pending target ID |
| 8 | 8 | Four root slot numbers reserved by `/P`, when prepared |
| 16 | 102 | Three 34-byte entry records (IDs 1–3); DOS is ID 0 |
| 118 | 1 | State version: 0 = original D5; 1 = replayable switch |
| 119 | 1 | Switch flags: bit 0 preserves the previous default during SYS |
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
parks the owner, activates the target (nothing for DOS), then commits
owner and last choice while clearing the marker. Renames are in-place
updates of the name and attributes; no FAT or file-data sectors are
written. A repeat of the active and last choice writes nothing.
Refreshing DOS with `SYS` may park the active version, but preserves
its last menu choice. On the next HDD-only boot the stage checks for a
valid prefix of the ordered renames (all owner files park before any
target file activates), skips completed steps, and rolls forward before
showing the menu. Plain `SYS C:` and `/L` can also replay the marker.
An unexplained name, slot, attribute, record CRC, or FAT chain is a
read-only failure: the stage prints a warning and boots DOS. The chain
walk requires exactly the number of clusters implied by the file size
and an end marker; it is bounded even on a cycle. Capture also checks
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
before setting phase 3, then parks the four files. It commits the
new default before publishing our IPL. Publication writes blocks 2–3
first, then block 0 alone; block 1 is left untouched and our loader
ignores it. Until block 0 changes, the ROM still enters PC-Engine's
IPL; some of the files it expects may already be parked. Boot the
MS-DOS floppy and rerun `SYS C:` to resume the allocation, a committed
phase-3 capture, or a capture parked before publication. Recover
before using the HDD from other software. With a foreign or blank IPL,
the preceding transfer of `IO.SYS`, `MSDOS.SYS` and `COMMAND.COM` is
ordinary DOS file I/O. Back up the disk first.

### Refresh and upgrade

When the IPL is already recognized as D4 or D5, SYS stages the new DOS
file contents in clusters free in both FAT copies. It records the staged
file entries and the exact new and retired chain lists in a CRC-checked
plan, then publishes a zero-length `VASYS.JRN` root entry pointing to
that plan. The staged files are not separately named in the directory.
SYS claims the new chains in both FATs, replaces the two live kernel
entries together in one 256-byte write, replaces `COMMAND.COM`, frees
the old chains in both FATs, then deletes the journal. If the kernel
entries span physical blocks, SYS refuses rather than exposing a mixed
pair. This does not yet support refresh on every valid root layout.
A cut can leave unreferenced chains or unequal FAT copies. Boot the
floppy and retry `SYS C:` **before** running CHKDSK repair or writing
anything else to the HDD: the journal cluster itself is not allocated.

New SYS must recognize the old IPL, validate and retain the old state
entries, and install a matching IPL and stage as a pair. The original
D5 release and this one share the same DOS loader and differ only in
IPL block 0. SYS writes the new stage, updates its length in the root,
then commits block 0 and the state version. Until publication a stage
length or CRC mismatch falls back to DOS; retry with new SYS. A future
format change must migrate the state explicitly and must not assume a
new IPL layout can be published in the same order. The old format did
not distinguish a SYS-initiated pending switch from a menu selection.

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
   the floppy. Install compatible shared `CONFIG.SYS`/`AUTOEXEC.BAT` if
   desired. Only the examples described in M2 were tested; arbitrary
   DOS startup commands and drivers may not be accepted by PC-Engine.
3. Boot **MS-DOS** from the HDD menu to free the real file names. Run
   `SYS C: /P`. Then boot the PC-Engine 1.1 floppy and run its `SYS C:`.
   Boot the project DOS floppy and run `SYS C:` again; label the new
   entry `PC-Engine 1.1`. The new entry is the first default.
4. A digit boots immediately; Enter or the 10–11 second timeout boots
   the default. `SYS C: /L` lists persistent IDs (menu digits may differ
   after removal). Use `SYS C: /C` before installing to cancel preparation,
   or `SYS C: /D n` to unregister ID `n`, even if its files are missing.
   `/D` only changes state; it does not rename, delete or restore files.
   Select MS-DOS before unregistering a healthy active set. If the
   unregistered set was active and left real names behind, back up and
   move those files before using the menu again.

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
   共用です。M2 の例以外の設定やデバイスドライバーは動作未確認です。
3. HDD メニューで **MS-DOS** を選び、PC-Engine のファイルを退避します。
   `SYS C: /P` を実行してから、PC-Engine 1.1 のフロッピーで起動し、
   その `SYS C:` を実行します。MS-DOS フロッピーで起動し直し、`SYS C:`
   で `PC-Engine 1.1` などの名前を登録します。登録直後は新しい項目が
   既定値です。
4. 数字キーで直ちに起動します。Enter または 10 秒経過で前回の選択が
   起動します。`SYS C: /L` は登録 ID を表示します (メニューの番号とは
   異なる場合があります)。準備の取り消しは `SYS C: /C`、登録解除は
   `SYS C: /D n` です。登録解除では退避ファイルを残し、復元はしません。
   登録処理が中断した場合は MS-DOS フロッピーから再起動し、他の書き込みや
   ディスク修復をする前に `SYS C:` を再実行します。

1.05 は VA 用、1.1 は VA2 用です。別の機種で起動すると、ディスク版と
異なる本体内蔵のバージョンが表示されることがあります。

## M4 — Gate results

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

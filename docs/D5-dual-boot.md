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

Use the *PC-88VA Technical Manual* §6.13, calendar-clock BIOS
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

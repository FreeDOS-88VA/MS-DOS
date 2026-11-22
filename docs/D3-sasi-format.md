# D3 — SASI FORMAT for the PC-88VA

## Use

Boot MS-DOS 4.0 VA from A: and leave A: current. Make a backup before formatting.

- `FORMAT C:` (or the mounted SASI drive's actual DOS letter) recreates the NEC VA FAT12 filesystem. Append `/V:label` to create a DOS root-directory volume label (up to 11 characters, same parsing as floppy FORMAT).
- `FORMAT /H0` or `FORMAT /H1` selects a **physical** SASI target that DOS did not mount at boot. The numbers are zero-based, not DOS letters or the emulator's `--sasi1`/`--sasi2` numbers. If the target is already mounted, use its DOS letter. A blank target has no DOS letter until reboot.
- The prompt names the letter (if any) and target number. Type `Y` and press Enter; any other line cancels. A redirected input file is not accepted. FORMAT refuses the current and boot disks, unsupported targets, and `/S` on SASI.
- **Reboot after formatting**, including after a failed or interrupted write to a mounted disk. A mounted unit is taken offline at confirmation and stays offline until reboot, even if FORMAT fails. Trying to read it before reboot can produce DOS's `Not ready` critical-error prompt.
- There is no SASI IPL installation, physical format (`/P`), surface scan, or secure erase. A non-NEC mounted volume (including the FreeDOS native layout) is replaced, not converted. A: and B: still use the 2HD floppy path, including its existing `/S` support.

## Design

The SASI path lives in `pc88va/VAFORMAT.ASM`: one command, the same option parser and root label writer, separate floppy and SASI selection and I/O. The existing builder still assembles and installs `FORMAT.COM`; no builder changes are needed.

The ROM interface follows 602HDD §6.2.2 (status) and §6.2.3 (09 SENSE, 02 WRITE DATA, 04 FORMAT DRIVE). SENSE must return type 0–3; FORMAT repeats it after confirmation. The writer uses relative block addresses with four 256-byte blocks per write and a physically 1024-byte-aligned buffer checked against the DOS allocation. The buffer cannot cross a DMA 64 KiB boundary. On the first BIOS error, FORMAT stops. It writes the first sector of FAT 1 last, so D2's detection signature on a blank disk is not published before the other metadata writes succeed. This is not transactional on a previously formatted disk.

| SENSE type | Nominal size | Media | Sectors/FAT | Root entries | First data block |
|---:|---:|---:|---:|---:|---:|
| 0 | 5 MB | D0h | 1 | 608 | 88 |
| 1 | 10 MB | D1h | 2 | 992 | 144 |
| 2 | 20 MB | D2h | 4 | 1504 | 224 |
| 3 | 40 MB | D3h | 4 | 3072 | 420 |

Two FATs start at block 4. Each starts with `Dx FF FF`, followed by zero bytes. The empty root matches HDFORM: every 32-byte slot starts with `00` followed by 31 `E5` bytes. `/V` replaces the first slot with an attribute-08h, DOS-date/time-stamped label entry; the next slot is still an end-of-directory marker. Blocks 0–3 (D4's IPL area) and all data and tail blocks remain untouched.

### DOS integration

Private generic IOCTL category 08h, function F0h, takes a two-byte packet. On the VA floppy driver it returns the boot-time SASI mount bitmap and tag D3h; on the SASI driver it returns the physical target and tag D4h. This avoids inferring the target from the DOS letter (e.g. when target 1 alone is mounted as C:). Raw `/Hn` refuses a target in the bitmap. DOS's current and boot letters are checked against the selected mounted drive, including by physical target where the IOCTL resolves the letter. VA IO.SYS now reports A: to SYSINIT as the boot drive, matching VABOOT.

On mounted FORMAT, DOS disk reset flushes buffers before IOCTL 08/F1, which validates the tagged physical target and takes its unit offline. Media check reports changed; build-BPB and block I/O refuse access until reboot. This avoids stale DOS buffers and differs deliberately from a media-change-only scheme: the old DPB can describe a different sector size or FAT type. Boot discovery rebuilds the correct DPB. The no-SASI resident end grew by 16 bytes after paragraph rounding; the mounted BPB table starts at the same offset as D2.

### HDFORM comparison

References: PC-Engine 1.1 boot disk (banner 1.0 on VA, 1.1 on VA2), vaeg m153. Used matched scratch HDIs with an IPL marker and a tail-data marker (also a marker in the first data block on the 40 MB runs). [`compare-format.py`](D3/compare-format.py) compared all physical blocks and the HDI header. Every default run matched HDFORM exactly, including the IPL, FATs, unused root entries, and data/tail. No differences to explain. For the 10 MB labeled reformat, the metadata differs from the unlabeled HDFORM reference only in physical block 20 (the label and its DOS timestamp).

Instrumented a scratch m153 build (6367e5d3): in `cbus/sasiio.c`, log the six CDB bytes and target at `checkcmd` before the opcode switch. Captured from boot through completed 5 MB `HDFORM C:` runs on VA and VA2: [21 four-block writes and no FORMAT DRIVE or FORMAT TRACK CDBs](D3/hdform-trace.tsv). The 600 reads of 33 blocks cover the 5 MB logical extent. D3 matches HDFORM's on-disk result on healthy media, but does not repeat the read test or mark bad clusters. The trace and byte comparison are separate: matching HDIs alone would not detect a physical-format command that the emulator treats as a no-op.

## Emulator gate

Build: MASM 5.10 assembled VAIO and VAFORMAT, zero warnings and errors. LINK 3.65 linked both (`L4021`, no stack segment, as these images supply their own stack). Tested with vaeg m153 on VA and VA2 at 640 KiB, using MS-DOS 4.0 VA, the D2 PC88VA CHKDSK build, and the D1 DISKCOPY. Repeated all eight blank formats after adding the DMA allocation check; the final binary produced the same HDIs.

For each [model/size pair](D3/gate.tsv):

1. Generate two identical blank HDIs with `docs/D2/mkhdi.py --layout blank`, outside the repository. Add the same markers to both. Format one with `HDFORM C:` and the other with `FORMAT /H0`. Answer `Y` in both sessions. Compare before either OS writes any files.
2. Reboot DOS on the new disk. `DIR C:` shows an empty root. Copy a floppy fixture to `C:\MARK.TXT`, `MD C:\D3DIR`, then copy the fixture to `C:\D3DIR\SUB.TXT`. Check `DIR`, compare the exact host manifest and contents using `docs/D2/check-nec-fat12.py`, and compare CHKDSK's free cluster count with the host check.
3. Boot PC-Engine on that disk. Copy the DOS marker back to a transfer floppy; copy a second test file from floppy to `C:\ENG.TXT` and read it back to the floppy. Compare both readbacks and check the final HDD manifest and both FATs. Boot NEC MS-DOS 2.11 VA on the same disk, accept the date and time prompts, run `DIR C:` and `TYPE C:ENG.TXT`.

| Extra gate | Models and observed result |
|---|---|
| Mounted reformat with files | VA2, 10 MB: `FORMAT C: /V:D3TEST`; attempted DIR gets `Not ready`; after reboot DIR shows the label and no files, CHKDSK reports all 1233 clusters free. IPL and data bytes unchanged. |
| Mounted FreeDOS native conversion | VA2, 40 MB FAT16: copied a marker to C:, confirmed `FORMAT C:`, then rebooted. DIR showed no files and the NEC FAT12 host check and CHKDSK both reported 2468 free clusters. |
| Refusals | VA2, mounted 10 MB at target 0: `/S`, `/H0` (mounted), `/H1` (absent), `D:` (invalid drive), `C:` while current, `N` at the confirmation prompt, and redirected `Y` from a file. HDIs byte-identical to input. With no SASI images attached, `/H0` also refused before prompting. |
| Two targets | VA2, 10 MB target 0 with files + blank 40 MB target 1: `FORMAT /H1` changed only target 1. Target 0 byte-identical; after reboot DIR on C: shows the original files and D: is empty. Host FAT check on target 1 clean. |
| Floppy FORMAT | VA and VA2: `FORMAT B: /V:D3FLOPPY`, 2HD; 1,299,456 bytes free, DIR sees the label. |
| Floppy DISKCOPY | VA and VA2: `DISKCOPY A: B: /V`; all 1280 × 1024-byte sector payloads match and the copy boots. |

Screenshots: [raw FORMAT](D3/raw-va2-40.png), [mounted offline](D3/mounted-offline.png) and [after reboot](D3/mounted-reboot.png), [refusals](D3/refusals.png), [target 1 format](D3/target-1-format.png) and [after reboot](D3/target-1-reboot.png), [HDFORM](D3/hdform-va2-5.png), [PC-Engine](D3/pc-engine-va-40.png), [NEC 2.11](D3/nec211-va-40.png), [floppy FORMAT](D3/floppy-va.png) and [DISKCOPY](D3/diskcopy-va2.png).

**NOT RUN:** real hardware, physical-format effects, defective media, write protection, hot removal, refusal while actually HDD-booted (D4), low-memory refusal, and floppy `/S`. No guest/media binaries are included here.

# F1 — Small follow-ups

## 1. System-file dates

`FORMAT /Hn /S` populated the root entries directly with midnight on
1980-01-01 (date word `0021h`, time word zero). Floppy `FORMAT /S` and
`SYS` used DOS file creation and close, so their timestamps were those
of the copy, not of the source. All three now get each source file's
last-write date and time via INT 21h AX=5700h while staging. Raw SASI
FORMAT writes both words at FAT offsets 22 and 24. The DOS-write paths
set them with AX=5701h after writing and before closing. A timestamp
error follows the existing read or write error path.

Built the Japanese and English distributions with the D4 and J4 builder
patches, in that order. The media tests use the Japanese distribution
and vaeg m153, VA2, 640 KiB. Synthetic source entries carried different
nonzero dates and times. After raw `FORMAT /H0 /S` on a blank 40 MB
HDI, host inspection matched all six FAT timestamp words. On a clone,
only the IO.SYS and MSDOS.SYS attributes were cleared for `DIR` (this
COMMAND does not accept `/A`). The clone cold-booted without floppies;
`DIR` at `C>` showed IO.SYS `20-06-17 10:20`, MSDOS.SYS
`21-06-18 11:20`, and COMMAND.COM `22-06-19 12:20`. Reinstalling on C:
with `SYS C:` from a floppy with revised dates and times reported
`System transferred`; all six destination words matched the revised
source. `FORMAT B: /S` onto a blank 2HD floppy also reported `System
transferred`; all six words and all three payloads matched that source.

**NOT RUN:** real hardware, timestamp API failure injection.

## 2. A 40 MB secondary SASI disk on VA

The documented VA drive list (602HDD §6.2.1) includes the 40 MB
PC-98H53 but not its secondary/expansion PC-98H54. It lists both
members of the 5, 10 and 20 MB pairs explicitly. §6.2.3 defines a
common SENSE result type 3 for 40 MB, not support for every capacity
on both targets. The 1993 *PC-9800 Technical Data Book, Hardware*,
p. 234, documents switch code `110b` for 40 MB in **both** fields;
this is the PC-9800 controller convention, not a promise of VA BIOS
support for the H54. The VA Technical Manual §5.7.5 describes the
shared interface, not the supported secondary drive list.

vaeg `fdd/sxsi.c` matches HDI block size, sectors/track, heads and
cylinders to its SASI type table. Both 40 MB files had header size 4096,
payload 41,564,160 bytes, and geometry 256 bytes/block, 33 sectors,
8 heads and 615 cylinders (switch code 6). The 10 MB files used 256,
33, 4 and 310 (code 1). `cbus/sasiio.c` returns the two switch codes
in bits 5:3 and 2:0 of the type read from port 82h.

Fresh NEC-layout images, Japanese distribution, 640 KiB, tracing-only
m153 build. A standalone DOS COM issued INT 81h with AX=0900h,
BH=0 and 1; both calls returned CF=0 in every row:

| Model | Target 0 + 1 | Port 82h | AX0 | AX1 | Target 1 command trace |
|---|---|---|---|---|---|
| VA | 40 + 40 | 36h | 0003h | 00FFh | C2 once, 00 twice; no seek or read |
| VA | 10 + 40 | 0Eh | 0001h | 00FFh | C2 once, 00 twice; no seek or read |
| VA | 40 + 10 | 31h | 0003h | 0001h | C2, 00, 01, 0B, 08; D: listed |
| VA | 40 + absent | 37h | 0003h | 00FFh | C2 once, 00 twice; no seek or read |
| VA2 | 40 + 40 | 36h | 0003h | 0003h | C2, 00, 01, 0B, 08; D: listed |

For example, VA and VA2 both sent target 1 CDB `C2 20 00 00 00 00`;
only VA2 proceeded to `0B 20 05 28 00 00` (seek) and
`08 20 00 04 02 80` (read). The controller reported no errors on those
commands, and TEST DRIVE READY (`00`) was not discriminating: the
emulator checks for a slot pointer, which exists even for an empty
slot. For a separate diagnostic, overriding just the low three type
bits on VA with both 40 MB files attached yielded SENSE AL=0, 1, 2 for
codes 0, 1, 4 respectively; codes 2, 3, 5, 6, 7 all gave FFh. No switch
code made the VA BIOS recognize target 1 as type 3.

This is a VA BIOS/support limit in the tested configuration, not a DOS
probe ordering or HDI geometry problem. The two images do mount on
VA2 with the same emulated controller. No DOS or vaeg code change;
no geometry is guessed for target 1. **NOT RUN:** physical drives,
real hardware, other firmware revisions.

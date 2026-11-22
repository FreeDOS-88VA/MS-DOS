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

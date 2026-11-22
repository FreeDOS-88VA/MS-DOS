# J2d — direct text BIOS output and CON row modes

Baseline: `release/msdos-va` at `0e4738d`. VA emulation: vaeg m153, VA and VA2.

## 1. Direct INT 83h writers

Restore `VSCL` on the main split. CON still defers its right-edge wrap:
away from the bottom row it can undo the BIOS cursor advance with `Locate`;
at the bottom it temporarily installs the same split with `VSCL` clear. The
write, including a split kanji or the `FEh` pre-wrap filler, still goes through
the text BIOS with word wrap enabled. Both split changes restore the current
attribute and cursor. The system-row geometry and backing storage do not change.
See `604TEXT.TXT` §6.4.3 functions 1–3, 7, 27, 36 and 37.

In the baseline, `ROMWRITE` on VA and VA2 left lines 01–23 intact and only
replaced the last row with line 32, for both `Putstr` and `Chuput`. The probe
uses DOS only to wait and exit. Source audit: `VAJFP`, `VAKEY`, `VAFORMAT` and
`VADCOPY` do not issue INT 83h directly; the resident FEP uses it on the
system split, and COMMAND's `CLS` and the boot error paths also use it.
This is not an audit of third-party DOS binaries.

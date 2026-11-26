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

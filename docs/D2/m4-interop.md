# D2 M4 — PC-Engine disk interchange

Gate: on VA2 and, if it boots PC-Engine, VA, hand one 40 MB and one
smaller HDFORM-made HDI back and forth without converting the volume.
Check guest reads against known bytes, run MS-DOS 4.0 CHKDSK before and
after its writes, and validate the final FAT12 directly on the host.

## Setup and procedure

Used vaeg m153, the M3 `d2boot.d88` (the D2 VAIO and PC88VA CHKDSK
build), the PC-Engine 1.1 floppy, and the NEC MS-DOS 2.11 VA floppy.
All guest media and recovered files stayed under the external D2
scratch directory. Each model/size pair had its own initially blank
HDI from `mkhdi.py`. HDFORM selected the type from the attached drive:
40 MB reported 40,435,712 usable bytes, and 10 MB reported 10,100,736.
The same HDI was attached as C: at every main stage for that pair; B:
was a 2HD FAT12 floppy carrying original test data and readbacks.

1. Boot PC-Engine and format C:. In a fresh boot, PC-Engine copies
   `ENG.TXT`, `ENG.BIN` (131,328 bytes) and a deletion sentinel
   `ENGDEL.TXT` to C:, creates `ENGDIR`, copies `SUB.TXT` into it,
   and lists both directories.
2. On MS-DOS 4.0 VA, `DIR` lists the root and `ENGDIR`. `TYPE` of
   `ENG.TXT` and `COPY /B` of the binary and subdirectory file to the
   floppy match the input bytes on the host. `CHKDSK` reports clean.
   DOS writes `DOS.TXT`, `DOS.BIN` (the 131,328-byte fixture reversed),
   `DOSDIR/SUB.TXT`, and its own deletion sentinel `DOSDEL.TXT`, then
   deletes `ENGDEL.TXT`.
3. Back on PC-Engine, list C:, copy the DOS text, binary and subdirectory
   file back to B:, then write `ENGNEW.TXT`, delete `DOSDEL.TXT`, and list
   C: again. The host compares the three recovered files byte for byte.
4. On MS-DOS 4.0 VA, `DIR` sees `ENGNEW.TXT` and neither sentinel.
   `TYPE` of `ENGNEW.TXT` matches the input bytes; `CHKDSK` reports
   clean again. Both CHKDSK runs agree with the host's allocation counts.
5. On NEC MS-DOS 2.11 VA, `DIR C:` lists both systems' files and `TYPE`
   shows the expected text from `ENGNEW.TXT` and `DOS.TXT`.

On separate copies of the two pre-delete checkpoints, DOS also typed
`ENGDEL.TXT` and `ENGDIR/SUB.TXT` and compared `ENG.BIN` with `COMP`;
PC-Engine copied `DOSDEL.TXT` to B:. The text and floppy readbacks
matched the inputs and `COMP` reported `Files compare OK`. These extra
read checks did not modify the main interchange image.

PC-Engine command names and roles: **HDFORM** (initialize the HDD),
**COPY** (transfer data to or from the HDD), **MD** (make a subdirectory),
**DIR** (list files), and **DEL** (delete the DOS sentinel).

## Evidence and differences

- [Matrix](m4-gate.tsv): byte comparisons, CHKDSK and final FAT checks.
- PC-Engine screenshots: [VA2 / 40 MB HDFORM](m4-va2-40-format.png),
  [first write](m4-va2-40-first.png), [after the return leg](m4-va2-40-return.png),
  and [VA / 10 MB after the return leg](m4-va-10-return.png).
  [NEC MS-DOS 2.11 DIR and TYPE](m4-va2-40-nec211.png) on VA2 / 40 MB.
- The same PC-Engine 1.1 floppy boots to a banner showing **v1.1 on VA2**
  and **v1.0 on VA**. HDFORM and all interchange operations worked on
  both. The VA / 40 MB interchange began with the HDFORM-written volume,
  but the host timed out before taking the completion screenshot;
  [this VA / 40 MB HDFORM screenshot](m4-va-40-format.png) is from a
  separate format-only repeat on another blank HDI.
- DOS displayed `26-00-01` for copied test files because the reused M3
  floppy builder supplied FAT date `5C01h` (month zero). This date was
  already on the source disk. `COMP` printed `EOF mark not found` before
  its success line because the binary fixture does not end in Ctrl-Z;
  the independent binary readback also matched. No payload mismatches
  were observed. Real hardware was not tested.

[`check-nec-fat12.py`](check-nec-fat12.py) reads the HDI geometry and
FAT12 at physical block 4 (1024-byte logical sectors) without modifying
or repacking the image. It compares both FAT copies, walks allocation
chains through the root and subdirectories, checks file sizes and dot
entries, and rejects loops, cross-links and unreferenced allocations.
With `NAME=SOURCE` arguments it also requires the exact file manifest
and contents, including the absence of the deleted files. The checks
were run against the checkpoints after the first two writers and the
final image. The final manifest was `ENG.TXT`, `ENG.BIN`,
`ENGDIR/SUB.TXT`, `DOS.TXT`, `DOS.BIN`, `DOSDIR/SUB.TXT`, and
`ENGNEW.TXT`. Negative checks rejected a mismatched FAT copy, a lost
cluster inserted in both copies, and a truncated HDI.

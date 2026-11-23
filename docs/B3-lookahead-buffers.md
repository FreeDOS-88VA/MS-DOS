# B3 — `BUFFERS=n,m` on PC-88VA

## Reproduction and diagnosis

On the Japanese B2 image (`a22890cd`, same source as the `a11b4cc`
merge), booted in vaeg m153 on VA and VA2, append
`ECHO BUFFERS=20,8>> CONFIG.SYS` and reboot the written disk.
Both models show the sign-on but no prompt or DIR output by guest frame
1600. The same happens with `20,1`; `20` reaches the prompt and lists
files. Each value was tested on a fresh copy of the image.

SYSINIT allocated only `512 * m` bytes for the secondary cache. DOS
`RW_SC` requests up to `m` sectors at that address, and `SC2BUF2` uses
`SC_SECTOR_SIZE` to index and copy them. VAIO reads full 1024-byte
sectors on the test floppy. The allocation ends before the transfer
ends, so read-ahead writes into the DOS current directory structures
(CDS), allocated immediately after the cache and its next allocation
marker.

On **both** models, a `wait-pc` register capture at the relocated
SYSINIT cache-size multiply (`9C11:11FA`) shows AX=`0200h` with CX=1
or 8. The capture at the call to `FOOSET` (`9C11:125D`) shows the CDS
at `2122:0000` or `2202:0000`, respectively. The captures at VAIO's
INT 80h read site (`1000:2454`) and return (`1000:2456`) gave the
following:

| Value | Read registers AX / BX / CX / DX | Target ES:BP | Return AX / CF |
|---|---|---|---|
| `20,1` | `8101 / 0700 / 000E / 0503` | `2101:0000` | `0001 / 0` |
| `20,8` | `8104 / 0701 / 000F / 0103` | `2201:0000` | `0004 / 0` |

With `20,8`, the FDC log records 4096 bytes transferred to physical
`21010h` (cylinder 7, head 0, sector 5), then another 4096 bytes
to `22010h` (head 1, sector 1). The second destination is past the
4096-byte allocation and is only 16 bytes before the CDS. With `20,1`,
the first 1024-byte transfer to `21010h` already overruns the 512-byte
allocation. Neither transfer needs to cross a 64 KiB DMA boundary.

At frames 700 and 1000, emulator state samples on both models showed
all 440 bytes of the five-entry CDS table matching the corresponding
floppy sector data: from offset `210h` in C7/H0/R5 for `20,1`, and
from offset `10h` in C7/H1/R1 for `20,8`. The PC samples varied; this
was not one stuck INT 80h call. In particular, the damaging read
returned success before the prompt failed.

## Fix

In `v4.0/src/BIOS/SYSINIT1.ASM`, the `PC88VA` allocation now uses
`SingleBufferSize - BUFINSIZ`. SYSINIT already derives that primary
buffer size from `SYSI_MAXSEC` plus the primary buffer header; the
secondary cache holds raw sectors and needs no per-sector header.
`BUFFERS` accepts 0 through 8 secondary buffers, so the largest
allocation on VA is 8192 bytes. No change to the DOS cache policy, VAIO
transfers, or non-VA allocation.

## Gate

Built `c3d071e3` with the D4+J4 builder (Japanese, 2HD distribution
floppy) and tested it with vaeg m153. Each floppy setting was appended
in DOS and checked with `TYPE CONFIG.SYS` after reboot.

| Check | VA | VA2 |
|---|---|---|
| `20,1`: boot and DIR | PASS | PASS |
| `20,8` (maximum secondary count): boot and DIR | PASS | PASS |
| `99,8` (maximum conventional primary and secondary counts): boot and TYPE CONFIG.SYS | PASS | PASS |
| `20`: boot and DIR | PASS | PASS |
| `20,8`: COPY COMMAND.COM, FC /B, MD, COPY into subdirectory, CHKDSK | PASS | PASS |
| Same `20,8` disk, second boot: FC /B of persisted copy, DEL, RD, DIR /W, CHKDSK | PASS | PASS |
| 40 MB SASI HDI, `20,8`: HDD-only boot, DIR, COPY, FC /B, CHKDSK | NOT RUN (not required) | PASS |
| Unmodified CONFIG.SYS: two-boot `docs/B2/run-smoke.py` regression | PASS | PASS |

The B2 smoke-screen comparisons against `a22890cd` matched on both
models after normalizing the build stamp and file timestamps. Both
binary comparisons matched, and CHKDSK reported no errors on either boot.

The look-ahead floppy comparisons matched on both boots. After cleanup the root
listing again had 37 files and CHKDSK reported 772,096 bytes free,
with no errors on either boot. For the HDD test, `FORMAT /H0 /S` installed
the system from the test floppy onto a blank HDI. After rebooting the
floppy to write `C:\CONFIG.SYS`, the HDI booted with both floppies absent.
`TYPE CONFIG.SYS` showed `BUFFERS=20,8`; the copy matched and CHKDSK
reported 40,173,568 bytes free with no errors.

**NOT RUN:** real hardware, 2D media, EMS `/X`, or a non-VA build.

# A1 — ROM-backed PRN and AUX

## M1: interfaces and policy

Sources: PC-88VA technical manual §§2 (interrupt/I/O maps), 5.8–5.9,
6.9 (`609PRN.TXT`) and 6.10 (`610COMU.TXT`); NEC MS-DOS 3.3D
Installation Guide §§4.1, 4.3 and appendix A, and User's Guide appendix
B.4 (`SPEED`, `SWITCH`). The PC-98 manuals were extracted and read in
scratch only. No NEC execution or byte capture was performed.

- **Printer:** INT 89h/00h returns ready (AL=0) or busy (AL=1).
  There is no independent paper-out/offline/disconnected indication in
  this interface. 03h sends DL unchanged and reports STOP or timeout via
  carry, without distinguishing them. 01h accepts a Shift-JIS word in DX,
  converts it to printer JIS as appropriate, and distinguishes invalid
  conversion (AL=1), STOP (2) and timeout (3). 08h sets the timeout in
  seconds, initially zero (unlimited). The PC-98 guide documents
  `COPY file PRN`, redirection, simultaneous console printing and
  STOP/Ctrl-C with BREAK ON. It shows a PRN not-ready diagnostic and
  PC-PR201 printer settings, but does not establish the wire-level kanji
  shift bytes or CR/LF transformations. Those and timed retries on NEC
  are **NOT RUN**.
- **PRN policy:** use documented VA printer conversion for Shift-JIS
  pairs, with printer type/framing owned by ROM SETUP, not hardcoded
  PC-PR201 codes. Follow J2a's split-request lead collection, but use the
  printer BIOS, not console glyph substitution. Send standalone bytes
  unchanged via 03h, including CR, LF and TAB. This is a VA policy, not
  proven NEC byte parity. Use a one-second firmware timeout; map an
  ambiguous busy/timeout to not ready where distinguishable, otherwise
  write fault; never fabricate a paper-out code from busy alone.
- **Serial:** INT 8Ah/00h initializes the 8251 (DH mode, DL command),
  interrupt-fed ROM RX queue and state. It takes baud from firmware
  backup, so apply 08h to select the baud. 09h can force raw single-byte
  receive; 0Ah controls XON/XOFF and SI/SO. 03h consumes a received byte
  (CF=1 empty, AL bit 7 on receive error); 04h peeks, 05h peeks native data,
  0Bh returns queue count, 0Ch clears it. 0Dh waits in 100-ms units and
  recognizes ROM abort keys. 01h transmits (DH=0 for a single byte), waits
  about 140 ms on UART busy, and may retain an unsent byte for 02h retry.
  06h gives TxRDY/TxEMPTY, DSR, CTS, DCD and flow status. The ROM RX IRQ
  drops new bytes when its queue is full.
- **AUX defaults:** 9600 baud, 8N1, no software flow or character
  conversion; assert RTS and DTR and respect CTS for transmission.
  These are project defaults, not NEC factory defaults. NEC 3.3D uses
  RSDRV.SYS and `SPEED` to activate/configure the selected port, taking
  initial settings from memory switches (`SWITCH` persists them).
- **Emulator:** vaeg m153 (SHA-256 `a3ab65a03eac9fd2abccca3d51b8e464266a4b6141b9d5132b5b667495655906`),
  inspected supplied source: `io/sysportva.c` does not latch printer data
  or model strobe and hardwires printer not-busy. The SDL2 JAST printer
  branch in `sdl2/commng.c` is not wired to this interface. `io/serial.c`
  models UART data/status and its IRQ path through a `COMMNG` endpoint,
  but `COMCREATE_SERIAL` in SDL2 falls through to the disconnected stub
  (no reads, writes discarded, inactive modem inputs). No capture or
  injection config found. Minimal emulator changes: latch printer data
  and append it on the active strobe edge, with injectable busy; add an
  opt-in serial `COMMNG` PTY or paired input/output files, with asserted
  CTS/DSR and RX paced by the existing timer/IRQ path. No vaeg changes.

M2 gate: build and test the assembled DOS driver with synthetic BIOS
replies if no printer backend exists. M3 gate: build and test similarly;
mark actual serial capture/injection and terminal use NOT RUN without a
backend. In both cases boot VA and VA2 where possible; real peripherals
are NOT RUN.

## M2: PRN and LPT1

The built-in headers share a pair parser. Command 16 checks readiness
before each byte and reports the accepted prefix on busy. An already
started ROM character may still wait up to the BIOS timeout, and the
BIOS does not report partial physical output inside a JIS character.
Command 11 drops an unmatched lead. A DOS Retry after partial physical
output can repeat bytes. No independent paper-out mapping is possible.

| Gate | VA | VA2 |
|---|---|---|
| Boot from 2HD | Prompt reached | Prompt reached |
| Initial synthetic BIOS fixture | FAIL: invalid fixture opcode | FAIL: invalid fixture opcode |
| Initial CHKDSK | FAIL: no completion | FAIL: no completion |
| Physical printer / byte capture | NOT RUN | NOT RUN |

See [M2 evidence](A1/m2.txt). `PRINT` source inspection found that its
resident code recognizes PRN/LPT1 as IBM INT 17h devices and uses IBM
interrupt hooks; command 16 alone does not establish compatibility.
`PRINT.COM` was not executed or added to the builder.

## M3: AUX, COM1 and SPEED

- Boot initializes the communication BIOS to the M1 defaults. AUX and
  COM1 share the interrupt-fed BIOS queue. A device read waits for the
  requested byte count, with IRQs enabled; no data is not EOF. An errored
  receive byte returns read fault. DOS cooked mode can still interpret
  Ctrl-Z; the driver itself does not. Peek and input status do not
  consume a byte. Input flush clears the BIOS queue; output flush has no
  DOS-side queue to clear.
- Writes submit one byte at a time, return not ready without CTS, and
  return write fault on BIOS send failure. They do not call BIOS retry:
  DOS owns retry and the returned count describes only accepted bytes.
  Output status checks Tx ready, CTS and XOFF; DOS single-character calls
  can poll that status while the device is busy.
- `SPEED baud` selects `75`, `150`, `300`, `600`, `1200`, `2400`, `4800`,
  `9600` or `19200` for AUX/COM1 (e.g. `SPEED 4800`). It changes baud only,
  without flushing RX, and does not persist a setting. It is not the
  multi-port NEC command. The [builder patch](A1/build-speed.patch)
  packages the project implementation as `SPEED.COM`.
- The initial printer fixture contained unsupported 386 near branches.
  Both fixtures now target 186-compatible instructions. The printer
  status reply also now zeroes the low byte when reporting Busy.
- M3 used a 256-byte alignment workaround for the floppy-only CHKDSK
  hang. Fix 1 removed it; see [CHKDSK hang root cause](#chkdsk-hang-root-cause).

## Gate procedure

Use the scratch MASM/LINK toolchain and existing 2HD builder fixture, as
in [J2d](J2d-console.md#reproduce). Relink `VAIO` with the same SYSINIT
objects, link `VASPEED` and convert it at COM origin 100h. Keep all
output outside the checkout. Assemble `PRNMCK.NAS` and `AUXMCK.NAS` in
`tests/pc88va/` with NASM `-f bin`, then add the two COMs and `SPEED.COM`
to the test image. The runner accepts the same arguments as the J0.4
runner: vaeg executable, ROM directory, baseline disk, new disk, test
disk, scratch output directory, then optional scenario names. Set
`PYTHONPATH` to vaeg's `tools/qa` and `BASE_CISTAT`/`AFTER_CISTAT` to the
DOS `CISTAT` entry points in the MASM listings. The cases `prn-mock` and
`aux-mock` hook the BIOS vectors in a cold-booted DOS guest. `-DSTARTDEV=3`
with the rebuilt IO.SYS in the NASM working directory instead builds
isolated fixtures runnable in emu2, omitting DOS standard-handle tests.

Actual captures/injection, real devices, NEC execution, PRINT, physical
2HD/2D, and drive/terminal scenarios requiring a live serial peer
(`COPY` both ways, `CTTY AUX` prompt and command): **NOT RUN**. The UART
mock checks the DOS interface, not the actual UART, IRQ handler or baud.
See [M3 evidence](A1/m3.txt).

## CHKDSK hang root cause

`CALLFL` (the flags word loaded with `POPF` before ROM disk calls) was
in the optional SASI tail, **past `RESEND`**, but both the floppy and
SASI drivers used it. With no SASI volume, SYSINIT relocated DOS over
that tail. The floppy driver was then loading flags from DOS memory,
not from the assembled `0245h`. Even builds that appeared to work had
the dangling reference. Aligning the DOS destination to 256 bytes only
changed which DOS word the floppy driver read.

**Reproduction and controls.** On vaeg m153, cold boot a single 2HD
floppy with no SASI units and run `CHKDSK A:`. Assemble and link VAIO
with `DB n DUP (0)` immediately before `RESEND`; use the same SYSINIT
objects, kernel, CHKDSK, disk files and boot sector for all variants.
The debug script enters the command at frame 260; score a pass only if
CHKDSK prints its memory summary and returns to `A:\>` (screen dumped
at frame 950 for the baseline sweep and 680 for the fixed/fine sweeps).
The requested 0–1024 sweep in steps of 16 did not hang on `9c071a6`:
those steps preserve the byte offset of the overwritten flags word
relative to the relocated DOS. In a finer sweep, `n=234` hung on both
models, while `n=235..240` passed at the **same** DOS destination
(`1254h`, physical `12540h`). At `n=234`, the assembled flags word is
at `1000:256Bh` (physical `1256Bh`, DOS offset `002Bh`). At `n=235`,
it is one byte later.

| Build / padding (decimal) | DOS segment | Last DOS root-buffer read (physical) | CHKDSK FAT read (physical) | VA / VA2 |
|---|---|---|---|---|
| Baseline `n=234` | `1254` | `1E288` | Not issued | Hang / Hang |
| Baseline `n=235..239` | `1254` | `1E288` | `30170` | Pass / Pass |
| Baseline `n=234`, same-layout flags control | `1254` | `1E288` | `30170` | Pass / Pass |
| Fixed A1 `n=234,235` | `126D` | `1E418` | `30300` | Pass / Pass |

The stock emulator's `wait-pc` capture at `GET_BPB`'s `REP MOVSB`
(`1000:2189h` in the failing image) showed `CX=0017h`, `SI=003Bh`,
`ES:DI=1000:241Bh`, and **DF=1** on both models. The preceding INT 80h
read succeeded, but the scratch INT 80h trace showed FLAGS `F402h` on
entry and return: DF set and IF clear. The copy therefore walked
backwards from `MIDCACHE+1` and overwrote `1000:2405h`, the jump out of
the floppy get-media-ID handler. Frame samples showed that word change
from `B0EBh` to `00C0h` and the cache's valid byte from `00h` to the
boot sector's `29h` signature, exactly as the backward copy predicts.
CHKDSK printed the volume label, entered IOCTL `440Dh` / `0866h` for
the serial number, then ran through the corrupted handler and never
issued the FAT read (`INT 25h`).

For the same-layout control, put `0245h` into two unused bytes of the
resident padding and retarget only the three floppy `PUSH CS:[CALLFL]`
operands. With all load and buffer addresses unchanged, both models
returned from INT 80h with FLAGS `F246h`, copied forward (DF=0 at the
breakpoint), left `B0EBh` intact, issued the FAT read and returned to
`A:\>`. FDC/DMA tracing also showed successful 1024-byte transfers
straddling physical `20000h` (for example `1FD70h..2016Fh` in the
failing image). The last root read completed at `1E288h`, well below
1 MiB. Neither a DMA page crossing nor a change in DOS relocation
address was needed to explain or fix this hang. No vaeg fix was made.

**Fix and gate.** Keep the shared `CALLFL` below `RESEND` and restore
ordinary paragraph rounding for floppy-only boots. The SASI path
still rounds the end of the mounted BPB records. MASM reported zero
warnings and errors for the tested builds. See the
[65-row sweep](A1/chkdsk-sweep.tsv): all 65 images per model on the
fixed branch completed CHKDSK and returned to the prompt. Physical
addresses in the fixed columns were checked against FDC/DMA traces on
both models. The baseline address columns are derived from the DOS
load segment and checked against both models' traces at `n=0,16,240,
512,768,1024` and at the fine-sweep points where the reads occurred.

- **VA and VA2:** `DISKCOPY A: B: /V` completed; all 1,280 sectors
  matched and the copy booted. `FORMAT B: /S` reported system transfer;
  the target's IO.SYS matched byte for byte and the target booted to the
  prompt. `COPY /B` of a 131,328-byte file to that disk matched byte
  for byte on the host.
- **D2 SASI, VA2 / 640 KiB:** a mixed NEC 40 MB and FreeDOS 40 MB pair
  mounted as C: and D:. Both CHKDSK runs were clean, host and guest
  readbacks matched, the two FATs agreed on each disk, and the temporary
  directory was absent. `HDRANGE` on D: passed cross-page and range
  checks; host comparison confirmed the last logical sector was restored.
  Other SASI models, RAM sizes and HDD boot were not rerun for Fix 1.

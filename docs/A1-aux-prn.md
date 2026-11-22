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
- The final boot path aligns the floppy-only DOS destination to 256
  bytes as a workaround for the layout-sensitive CHKDSK hang. Scratch
  controls reproduced it by growing the baseline resident BIOS without
  changing the driver code. Growing only the IO.SYS file did not
  reproduce it. The alignment restores the CHKDSK gate on both models;
  it does **not** establish the root cause. SASI keeps the original DOS
  destination calculation; HDD boot and other memory sizes were NOT RUN.

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

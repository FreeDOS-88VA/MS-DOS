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

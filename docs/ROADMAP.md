# MS-DOS 4.0 for PC-88VA — roadmap

Milestones are handed to pi one at a time (see `AGENTS.md`). Each has a
goal, the files it may touch, and a gate. The reference for what a NEC
Japanese DOS ships is MS-DOS 3.3D (`NEC 日本語MS-DOS 3.3D 基本機能セット.zip`).

Current state (`release/msdos-va`, f8cd7e8): VAIO.ASM provides CON, AUX
and PRN stubs, CLOCK$ and a 2HD-only (1024 x 8 x 77 x 2) floppy driver;
VAFORMAT and VASYS handle 2HD; CHKDSK and RECOVER accept 1024-byte sectors.

## Japanese support

How the two reference ports do it:

- FreeDOS(98) (`lpproj/fdkernel`, `nec98/`): the kernel is built with
  `-DJAPAN -DDBCS`, so path parsing, FCB names and upper-casing skip DBCS
  trail bytes; the DBCS table is hard-coded (81-9F, E0-FC). Its own CON
  (`nec98/kernel/int29dc.c`) buffers the lead byte in the NEC work area
  0060:0115/0116, converts Shift-JIS to JIS and writes text VRAM, and
  parses the NEC MS-DOS escape sequences itself. There is no built-in
  FEP: an external FEP (ATOK, VJE, NEC's drivers) hooks keyboard input,
  and the INT DCh FEP calls (CL=E0h-FDh) are no-ops. FreeCOM
  (`freecom_dbcs2`) reads the DBCS table with INT 21h AX=6300h.
- FreeDOS-88VA: Japanese is planned (M24 output/NLS, M25 input, M26
  filenames). The ROM JFP (INT 8Dh) stays installed and its work areas
  lie below the kernel; the owner decided to replace it later with a
  project FEP that reads the dictionary from the machine's own ROM. INT
  87h and 88h write into kernel memory and return CF=1 there.

On the VA the ROM already provides what FreeDOS(98) had to write: the
text BIOS Chuput (INT 83h AH=00h, DX=Shift-JIS) draws kanji from the
kanji ROM and executes control codes and escape sequences, and the
keyboard BIOS main functions deliver JFP-converted characters. The NEC
FEP, dictionary, FONT.SYS and USKCGM from 3.3D are not needed.

MS-DOS 4.0 has the DBCS code paths already (`IF DBCS` in `v4.0/src/DOS`,
switch in `v4.0/src/INC/DBCS.SW`, empty `DBCS_TAB` in `DOSMES.ASM`), and
COUNTRY.SYS has the Japan/932 DBCS table. COMMAND, EDLIN, TREE, XCOPY,
FC, LABEL and RECOVER ask for the table at run time.

### J0 — NEC-style function keys with the label line

Maintainer decision (2026-11-21): NEC MS-DOS behavior from the start,
with the function-key labels on the bottom line.

What NEC MS-DOS does: F1-F10 send ESC S, T, U, V, W, E, J, P, Q, Z
(labels C1 CU CA S1 SU VOID NWL INS REP ^Z); the kernel line editor
treats ESC as the lead-in and uses those letters for its template keys;
INS sends ESC P, DEL ESC D, the arrows 0Bh/08h/0Ch/0Ah, HOME/CLR 1Ah;
SHIFT+F1-F10 carry user strings; ESC[>1h / ESC[>1l hide and show the
label line; KEY changes the strings through INT DCh CL=0Ch/0Dh, whose
entries are 0FEh + 5-character label + string. FreeDOS(98)
`nec98/kernel/conkey60.asm` has the full default table.

What the VA ROM already has:
- KB BIOS (INT 82h) main functions GetChar/SnsChar (AH=00h/01h) expand
  soft-key strings; DefSft (AH=03h) defines them (15 bytes for F-keys, 5
  for ROLL, INS/DEL, arrows, CLR, HELP, HOME) and redraws the labels;
  ExpCtrl (AH=02h) turns expansion on/off. The main functions go through
  the JFP; VAIO.ASM currently uses the primitive functions (AH=09h/0Ah)
  and drops keys with internal code 0 (all F-keys, arrows, INS, DEL...).
- Text BIOS (INT 83h) has a system-line screen type, and SftCtl
  (AH=2Fh) shows 0, 5 or 10 key labels on its bottom row, shifted or not.
  The screen editor BIOS (INT 94h, InitScr/AlcSysL) sets up a 25-line
  main screen plus a 1-2 line system line that also holds the JFP area.
- MS-DOS 4.0: `STDSW.ASM` selects ESCCH=0 and CANCEL=ESC for IBM, and
  ESCCH=1Bh, CANCEL=Ctrl-X otherwise; `DOSMES.ASM` already contains the
  non-IBM ESCTAB with exactly the NEC letters.

#### J0.1 — Probe the ROM (no product change)
- Goal: a small COM program (`tests/pc88va/FKPROBE.ASM`) run under the
  current MS-DOS 4 VA system that answers, with screenshots and hex dumps:
  1. Can the system line be set up from DOS (INT 94h InitScr/AlcSysL or
     text BIOS Spltscn/SftCtl) without breaking DOS output, and does
     Chuput/Putstr output then scroll only the main screen?
  2. What does SftCtl display as the label: the string itself, or a
     separate label? Is the 0FEh + 5-byte label form understood?
  3. With DefSft strings defined, what do GetChar/SnsChar return for
     F1, SHIFT+F1, INS, an arrow (AX, BX per byte)?
  4. Does GetChar work at all under MS-DOS 4 VA? Find and report why
     v2.0 commit 714a26e bypassed the JFP.
  5. Which RAM does the KB BIOS/JFP use for soft keys (must not overlap
     IO.SYS/MSDOS.SYS).
- Gate: written report in `docs/J0-probe.md` with the answers and
  evidence; the maintainer chooses the design from it (ROM soft keys or
  a driver-side key table) before J0.2.

Decision after J0.1 (`docs/J0-probe.md`, accepted 2026-11-21): input
comes from a NEC key table in VAIO.ASM on the primitive KB queue; the
ROM draws the labels only (text-BIOS 24+1 split, SftCtl, DefSft with the
0FEh + label form, expansion not used). The ROM main input path is not
used until the JFP initialization question is probed (before J3). CLS
is broken today (CON attribute 8003h lacks the special-device bit, so
COMMAND's PC88VA CLS writes ESC[2J through CON, which drops ESC); fix it
in J0.4. ROM-internal addresses are not published in this repository.

#### J0.2 — Kernel: NEC line-editor keys
- Goal: under PC88VA, MSDOS.SYS uses ESCCH=1Bh and the non-IBM ESCTAB
  (ESC S/T/U/V/W/E/J/P/Q/Z, ESC D backspace). Decide CANCEL against the
  3.3D user's guide (PDF in the zip) and record the choice.
- Files: `v4.0/src/DOS/STDSW.ASM`, `DOSMES.ASM`, build files. No VAIO
  change.
- Gate: a test program that feeds the sequences through a CON stub or
  INT 21h AH=0Ah with redirected input shows each template function
  working; IBM build unchanged.

J0.2 accepted 2026-11-21 (`topic/j02-nec-line-editor`, 3d5da84 +
docs): steps 1-4 and 6-8 pass; step 5 is blocked by B1, which the IBM
baseline reproduces. ESC Z inserting ^Z was checked at the prompt.
After merging B1, step 5 passed 3/3 on vaeg VA2 (`COPY CON T.TXT`, two
lines, ESC Z: T.TXT = "ABC\r\nDEF\r\n").

#### B1 — COPY CON stalls (accepted 2026-11-21)
- Cause (`docs/B1-copy-con-stall.md`): vaeg accepts an IRQ between
  `MOV SS` and `MOV SP`, so VAIO's switch to its private request stack
  corrupted DOS data. VAIO now masks IRQs across both switches (857b4fc).
- The emulator bug itself (no interrupt shadow after MOV SS / POP SS in
  the uPD9002 core) is fixed in vaeg separately; other code that relies
  on the shadow (the kernel's own stack switches) is exposed until then.

#### J0.3 — CON input: NEC function keys
- Goal: F1-F10, SHIFT+F1-F10, INS, DEL, arrows, HOME/CLR, ROLL deliver
  the NEC default codes (table above / conkey60.asm) to DOS, using the
  design chosen after J0.1.
- Files: `v4.0/pc88va/VAIO.ASM` (CISTAT, CINP, CON_FLSH).
- Gate (vaeg): DIR then F3 recalls it; F1, F2 x, F4 x, F5, F6, INS, DEL,
  → and ← behave as on NEC MS-DOS; `COPY CON` ends with F6; ASCII, Ctrl
  keys and STOP (Ctrl-C) unchanged.

J0.3 accepted 2026-11-21 (`docs/J0.3-fkeys-input.md`,
`docs/J0.3b-editing-keys.md`): VAIO key table in NEC layout on the
primitive queue; F1-F10, SHIFT+F, INS, DEL, arrows, HOME/CLR, ROLL and
HELP match NEC MS-DOS 3.3D observed in NP2kai (12/12 keys), including
the caret echo of UP/RIGHT/HOME and Backspace removing a caret pair.
Cost: 544 bytes of conventional memory.

#### J0.4 — Label line
- Goal: the bottom line shows the ten labels at boot (C1 CU CA S1 SU VOID
  NWL INS REP ^Z, SHIFT shows the shifted set); DOS output scrolls above
  it; CON output handles ESC[>1h (hide) and ESC[>1l (show), and CLS keeps
  the line.
- Files: `v4.0/pc88va/VAIO.ASM` (init, OUTCHR).
- Gate (vaeg): labels visible after boot; `DIR` of a long directory
  scrolls without overwriting them; `ECHO` of ESC[>1h / ESC[>1l hides and
  shows them; free memory reported before/after.

J0.4 accepted 2026-11-21 (`docs/J0.4-label-line.md`): 80x25 text
(24 + ROM label row) on VA and VA2; labels from the VAIO table via
DefSft/SftCtl; CON handles ESC[>1h (25 text rows), ESC[>1l, ESC[2J,
ESC[H, which also fixes CLS. Cost 320 bytes. Open: SHIFT labels show the
CR of `date`/`time` as a glyph; compare with NEC in J0.5.

#### J0.5 — KEY command and INT DCh
- Goal: INT DCh CL=0Ch (read) and CL=0Dh (write) for the function-key
  table in NEC format, and a project-written KEY.COM (list, set one key,
  load/save a table file).
- Files: `v4.0/pc88va/VAIO.ASM` (INT DCh handler), new `pc88va/VAKEY.ASM`.
- Gate (vaeg): `KEY` lists the defaults; setting SHIFT+F1 to `dir a:` +
  CR runs DIR when pressed and updates the label; values survive until
  reboot.

J0.5 accepted 2026-11-21 (`docs/J0.5-key-command.md`): INT DCh
CL=0Ch/0Dh match NEC 3.3D (compact 386-byte and extended 786-byte
tables, 15+NUL truncation); labels follow writes. `pc88va/VAKEY.ASM`
(KEY.COM): list, set, save/load (VA file format); no full-screen menu,
no NEC KEY.TBL format. Adding KEY.COM to the disk needs the builder
change in `docs/J0.5/build-key.patch` (FreeDOS-88VA/freedos). Cost 288
bytes.

### J1 — DBCS kernel
- Goal: MSDOS.SYS built with `DBCS = TRUE` and `DBCS_TAB` = 81-9F,
  E0-FC; country 081 as default.
- Files: `v4.0/src/INC/DBCS.SW` (or a PC88VA-conditioned switch),
  `v4.0/src/DOS/DOSMES.ASM`, build files.
- Gate: builds; on vaeg, INT 21h AX=6300h returns the table; a file whose
  name contains a Shift-JIS character with trail byte 5Ch (「表」 = 95 5C)
  can be created, listed, renamed and deleted; ASCII behavior and
  existing boot unchanged.

J1 accepted 2026-11-21 (`docs/J1-dbcs-kernel.md`): DBCS kernel paths
on for PC88VA, DBCS table 81-9F/E0-FC, Japan/932 country defaults (dates
YY-MM-DD). Wildcards match NEC (`??` per double-byte character). SHARE
needed a symbol alias. Cost 1,440 bytes. Legacy edge cases (malformed
paths, split pairs at FCB field ends) are noted, not exercised.

### J2 — Japanese console output
- Goal: CON write passes Shift-JIS pairs and escape sequences to Chuput
  instead of dropping bytes outside 20h-7Eh. Buffer a lead byte across
  write calls (one-byte writes from INT 21h AH=02h must work).
- Files: `v4.0/pc88va/VAIO.ASM` (OUTCHR).
- Gate: `TYPE` of a Shift-JIS file shows kanji and half-width kana;
  a kanji split across two AH=02h calls displays; ESC[2J, ESC[K,
  ESC[row;colH and attribute ESC[..m work. List which NEC MS-DOS escape
  sequences the ROM does not support (do not emulate them yet).

J2a accepted 2026-11-21 (`docs/J2a-sjis-output.md`): CON draws
Shift-JIS pairs with Chuput and half-width kana with Putstr; a lead byte
waits across writes; output matches NEC 3.3D for valid text. Deliberate
difference: a lead followed by a control byte is dropped (NEC joins it
with the next printable byte). Cost 80 bytes. J2b: NEC escape sequences
and control codes.

J2b accepted as partial 2026-11-21 (`docs/J2b-escape-sequences.md`,
18/25 NEC pages): cursor addressing and movement, ESC=, save/restore,
CSI 6n, erase, insert/delete line, index, colors/reverse/secret, cursor
on/off, NEC control codes; label row protected. ESC[2J now also homes
(NEC). Cost 896 bytes. Follow-up J2c: cursor stays on column 80 after
printing there (NEC pending wrap), underline/blink, ESC)3 graph mode,
ESC[>3h/l 20-row mode. Malformed-sequence recovery differs on purpose.

J2c accepted (parts 1-3) 2026-11-21 (`docs/J2c-console-followups.md`,
J2b pages 22/25): NEC pending wrap at column 80, underline/blink (text
attribute mode 1), ESC)3/ESC)0 graph mode with the `g` indicator. Cost
416 bytes. Risk: the main screen now has ROM auto-scroll (VSCL) off;
VAIO scrolls CON output itself, but a program writing through INT 83h
directly would not scroll at the bottom.

#### J2d — open console items
- Keep ROM auto-scroll on except for the bottom-right edge write, or
  show that no direct INT 83h writers matter; test a direct-ROM writer.
- ESC[>3h/l 20-row mode in CON (ROM switching verified in J2c).
- J2d accepted 2026-11-22 (`docs/J2d-console.md`, VA/VA2): ROM
  auto-scroll back on for direct INT 83h writers (CON turns it off only
  for its own bottom-right edge write, keeping NEC pending wrap);
  `CSI >3h/l` 20/25-row mode (19+1 / 24+1 rows) with labels, hide,
  6n reports, scrolling, KEY and FEP checked in both. NEC parity 24/25
  pages per DOS write method (page 23 malformed sequences stays a
  deliberate difference). Cost 272 B.

### J3 — Japanese input through the ROM JFP
- Goal: ROM kana-kanji conversion works at the prompt and in EDLIN. If
  J0.3 already moved CON input to the KB BIOS main functions, this is
  mostly verification plus the system-line JFP area; otherwise switch
  here (see J0.1 item 4 on why v2.0 commit 714a26e bypassed the JFP).
- Files: `v4.0/pc88va/VAIO.ASM` (CINP, CISTAT, flush).
- Gate: conversion on/off, convert and confirm a word at the prompt;
  backspace removes a whole kanji (with J1); Ctrl-C, function keys and
  cursor keys still behave as now; memory free unchanged.
- Open decision for the maintainer: keep the ROM JFP, or later share the
  project FEP planned in FreeDOS-88VA.

### J3 plan — try both input methods (maintainer, 2026-11-21)

Both paths are built and compared; neither replaces the other until the
comparison is done.

- J3.0 — probe the ROM JFP under DOS (init sequence, memory, screen
  area, behavior during a pending conversion). Shared groundwork.
- J3.0 accepted 2026-11-21 (`docs/J3.0-jfp-probe.md`): the ROM JFP
  converts under DOS after `ResJFP → KbFlsh → SetJFP` (the callback is
  null from the ROM's disk handoff; IntKb alone crashes). ZENKAKU toggles
  kana input, HENKAN converts, KETTEI confirms; GetChar returns one
  Shift-JIS word per character. The JFP draws its composition on the
  label row (row 1 when labels are hidden), consumes editing keys while
  composing, and `ResJFP` opens a `.DIC` and a `.DAT` file through
  INT 21h, so it must not run inside a DOS call. Work areas are below
  IO.SYS. pi recommended a project FEP; the maintainer wants both paths.
- J3a — ROM JFP: VAIO initializes the JFP and reads CON through the KB
  BIOS main functions with conversion; keep the J0.3 key table (ROM
  expansion off); place the JFP area so the label line survives.
- J3a accepted 2026-11-21 (`docs/J3a-rom-jfp-input.md`, VA/VA2 35/35):
  `JFP.COM` (`pc88va/VAJFP.ASM`) initializes the ROM JFP from the
  foreground and switches VAIO through private INT DCh CL=F0h; `JFP ROM`
  uses the ROM dictionary when the default `.DIC`/`.DAT` files are
  missing (the only tested case), `JFP OFF` returns to plain input.
  Labels come back after composition; ESC[>1h is deferred while the JFP
  is on. Cost 784 bytes. Risk: with real dictionary files, learning on
  KETTEI may write files through INT 21h inside a CON read — not tested.
  The builder needs `JFP.COM` added (patch in `docs/J3a/`).
- J3b — project FEP (as FreeDOS-88VA decided for its M21): a resident
  front end in VAIO or a separate driver, reading the conversion
  dictionary from the user's own machine ROM at run time; no dictionary
  contents and no ROM-internal details in this repository. Staged:
  J3b.1 dictionary-reader feasibility (private evidence only), J3b.2
  romaji/kana input, J3b.3 single-phrase kanji conversion with
  candidates, J3b.4 user dictionary.
- J3b.1 accepted 2026-11-21 (`docs/J3b.1-dictionary-feasibility.md`):
  the dictionary ROM window is readable from DOS (documented MemMode
  selector, IRQs masked while mapped); a direct reader looks feasible but
  is unproven (1-2 weeks). The documented JFP conversion functions
  (Sug1st/SugNxt/SugPrv) work with the ROM front end master-disabled, no
  INT 21h/83h during conversion. Next: J3b.2 project-owned romaji/kana
  input and composition UI with a backend interface; J3b.3 BIOS backend
  first, direct reader as fallback. Private evidence: `../pc88va/tmp/j3b/`.
- J3b.2 accepted 2026-11-21 (`docs/J3b.2-project-kana-input.md`, VA/VA2
  52/52): `JFP FEP` selects the project front end (`JFP ROM` the ROM
  JFP, `JFP OFF` plain); romaji and KANA-key composition on the system
  row, F7 katakana, BS/ESC/Ctrl-C, KETTEI confirms; backend interface
  begin/next/previous/cancel/commit with a katakana/hiragana stub.
  Cost 2,304 bytes. Open: Return during composition confirms **and**
  queues CR; check NEC FEP behavior in J3b.3 and follow it.
- J3b.3 accepted 2026-11-21 (`docs/J3b.3-bios-backend.md`, VA 640 KiB,
  VA2 256/640 KiB 48/48 each): kanji conversion through the documented
  JFP functions with the ROM front end master-disabled (日本語, 漢字,
  変換, 東京 as first candidates; phrase move/resize); confirmation
  without learning; 0 nested INT 21h/83h in 225 monitored BIOS calls.
  Return now confirms first and submits on the second press, as NEC's
  NECAIK does (NP2kai). Cost 544 bytes (project FEP total ~2.8 KiB).
- J3c — compare J3a and J3b (conversion quality, memory, speed, key
  feel, interaction with ESC/F-keys/labels) and choose the default; the
  other may stay selectable.
- J3c accepted 2026-11-22 (`docs/J3c-comparison.md`, VA 640 KiB, VA2
  256/640 KiB): both paths give the same candidates, ranks and
  segmentation on a 22-reading corpus (the machine ROM matters, not the
  front end), latency within one frame, no activation memory cost. FEP
  has no nested INT 83h, no learning call and validates BIOS output; ROM
  JFP enters INT 83h 10-106 times per trial and claims more pending keys
  (F6/F8/F10, SHIFT+F9/F10, ZENKAKU). Decision: `JFP ON` selects the
  project FEP; `JFP ROM` stays explicit; boot stays plain. Note: FEP's
  guard refuses activation when default `.DIC`/`.DAT` files exist, so
  `JFP ON` no longer means the old file-requiring ROM selection.
  Open: external dictionary files and ROM learning (NOT RUN); NEC uses
  Ctrl+XFER/Space where the VA uses ZENKAKU/HENKAN (kept VA keys).
- J3b.4 accepted 2026-11-22 (`docs/J3b.4-user-dictionary.md`, VA 640 KiB,
  VA2 256/640 KiB): `JFP ADD/DEL/LIST` edit the project-owned
  `A:\JFPUSER.DIC` (`JFPUD` v1, 8 records) in the foreground; `JFP ON`
  loads it into VAIO; whole-reading user matches come before the BIOS
  candidates; 0 nested DOS calls over the whole CON read. Firmware
  `AddWd`/`DelWd` deliberately unused. Cost +1,418 B resident in every
  mode. Open: capacity of 8 words fixed in VAIO (move the table to a
  block JFP.COM keeps resident and raise the limit); boot drive fixed
  to A: (revisit with D4 HDD boot); reload needs `JFP ON` after edits.
- J3b.5 — [DOS-owned user dictionary](J3b.5-user-dictionary-tsr.md):
  compact v2 records, up to 64 pairs, with v1 read compatibility. `JFP ON`
  loads/reuses the external table; `JFP OFF` detaches and frees it. No
  table is allocated in plain or ROM mode. The `A:` path and explicit
  reload after ADD/DEL are unchanged.
  Accepted 2026-11-22 (VA 640 KiB, VA2 256/640 KiB): the table is a DOS
  block with MCB owner 8 (system), allocated last-fit by JFP.COM; VAIO
  keeps 6 bytes of state and is 829 B smaller than J3b.4; 64 entries cost
  at most 7,904 B; no leak over 5 ON/OFF cycles; 0 nested DOS calls.
  [F1](F1-small-fixes.md#3-user-dictionary-on-the-boot-drive) removes the
  fixed A: path: the dictionary now follows the DOS boot drive.
- J3d — [Space converts and advances project FEP candidates](J3d-space-convert.md) using the queued key code only. Accepted 2026-11-25 (VA/VA2; Shift+Space is not a back key: the ROM queue has no modifier state for Space).
- J3d.2 — Alt+` toggle via a keyboard BIOS user trap: merged and reverted 2026-11-25 (Windows IME takes Alt+`); replaced by VAEG M170, US Right Ctrl = 全角. See [J3d](J3d-space-convert.md#j3d2-withdrawn).

### J4 — Japanese messages (optional)
- Goal: Japanese message file next to `USA-MS.MSG`, selected at build.
- J4 accepted 2026-11-23 (`docs/J4-japanese-messages.md`, vaeg VA/VA2):
  project-written translations (no NEC text) in `v4.0/src/MESSAGES/JPN-MS.tsv`
  (catalog overlay → Shift-JIS `JPN-MS.MSG` at build) and `JPN-ASM.tsv`
  (hard-coded DB strings in FC, SHARE, VAIO and the VA commands); builder
  `--messages ja|en` (patch `docs/J4/build-messages.patch`, includes the
  D1/A1 steps). Kernel, SYSINIT, COMMAND, 25 utilities and 6 VA commands
  checked on both models; answer keys stay ASCII (中止(A) 再試行(R) …);
  English build unchanged. COMMAND resident +80 B. Fail on an empty drive
  re-prompts in both languages (DOS behaviour). NOT RUN: real hardware,
  unexercised error branches, boot-sector diagnostics (still English).

### K1 — KANA lock and GRPH input

[K1](K1-kana-grph-keys.md): admit raw GRPH bytes only in CON graph mode,
as on NEC 3.3D (built-in GRPH codes 80h–9Fh, E0h–F7h from physical keys; FFxx user-defined keys kept). KANA-lock failure not reproduced on vaeg VA/VA2 (m153, M170). Accepted 2026-11-25.

## Release identity

R1 accepted 2026-11-21 (`docs/R1-boot-banner.md`): the boot COMMAND
prints `日本語MS-DOS version 4.00 Release <YYYYMMDD> (<track>, <8-hex>)`,
`for NEC PC-88VA Series Personal Computer`, `Ported by Nakata Maho`.
The builder writes `v4.0/src/CMD/COMMAND/VAREL.INC` (track `main` for
`release/msdos-va`, date from the lock or the commit date in JST);
`docs/R1/build-release.patch`. No resident memory cost.

## Disks

### D1 — DISKCOPY for 2D, 2DD and 2HD
- Goal: a VA DISKCOPY (`pc88va/VADCOPY.ASM`, installed as DISKCOPY.COM)
  that copies through the ROM floppy BIOS track by track, independent of
  the DOS driver, so it works for media IO.SYS cannot mount yet.
- Media: 2D, 2DD and 2HD (and 2HC 15 x 512 if the drive mode allows).
  For each track read the sector IDs (READ ID) and copy whatever is there:
  sector count, sector length 128/256/512/1024 (N=0-3), FM or MFM, and
  non-standard numbering such as N88-BASIC 16 x 256. Format the target
  track to the same layout before writing it.
- Use one drive (with swap prompts) or two; as much memory as is free
  for the track buffer, avoiding 64 KB DMA boundaries (VAFDXFER.INC).
- Report unreadable sectors and continue or abort as the user chooses;
  refuse to copy if source and target drive types differ.
- Files: new `pc88va/VADCOPY.ASM`, shared helpers in `pc88va/VAFDXFER.INC`.
- Gate (vaeg): byte-identical copies of a 2HD MS-DOS disk, a 2DD 640 KiB
  disk, a 2D 320 KiB disk and an N88-BASIC 2D disk (compare D88 images);
  one-drive and two-drive runs; error path on a damaged sector.

- D1 accepted 2026-11-22 (`docs/D1-diskcopy.md`): `pc88va/VADCOPY.ASM`
  → DISKCOPY.COM copies through the ROM floppy BIOS track by track
  (READ ID layout, N=0-3, FM/MFM, independent C/H, high R; 2D/2DD/2HD/
  2HC), formats blank targets, refuses detectable mode mismatch, `/V`
  verify, Abort/Ignore with a summary of skipped tracks. Mixed-N tracks
  cannot be reproduced (one N per uPD765 FORMAT) and are reported. One
  drive: VA2 256 KiB 5/13/25 swaps (2D/2DD/2HD), 640 KiB 1/3/5. Builder
  patch `docs/D1/build-diskcopy.patch`. vaeg bug: FORMAT dropped the FM
  density flag (fix `64e55e11`, PR). NOT RUN: real hardware, CRC-error
  data path, deleted data.

### D2 — SASI hard disk driver
- IO.SYS attaches one fixed disk per recognized SASI target (5–40 MB)
  through the ROM hard disk BIOS (602HDD). No partition table: NEC VA
  FAT12 is the default; the FreeDOS native-prefix FAT12/16 layout is also
  recognized. See [D2](D2-sasi-driver.md) for layouts and gates.

- D2 accepted 2026-11-22 (`docs/D2-sasi-driver.md`, vaeg VA/VA2, 256/640
  KiB): `v4.0/pc88va/VAHDD.INC` mounts NEC VA single-volume FAT12 (as
  PC-Engine HDFORM writes it: IPL blocks 0-3, FAT at block 4, 1024-byte
  sectors) and FreeDOS-88VA native-prefix FAT12/16; requests bounded
  before the BIOS; 64 KiB DMA splits with a bounce block. Interchange
  verified both ways with PC-Engine 1.0/1.1 and NEC MS-DOS 2.11. CHKDSK
  accepts NEC media bytes D0h-D3h and 3072 root entries. Resident cost
  +16 B without SASI, +1,216 B with one volume. [F1](F1-small-fixes.md#2-a-40-mb-secondary-sasi-disk-on-va)
  confirmed the VA BIOS does not recognize a 40 MB secondary (VA2 does).
  Not-ready/write-protect/hot removal and real hardware NOT RUN.

### D3 — SASI HDD format
- `FORMAT d:` or `FORMAT /H0` / `/H1` creates the NEC VA single-volume
  FAT12 layout; reboot to use the new volume. Like HDFORM, the default
  does not physically format the drive. The IPL and data areas remain
  untouched; HDD boot and system installation are D4 work.
- Depends on D2. See [D3](D3-sasi-format.md) for syntax, safety checks,
  and the vaeg comparison and interchange gates.

- D3 accepted 2026-11-22 (`docs/D3-sasi-format.md`, vaeg VA/VA2, 5/10/20/40
  MB): `FORMAT C:` (mounted) or `FORMAT /H0|/H1` (raw target) writes the
  NEC VA FAT12 layout byte-identical to PC-Engine HDFORM (which issues no
  physical format; traced); IPL blocks 0-3 and data untouched; `/V`
  label; Y confirmation; refuses current/boot drive, `/S`, absent or
  mounted-via-/Hn targets. A reformatted mounted unit stays offline until
  reboot. IO.SYS now reports A: as the one-based boot drive to SYSINIT.
  NEC interchange (PC-Engine, MS-DOS 2.11) passed. NOT RUN: real
  hardware, bad media (no surface scan, unlike HDFORM's read pass).

### D4 — HDD boot
- `SYS d:` on a mounted NEC FAT12 SASI volume or `FORMAT d:|/Hn /S`
  installs the SASI IPL and system files. IO.SYS sets the boot drive
  from the mounted target while preserving A: and B: as floppies.
- D4 accepted 2026-11-22 (`docs/D4-hdd-boot.md`, vaeg VA/VA2, 5-40 MB):
  the ROM boots SASI target 0 block 0 (512 B at 3000:0, V3) when the
  setup enables fixed-disk boot; `pc88va/VAHDBOOT.ASM` (blocks 0-3)
  loads IO.SYS/MSDOS.SYS through bounded FAT12 chains; HDD-only boot to
  C> with CONFIG.SYS/AUTOEXEC.BAT from C:; floppy boot with the HDD
  mounted; replaces a PC-Engine IPL only after confirmation. Fix 1
  found and fixed two floppy regressions (floppy SYS now copies
  COMMAND.COM; FORMAT /S fits 256 KiB). Builder patch
  `docs/D4/build-hdd-boot.patch` (after the D1 patch). NOT RUN: real
  hardware, physical boot switches, write-protect/interrupted writes.
  [F1](F1-small-fixes.md#1-system-file-dates) preserves the source
  timestamps of all three system files in SASI and floppy `FORMAT /S`
  and in `SYS`.

### D5 — Choose PC-Engine 1.05, PC-Engine 1.1 or MS-DOS at SASI boot
- One NEC-layout SASI volume holds PC-Engine 1.05, PC-Engine 1.1 and
  MS-DOS. `SYS C:` saves a foreign PC-Engine IPL and parks its system
  files under per-version names. The HDD boot menu lists the saved
  PC-Engine versions and MS-DOS, waits 10 seconds and then boots the
  entry chosen last; before starting a PC-Engine version it renames that
  version's files to their real names and runs its saved IPL.
  (Maintainer, 2026-11-26: three-way menu, default = last choice,
  coexistence by renaming at boot.)
- Gate (vaeg VA and VA2): build a volume with 1.05 and 1.1 by the
  documented procedure; each menu entry boots (PC-Engine to Ready with
  the right version, MS-DOS to C>); the timeout boots the last choice,
  including after a power-off between boots; CHKDSK clean in MS-DOS
  after every switch; a volume without saved IPLs boots MS-DOS with no
  menu (D4 behaviour); D4 HDD and floppy regressions.

## Follow-ups
- F1 accepted 2026-11-23 (`docs/F1-small-fixes.md`): FORMAT /S (SASI and
  floppy) and SYS keep the source files' date/time; a 40 MB second SASI
  disk is a VA BIOS limit (VA SENSE rejects target 1 type 3 although the
  controller reports it; VA2 accepts it; PC-98H54 is not in the VA drive
  list) — no code change; JFP keeps `JFPUSER.DIC` on the DOS boot drive
  (INT 21h AX=3305h; A: fallback).
- B2 M1 accepted 2026-11-23 (`docs/B2-dos40-bugs.md`): MS-DOS 4.01,
  PD0255 and IBM IR80263 fixes imported unchanged from tsupplis/
  msdos40-hacking (DEV, CTRLC, MKNODE, DISK3, FASTOPEN; FORMAT, MSINIT,
  GRAPHICS, ANSI not shipped on VA).
  M2 accepted 2026-11-23: MORE [filename] from the same project.
- B3 (`docs/B3-lookahead-buffers.md`): fixed VA/VA2 boot with
  `BUFFERS=n,m` by sizing the look-ahead allocation for the actual
  maximum sector size. Accepted 2026-11-23.

## Devices (later)
- AUX on the communication BIOS (INT 8Ah), PRN on the printer BIOS.
- A1 accepted 2026-11-23 (`docs/A1-aux-prn.md`, vaeg M163 = vaeg PR #86,
  VA/VA2 640 KiB, basics on VA2 256 KiB): PRN/LPT1 through INT 89h with
  Shift-JIS → JIS (`ESC K` … `ESC H`) via the BIOS, busy → `Not ready
  writing device PRN` with Retry/Abort, Ctrl-P; AUX/COM1 through INT 8Ah
  (9600 8N1 at boot, ROM RX queue, CTS), `COPY AUX`, `COPY … AUX`,
  `CTTY AUX`, IOCTL 4406h; `SPEED baud` (builder patch
  `docs/A1/build-speed.patch`). Also fixed a latent D2 bug: the ROM disk
  call flags (`CALLFL`) lay in the discarded SASI tail, so floppy-only
  boots read DOS memory as flags (DF=1 hung CHKDSK at some VAIO sizes).
  PRINT.COM not shipped (IBM INT 17h hooks); deferred by the maintainer (2026-11-23). NOT RUN: physical printers
  and serial devices.

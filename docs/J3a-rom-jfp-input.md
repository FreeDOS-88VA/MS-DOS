# J3a — Japanese input through the ROM JFP

JFP is **off at boot**. On a stock disk, run `JFP ROM`, then type `ECHO `, tap
ZENKAKU, type `nihon`, tap HENKAN, KETTEI, and Return. ZENKAKU switches
back to half-width alpha when no reading is pending. In half-width mode,
`JFP OFF` restores primitive CON input without reboot. `JFP ON` is the
strict default-file variant: a missing default file is an error and CON
stays plain. `JFP ROM` explicitly permits missing default files so it can
use the machine's built-in dictionary. No dictionaries are distributed.

## Design and decisions

- **Initialize in the foreground `JFP.COM`, not in a driver request.**
  [`pc88va/VAJFP.ASM`](../pc88va/VAJFP.ASM) runs at COMMAND (or from a batch
  file), with no DOS call outstanding. It reserves the system row, runs
  `ResJFP → KbFlsh → SetJFP`, checks the keyboard-side callback via
  `KyBook`, verifies the requested mode with `GetJFP`, and leaves ROM key
  expansion off. [J3.0](J3.0-jfp-probe.md) observed two DOS opens (`.DIC`
  and `.DAT`) from `ResJFP`. Doing that from a CON request would reenter DOS
  and its device stack. The COM observes the `3Dh` open results through a
  temporary INT 21h chain because `ResJFP` has no return status. It restores
  the vector before exiting; its temporary break/critical-error handlers
  prevent a DOS abort while the vector is hooked. Only `JFP ROM` permits
  file/path-not-found; other open errors reject the activation in both modes.
  The command does not validate default file contents. `SetJFP` starts at
  `0F00h` (half-width alpha, screen switching/dictionary editing/gaiji
  operations inhibited), using the documented 60/30 character limits
  (`618JFP` §6.18.2). Ordinary conversion does not use the screen-editor BIOS.
- **Private VAIO mode interface.** `INT DCh`, `CL=F0h`, `AX=4A46h`;
  `BX=0` query, `1` reserve, `2` commit, `3` release. The reply is
  `AX=464Ah`, `BX=0` plain, `1` active, `2` reserved but still primitive.
  Other registers and return flags are unchanged. The foreground command
  owns the transition protocol: reserve before ROM reset, commit only after
  successful configuration, and master-disable/flush the ROM before releasing
  on `OFF` or a failed activation. VAIO rejects commit without the link and
  conversion buffer pointers. The handler itself does not reset the ROM or
  call DOS. NEC-compatible `CL=0Ch/0Dh` and the `KEY` table are unchanged;
  the B1 interrupt masking around `SS:SP` switches is untouched.
- **CON input.** Active CON uses nonblocking `SnsChar`, then `GetChar` only
  for a ready character. A returned scan in BH selects the existing VAIO
  string, not the ROM string (`603KEYB` §6.3.2). The standalone BIOS sweep
  returned `62h–6Bh`, `82h–8Ah`, `36h–3Fh`, `AAh–AEh` and `BAh–BDh`
  in narrow mode (direct-alpha probe, `0F80h`); Shift+F10 did not come
  through in that sweep. In the `0F03h` wide probe, the
  ROM consumes several DOS keys as JFP mode keys even with no reading.
  VAIO therefore reserves F6–F10, Shift+F and ROLL/INS/DEL via the
  primitive head in idle wide mode, Shift+F10 in either width, and idle
  ESC/BS/Ctrl-C. The same table decodes both paths. With a reading pending
  the ROM gets the keys instead; a generated `0003h/FFFFh` after JFP cancel
  is not passed to DOS as a second break. A physical idle Ctrl-C still is.
  A primitive sense checks the head before a main poll; VAIO masks IRQs
  across that arbitration, and an empty head with no buffered ROM output
  does not enter the main poll. This prevents a newly arriving idle soft
  key from slipping past the arbitration.
- **Byte order and flush.** VAIO peeks the lead first, keeps a separate
  trail, and promotes the trail only on a consuming read. Key expansion
  and status keep J0.3 semantics. For idle-key arbitration it uses the
  documented JFP input/output buffer pointers (`618JFP` §6.18.6). On the
  tested ROMs the input starts with NUL when idle; the confirmation buffer
  keeps the just-returned word and clears earlier words in place. VAIO
  checks for a following word (bounded by the configured indirect limit)
  so a reserved raw key does not overtake confirmed input. This buffer
  behavior was measured, not guaranteed by `GetChar`'s public contract.
  Active flush drops VAIO caches and uses `KbFlsh` plus `GetJFP`/`SetJFP`
  to reset the ROM buffers while retaining the mode; `KbFlsh` alone left
  stale confirmed output in a probe. It never uses `ResJFP` for a flush.
- **Labels and hidden mode.** The system row is reserved for the entire
  enabled interval, even if the requested layout is 25 text rows. Hiding
  while enabled is deferred until `JFP OFF`; the latest hide/show request
  wins. This prevents the ROM from using row 1 of DOS text, including on
  the first mode change. The JFP owns the system row during composition;
  label cells that the ROM does not redraw may still be visible at the right.
  Calling `SftCtl` or `DefSft` to reclaim it while enabled was not reliable:
  tests left JFP mode labels in place or moved composition to the main
  cursor. VAIO instead repaints the idle row from its own six-cell KEY
  labels, using the documented V3 TVRAM window and the fixed J0.4 split.
  It preserves the bank register and IRQ state, never paints over a
  pending reading, and redraws on Shift changes. `OFF` gives back the
  requested J0.4 split. After ROM use the idle painter also assists plain
  labels when shown: on VA, master-off and `SftCtl` alone did not restore
  the Shift-driven label updates. Fresh plain boots still use ROM labels
  as before.

## Gate

**VA 35/35; VA2 35/35.** Both used vaeg PR #82,
`Rel.20261121 (m153, 6367e5d3)`, SHA-256
`a3ab65a03eac9fd2abccca3d51b8e464266a4b6141b9d5132b5b667495655906`.
Counts are checks, not boots. The runners completed 25 cold starts per
model; see the [checker output](J3a/observations.txt) and
[build comparison](J3a/build.txt).

| Brief item | VA | VA2 | Evidence |
|---|---:|---:|---|
| 1. Disabled regressions and memory | 22/22 | 22/22 | J0.3 steps 1/5/9 (8), J0.4 steps 1–5 (10, with the current NEC clear+home behavior), KEY list (1), J2a `TYPE SJIS.TXT` (1), CHKDSK before/after (2). |
| 2. COMMAND prompt | 1/1 | 1/1 | `日本` on the system row before KETTEI, in the DOS line after KETTEI, and printed by ECHO. [VA](J3a/va-prompt.png) · [VA2](J3a/va2-prompt.png). |
| 3. COPY CON / F10 / TYPE | 1/1 | 1/1 | `J.TXT` exactly `93 FA 96 7B 0D 0A`; F10 worked while still in wide mode. [VA](J3a/va-apps.png) · [VA2](J3a/va2-apps.png). |
| 4. Kanji filename | 1/1 | 1/1 | `DIR` listed `日本`; root entry name was `93 FA 96 7B` with space padding, and file contents were `x` + space + CRLF. |
| 5. EDLIN | 1/1 | 1/1 | Insert, F10, list, save, TYPE. `E.TXT` held `93 FA 96 7B 0D 0A 1A`; screenshots linked in item 3. |
| 6. Editing | 6/6 | 6/6 | BS reduced `ai` to `あ`; ESC and Ctrl-C cancelled without changing the DOS line; idle Ctrl-C still broke it. Pending F1 did not leak. F1/F3 recalled the template and BS erased both columns of `本`. |
| 7. Labels | 2/2 | 2/2 | Normal labels before composition, ROM candidate on the system row, pixel-identical labels after confirmation. Hidden at start and again after OFF; text row 1 unchanged and hide deferred while active. |
| 8. Disable | 1/1 | 1/1 | `JFP OFF` returned to plain input; Shift labels and their release restored normally. |
| **Total** | **35/35** | **35/35** | |

Supplemental on both models: strict `JFP ON` on the stock disk reported the
missing files and restored the plain prompt; the full 43-tap keyboard stream
matched in both idle widths (all F/Shift+F and editing keys, modifier arrows,
BS/ESC/Ctrl-C, including keys expected to return nothing). `JFPBYTE` verified
`93 FA 96 7B`, repeated status without advancing, flush after the lead, and
fresh ASCII input. Its INT 21h monitor saw no calls in `3Ch–42h` during those
input/flush tests. `KEY F1` updated both the input string and the visible
label while JFP was enabled.

**Memory:** CHKDSK reported 655,360 B total and **529,040 → 528,256 B free
(−784 B)** on each model. Enabled also measured 528,256 B free, so there was
no additional conventional-memory cost in the tested ROM-fallback case.
The resident VAIO grew by 795 B before paragraph rounding. IO.SYS grew from
21,098 to 21,898 B (21 → 22 boot sectors); `JFP.COM` is 848 B and nonresident.

## Reproduce

1. Use [R1's scratch builder setup](R1-boot-banner.md#reproduce),
   FreeDOS-88VA/freedos `7f467a2187a9e15c0c1bb84f179f214fe925153f`, emu2
   `9d8698d06e67359bc8b230c2d19d5b1503e60819`. Apply the **build.py only**
   hunks of R1 (`git apply --include=experiments/msdos4-va/build.py ...`);
   the tested template still invokes `VER` in `AUTOEXEC.BAT`. Build the
   base pin `38044f85f516886797c3b7990a683ce1b9ad2ebe` on the `main` track.
   For the candidate, apply [`build-jfp.patch`](J3a/build-jfp.patch) to a
   second scratch builder, pin `e240386d63c158eaa32d23faf6a7fc372b2ca985`,
   set `msdos.branch=topic/j3a-rom-jfp-input` and `msdos.track=j3a`, and run
   `build.py --output` against a new directory. No edits to the builder
   repository are necessary.
2. Prepare the candidate test image as in the [J2a reproduction](J2a-sjis-output.md#reproduce)
   (including `LABELCHK.COM`, `CONKEY.COM`, `LONG.TXT`). For the enabled
   checks append `JFPBYTE.COM` assembled with
   `nasm -f bin docs/J3a/JFPBYTE.NAS -o "$S/JFPBYTE.COM"`; use
   `docs/J1/media.py`'s `pack_va` helper. Keep all images and captures in
   `$S`, outside the repository.
3. Use the same vaeg binary on both models, with local model ROMs, no saved
   config and no backup RAM. `BASE_CISTAT` and `AFTER_CISTAT` below are
   addresses of **VAIO code**, from the MASM listings. Run with Pillow and
   the vaeg QA decoder available:

   ```sh
   export PYTHONPATH="$VAEG_SOURCE/tools/qa:$BUILDER_EXP"
   BASE_CISTAT=1000:06D0 AFTER_CISTAT=1000:0954 \
     python3 -B tests/pc88va/wrap-run.py "$VAEG" "$ROMS" "$BASE_D88" "$AFTER_D88" \
       "$REGTEST_D88" "$S/plain" base-boot after-boot base-mem after-mem dir \
       display toggle erase eof-1 eof-2 eof-3 ctrl-z cancel-break base-regression \
       after-regression type j1-key
   AFTER_CISTAT=1000:0954 python3 -B docs/J3a/run.py \
     "$VAEG" "$ROMS" "$JFPTEST_D88" "$S/enabled"
   python3 -B docs/J3a/check.py "$S/enabled" "$S/plain"
   ```

**NOT RUN:** physical hardware, VA3, 2D, OEM DOS input comparison, an actual
`AUTOEXEC.BAT` activation, successful loading of external default files,
corrupt/default-file content validation, injected critical media errors or
Ctrl-Break during reset, dictionary learning persistence, long/mixed-width
composition coverage, arbitrary INT 83h/8Dh users changing the screen or
JFP behind VAIO, or alternate emulator builds for the counted gate.

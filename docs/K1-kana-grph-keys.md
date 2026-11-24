# K1 — KANA lock and GRPH input

**GRPH fixed; KANA-lock failure not reproduced.** On vaeg m153, VA and VA2 already accept half-width kana with the host KANA lock on. The GRPH problem is separate: VAIO was feeding raw graphic bytes to DOS in normal kanji mode. NEC 3.3D only admits those bytes in graph mode. VAIO now does the same.

## Reproduction and diagnosis

Japanese 2HD images, 640 KiB, vaeg m153 `6367e5d3`, local ROM sets, no saved config or backup RAM. Base `46e9cb0`; driver change `d847700`. Each matrix used plain boot, project `JFP ON` in narrow width, `JFP ROM` in narrow width, and `JFP OFF` **after** `JFP ON`. The DOS probe hooked INT 82h during a real INT 21h read. It logged successful BIOS calls and the documented keyboard work-area shift/lock byte (Technical Manual §6.3): KANA `08h`, GRPH `10h`, and left Shift `01h`. This is keyboard BIOS RAM, not JFP's width byte.

**Lock versus tap:** vaeg's scripted `key-tap KANA` sends a physical make and break; it does not emulate the host's mechanical lock toggle. For applications the script leaves KANA made while entering kana, then breaks it to return to ASCII. A separate X11 run used vaeg's host Right Alt binding: release Right Alt, then type; the lamp and BIOS bit stayed on. A second tap unlocked both. On each model, in each of the four modes, the locked `A 3 E 4` plus unlocked `A` returned `C1 B1 B2 B3 61` through 0Ah. The same worked before the fix in the VA2 plain-mode host control. [VA](K1/va-lock.png) / [VA2](K1/va2-lock.png) show the host lock and unlock on the candidate.

The entries below agree on VA and VA2. `Prm` is AX (`scan:internal code`) from 0Ah and, on the primitive path, 09h. In ROM mode the normal printable keys use 0Ah to peek, then `SnsChar`/`GetChar` (01h/00h), which both return the AX/BX pairs shown. The other three modes do not use 01h/00h; forcing them into plain DOS with an uninitialized callback is not a valid comparison (see [J3.0](J3.0-jfp-probe.md)). The DOS columns describe 08h and 0Ah, before echo or storage; repeated values here are not duplicated DOS bytes.

| Keys | Shift/lock byte at read | Prm AX | Main AX/BX in ROM | DOS 08h / 0Ah, base → K1 |
|---|---:|---|---|---|
| `A` unlocked; `A` after raw KANA tap; `A` after raw Shift+KANA chord released | `00` | `1D61` | `0061/1D61` | `61` unchanged |
| KANA active, `A 3 E 4` (physical JIS positions) | `08` | `1DC1 03B1 12B2 04B3` | `00C1/1DC1 00B1/03B1 00B2/12B2 00B3/04B3` | `C1 B1 B2 B3` (ﾁｱｲｳ), unchanged |
| KANA active, Shift+E | `09` | `12A8` | `00A8/12A8` | `A8` (small ｨ), unchanged |
| GRPH + `A Q 0 Z` | `10` | `1D9E 109C 0AF7 2980` | `009E/1D9E 009C/109C 00F7/0AF7 0080/2980` | Kanji mode: `9E 9C F7 80` → no bytes. Graph mode: all four unchanged. |
| GRPH + `1`, `3` | GRPH held across the sequence | No ready entry | No ready return | No bytes, unchanged |
| GRPH + Space | `10` | `3420` | `0020/3420` | `20`, unchanged |

The scan remains the letter/number scan: no edit-slot collision or unknown-scan loss for the tested kana/graphic pairs. In narrow ROM mode, `JFPPOLL` left these printable keys on the main path and the ROM returned them. `JFP ON` in narrow width passed kana through `FEPKEY` without claiming it. Full-width composition is intentionally different, and its regression checks are below. None of `CISTASCAN`, `CISTAE`, the soft-key reservation in `JFPPOLL`, or the FEP is the cause of the reported lock failure in these runs.

**NEC comparison:** NP2kai `5939e0c`, NEC Japanese MS-DOS 3.3D system disk 1, started at `A>`. Used NP2kai's `key.txt` bindings (`F8=GRPH`, `F9=KANA`) for unambiguous guest keys. `ECHO` at the prompt displayed `ﾁｱｲｳ`; GRPH `A 1 Q 0 Z` in the default mode produced no prompt characters. [EDBYTES comparison](K1/nec-bytes.png): with KANA `A 3 E 4`, GRPH `A 1 Q 0 Z 3 Space`, then unlocked `A`, 0Ah returned `C1 B1 B2 B3 20 61 0D`. After `ESC ) 3` the GRPH sequence plus `A` returned `9E 9C F7 80 20 61 0D` and displayed the four graphics.

The base VA image delivered those graphic bytes even in kanji mode; DOS 08h proves they were not lost in the kernel. In a cooked line they overlap the Shift-JIS lead ranges `81h–9Fh` and `E0h–FCh`; kana `A1h–DFh` does not. The graphics can be paired or rendered incorrectly, or consume a following editing key. Matching NEC requires **rejecting the raw GRPH codes on input outside graph mode**, not changing the DBCS table. An intentional limit remains in explicit graph mode: VA DOS 0Ah still treats an isolated `9Eh` as a lead (`KSTRIN.ASM:SAVCH`), so the first CR is stored as its second byte and the second CR ends the line. DOS 08h returns `9E 0D` without that interpretation. NEC 3.3D graph-mode 0Ah behaved the same way: after the second CR, both systems returned `9E 0D` as data plus the terminating `0D`. Graph mode changes rendering and admission, not DOS's byte interpretation.

## Fix and gate

`VAIO.ASM:CISTAA` filters the queued one-byte graphic ranges `80h–9Fh` and `E0h–FFh` against `OUTGRAPH` (`ESC ) 3` / `ESC ) 0`). It does not poll a live modifier that might already have been released, and skips the rejected entry before caching it. Function/edit-key strings and JFP-generated words/bytes use their existing paths. No KANA-specific driver change was made.

| Check | VA | VA2 |
|---|---|---|
| 08h and 0Ah × graph/kanji × four CON modes, before/after | PASS | PASS |
| KANA active at ECHO, COPY CON, EDLIN and both TYPE displays, then unlocked ASCII, four CON modes | PASS | PASS |
| Host-triggered KANA lock and unlock in 0Ah, ECHO, COPY CON and EDLIN, four CON modes | PASS | PASS |
| F1–F10, Shift+F1–F10, `KEY F1`, arrows incl. shift/ctrl, HOME, ROLL/INS/DEL, HELP, BS, ESC, Ctrl-C | PASS | PASS |
| J0.3b mixed caret input, erase with BS / LEFT / DEL through 0Ah | PASS | PASS |
| Project romaji/HENKAN/KETTEI `日本` and direct KANA+dakuten `ちが`; ROM wide conversion `日本` | PASS | PASS |

`J.TXT = B1 B2 B3 61 0D 0A`; `E.TXT` has the same bytes plus `1A`. The gate checked FAT bytes and text cells, and compared the 104-byte soft-key/edit stream and FEP candidate cells before/after. See [gate output](K1/gate.txt) and the [host-lock application capture in ROM mode](K1/va-rom-apps.png). VA2's ROM mode showed literal graph output without the `g` label before and after; the marker is not used to decide whether graph input is enabled.

**Memory:** VAIO `RESEND` grew `25EAh → 25FEh` (+20 B before rounding). CHKDSK free memory was **524,032 → 524,016 B** on both models (one paragraph). IO.SYS is 28,797 B before and after (link padding absorbs the difference).

**NOT RUN:** physical hardware, vaeg versions/configurations other than m153 defaults (including host romaji input), 2D, VA3, reduced RAM, exhaustive modifier/scan combinations, GRPH during an active wide JFP composition, externally supplied dictionaries, full historical J0/J3 suites or non-PC-88VA builds. The maintainer's KANA-lock failure remains open if reproducible in a different configuration.

## Reproduce

1. In scratch use FreeDOS-88VA/freedos `main` at `1ed657b96f31a3b8664641d533e4da0aaba49b56`. Point `components/msdos` and `components/emu2` to their checkouts, pin `lock.json` `msdos.commit` to each of the revisions above, and run `python3 -I experiments/msdos4-va/build.py --output <dir>` (Japanese default). D88 SHA-256: `54486f20782b26fd0bf3aeb90d316f4e603ce24dbca88d713cf6f72ccfcf483e` / `584637b05baa5d70e18a43576a1fce4f28816d671bc38db98c25a5403a9b08b0`.
2. Assemble [K1BYTES](../tests/pc88va/K1BYTES.NAS) with `nasm -f bin`, build `CONKEY.COM` as in [J0.3](J0.3-fkeys-input.md#build-and-run), and add them with `docs/J1/media.py`'s `pack_va` to separate scratch copies of the base/candidate. `K1BYTES` reads 0Ah, `K1BYTES R` reads 08h, `K1BYTES G` enables graph mode, `K1BYTES N` restores kanji mode. Trace records are function, AX little-endian, BX little-endian (main only), shift byte.
3. For each probe disk use fresh scratch run directories. `AFTER_CISTAT` is the VAIO driver listing address (unchanged before/after); the vaeg SHA-256 is `a3ab65a03eac9fd2abccca3d51b8e464266a4b6141b9d5132b5b667495655906`.

   ```sh
   export AFTER_CISTAT=1000:0A73
   export PYTHONPATH="$BUILDER_EXP:$VAEG_SOURCE/tools/qa"
   python3 -B tests/pc88va/kana-grph-run.py "$VAEG" "$ROMS" "$BASE_PROBE" "$S/base"
   python3 -B tests/pc88va/kana-grph-run.py "$VAEG" "$ROMS" "$K1_PROBE" "$S/k1"
   python3 -B tests/pc88va/kana-grph-check.py "$S/base" "$S/k1"
   ```

4. For the host lock control, use X11 with the same vaeg binary (not dummy video), type `K1BYTES`, and tap/release Right Alt, type `a3e4`, tap/release Right Alt, type `a` and Return. Repeat after `JFP ON`, `JFP OFF` and `JFP ROM`. For NEC, use the [J0.3b NP2kai setup](J0.3b-editing-keys.md#reproduce), put the two bindings above in the scratch BIOS path's `key.txt`, and use the arrow keys and Return to exit MENU (F9 is rebound). For the byte test, add `EDBYTES.COM` and a graph-mode helper that writes `1B 29 33` to CON, using `pack_nec` on a disposable copy. Hold the remapped modifiers across the specified keys. Keep images, ROMs and raw emulator captures out of the repository.

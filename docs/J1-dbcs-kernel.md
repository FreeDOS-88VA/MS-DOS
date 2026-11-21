# J1 — Shift-JIS in the PC-88VA DOS kernel

**Gate: VA 64/64, VA2 64/64** on vaeg PR [#82](https://github.com/nakatamaho/vaeg/pull/82), `Rel.20261121 (m153, 6367e5d3)`. The main wildcard result is that NEC DOS treats a Shift-JIS pair atomically but requires **two `?` bytes** to match it. On both VA models and on NEC, `DEL ?.TXT` leaves a one-kanji name alone; `DEL ??.TXT` removes it. Conventional memory cost: **1,440 bytes** on each model. See the [VA checks](J1/va-observations.txt), [NEC observations](J1/nec-observations.txt), and [build comparison](J1/build.txt).

## Product changes

- `v4.0/src/INC/DBCS.SW` selects the existing DOS DBCS code only under `PC88VA`. The resident `DBCS_TAB` in `v4.0/src/DOS/DOSMES.ASM` has the same size as before; its length is six including the terminator, with bytes `81 9F E0 FC 00 00`. INT 21h/6300h returns the ranges, not the length. The built-in country is 081 and code page 932, with date/time/currency settings, high-byte mapping and collation from the existing Japan/932 definitions in `v4.0/src/DEV/COUNTRY/MKCNTRY.ASM`. The ASCII lowercase mapping still applies to standalone ASCII.
- The first DBCS build assembled the kernel but failed to link `SHARE.EXE` with L2029 on `IntCNE0`. The kernel and SHARE link the same `MSDOSME.OBJ`: its escape dispatcher now references the DBCS editor's input wrapper. `v4.0/src/CMD/SHARE/SHARELNK.ASM` resolves the reference to the existing input stub, at the same address, only for PC88VA. SHARE never runs the dispatcher. In the linked executable, only the embedded NLS tables and MZ checksum changed. As a supplemental smoke check, on both models a second `SHARE` reported `SHARE already installed`, and running the API probe with SHARE resident gave the same results and file contents. Lock contention was **NOT RUN**.
- No other runtime fixes were needed for the tested cases. No changes to VAIO, `pc88va/`, COMMAND, utility switches, the disk builder, or console Japanese output/input.

## Review of the enabled code

The actual `IF DBCS` assembly branches are all in `v4.0/src/DOS/`. `BIOS`, COMMAND, DEBUG, CHKDSK and other programs can include `DOSSYM.INC` without having such a branch. The runtime table queries are in COMMAND `INIT.ASM`, EDLIN `EDLIN.ASM`, TREE `TREE.ASM`, XCOPY `XCOPY.ASM`, FC `ITOUPPER.ASM`, LABEL `LABEL.ASM` and RECOVER `RECOVER.ASM` (all INT 21h/6300h via literal or symbolic constants). This confirms the runtime selection, not execution of every utility. `COUNTRY.SYS` already carries a Japan table; its shipped bytes did not change.

| Area reviewed | Behavior and follow-up |
|---|---|
| Paths and names (`MACRO2`, `FILE`, `DIR2`, `MISC2`) | Path/component scans and copies are aware of lead bytes, including the forward scan used when backing over path components. `FILE`'s temporary-file path scan skips the trail before looking for a final separator; unlike the single-byte scan, the DBCS loop doesn't enforce the computed segment-end bound. UNC, malformed/dangling leads, and temporary-file API boundary inputs were **NOT RUN**. `DIR2` still has a commented-out full-width space special case in the device-name packing loop. |
| FCBs, search and wildcards (`FCB`, `FCBIO`, `DIR`, `DIR2`, `SEARCH`) | TestKanj looks up the current NLS ranges; ordinary case-mapping and separator tests are bypassed on trails. `MetaCompare` compares a DBCS word against a literal word or against `??`, not `?` plus a literal byte. Several edge-case paths look unfinished: `FCBIO` explicitly ignores split pairs at the field boundary, `FCB`'s overlength scan can keep walking past the full field, and `SEARCH`'s FAT first-byte `05h` to `E5h` conversion still has a `Need fix?` note. The special leading `E5h` FAT encoding, malformed and split names, device aliases, and 11-byte Japanese volume labels were **NOT RUN**. |
| Locale and console (`GETSET`, `CPMIO`, `CPMIO2`, `KSTRIN`, `DEV`, `DISP`, `CTRLC`, `DOSMES`) | `GETSET` supplies the current table pointer and skips pairs in buffer uppercasing. Its register-preservation comment for function 63h is misleading: the specified outputs include DS:SI or DL. DOS now uses `KSTRIN`, which saves both bytes and walks the buffer from its start to determine the preceding character on erase. The template copy code assumes a complete pair in the template; malformed caller-supplied templates were **NOT RUN**. The interim-console flag and parameter bytes in request packets are historical Far East support (the app ZF handling in `CPMIO` explicitly checks Korean CP 934). They do not add JFP input or Japanese rendering to VAIO. |

Read the corresponding FreeDOS(98) path scans, FCB parsing and NLS uppercasing (`kernel/newstuff.c`, `dosfns.c`, `fatdir.c`, `fcbfns.c`, `nls.c` at `c9ce245e0447`) as a reference. No FreeDOS code was copied.

## VA and VA2 gate

The 8086 [COM probe](../tests/pc88va/J1DBCS.NAS) and [scratch batch fixture](J1/media.py) send bytes without depending on Japanese display or input. The pairs are `95 5C` 表, `83 5C` ソ, `94 5C` 能, `90 5C` 申, `97 5C` 予, `81 7C` −, and `82 61` Ｂ, with lowercase ASCII in the inputs. `82 7C` is not a defined Shift-JIS character; `81 7C` is valid (`－` in CP932). `82 61` ends in ASCII `a` but is not an ASCII letter to uppercase. The verifier walks raw FAT12 directory/cluster chains, compares exact live paths and contents across the whole disk, and checks that no fixture file changed or unexpected path survived.

| Brief item | VA | VA2 | Checks |
|---|---:|---:|---|
| 1. INT 21h/6300h | 1/1 | 1/1 | `DS:SI` bytes match; AH=38h also returned country 81. |
| 2. File and directory operations | 22/22 | 22/22 | Seven each: direct create/open/rename/delete and MD/CD/RD plus directory rename via 56h; COMMAND batch MD/CD/COPY/REN/TYPE; COMMAND DEL of nested name followed by RD. One extra `ECHO MARK>` with a `7Ch` trail in the redirection operand: exact name and `MARK\r\n`, no extra file. |
| 3. Wildcards | 10/10 | 10/10 | Five FindFirst/Next patterns with single/paired bytes and ASCII decoys; three `DIR` patterns; two `DEL` patterns. The listing after `DEL ?` still contains both files; neither remains after `DEL ??`. |
| 4. FCB | 7/7 | 7/7 | AH=29h parse, 16h create, 0Fh open, 17h rename, 13h delete per name; open after rename also verified through the independent ASCIIZ API. |
| 5. Upper-casing | 1/1 | 1/1 | `82 61` stays intact in the FAT entries while the following ASCII `b` is stored as `42h`. |
| 6. Edited redirected 0Ah | 2/2 | 2/2 | `X 95 5C` + Backspace or ESC D + `Y` + CR returns `02 58 59 0D` (count + `XY\r`). No console injection needed. |
| 8a. J0.3 steps 1, 5, 9 | 8/8 | 8/8 | DIR/F3/Enter, F10 EOF on three cold boots, BS/VER, Ctrl-X/F3, Ctrl-C/recovery, Ctrl-Z EOF. The four `COPY CON` runs saved `ABC\r\nDEF\r\n` and the subsequent `TYPE` returned to the prompt. |
| 8b. J0.4 steps 1–5 | 10/10 | 10/10 | Boot with 24+1 rows (1), Shift/release (2), DIR/TYPE scrolling (2), CLS/bytewise erase and redirect (2), and hide/show via block, bytewise and reflow (3). |
| 8c. KEY, memory | 3/3 | 3/3 | KEY stdout matches all 31 slots in IO.SYS (1); CHKDSK before/after (2). |
| **Total** | **64/64** | **64/64** | Item 7 is the separate comparison below; the SHARE smoke test is supplemental. |

`*`, `?`, `??`, `?X`, `??X` produce masks `0F 02 0B 08 04` against `{表, A, 表X, AX}` (bits 0 through 3 respectively). In particular, `?X` matches `AX` but not `表X`; `??X` matches `表X` but not `AX`. This tests matching at the pair boundary, not just wildcard acceptance.

| CHKDSK, distribution disks | Before | After | Delta |
|---|---:|---:|---:|
| VA | 531,872 B free | [530,432 B free](J1/va-chkdsk.png) | −1,440 B |
| VA2 | 531,872 B free | [530,432 B free](J1/va2-chkdsk.png) | −1,440 B |

655,360 bytes total on both before and after. Hardware, 2D media, live Japanese input/display and other vaeg builds: **NOT RUN**. The two redirected editor cases exercise kernel buffer contents, not visual cursor/erase behavior; visual DBCS editing belongs to J2/J3.

## NEC comparison (brief item 7)

[NEC MS-DOS 3.3D](J1/nec-version.png) booted in NP2kai SDL2 `5939e0c6d5985c4c08fc70f289a83290e5d3e6f7`. Ran the same API probe and batches on the 2HD scratch image. Results were read from guest output and the FAT12 image after pending disk writes reached the host.

| Case | NEC 3.3D | VA and VA2 MS-DOS 4.00 |
|---|---|---|
| INT 21h/6300h and AH=38h | `81 9F E0 FC 00 00`, country 81 | Same |
| INT 21h files, MD/CD/RD, COMMAND MD/CD/COPY/REN/TYPE/DEL/RD | All seven pairs passed; raw filenames match | Same |
| Rename a directory with AH=56h | Returns error `02h` for all seven pairs. Probe then changes into and removes the original directory. | Renames each directory; CD/RD test the new name. Kept DOS 4.0 semantics. |
| Wildcards and delete | Same five search masks; `DEL ?.TXT` leaves the one-kanji file and the ASCII `AB` decoy, `DEL ??.TXT` removes both. See [NEC listing after `DEL ?`](J1/nec-wildcards.png). | Same |
| FCBs and `82 61` trail (ASCII-looking `61h`) | FCB probe passed; exact trail retained | Same |
| Redirected AH=0Ah, Backspace and ESC D | Both return `02 58 59 0D` | Same |
| `7Ch` trail in a **redirection operand** | Ordinary filenames work, but `ECHO MARK>` with this operand did **not** produce the intended file: the raw 8.3 entry starts `81 00 54`, and the payload is `MARK\|.TXT\r\n` (literal `|`, not a backslash). | Produces `81 7C .TXT` with exactly `MARK\r\n`. Did not reproduce the NEC redirection bug. |
| J0 regressions and KEY | **NOT RUN** as J1 comparisons; these are VA regression tests. | Results above. |

## Build and reproduction

- **Build:** Use FreeDOS-88VA/freedos `7f467a2187a9e15c0c1bb84f179f214fe925153f`, `experiments/msdos4-va` (already builds `KEY.COM`), and its pinned emu2 `9d8698d06e67359bc8b230c2d19d5b1503e60819`. Point scratch `components/msdos` at this local repository, use the default lock at `62fc532820ac373bbd78489e1aa7485371ce4c88` for baseline, and set `msdos.commit` to `c9d7a09` (full SHA in [build.txt](J1/build.txt)) for J1. Run `python3 -B experiments/msdos4-va/build.py --output "$OUT"` for each. The only changed shipped files are **MSDOS.SYS** (37,392 → 38,832 bytes) and **SHARE.EXE** (13,408 bytes both times); the other 34, including IO.SYS, COMMAND.COM, KEY.COM and COUNTRY.SYS, and the boot sector are identical. The D88 changes accordingly. The [build comparison](J1/build.txt) also lists changed objects and maps.
- **Non-PC88VA comparison:** Rebuilt baseline and J1 with `DEFINES = ()` in two scratch builder copies and removed `'-DPC88VA'` from the manual COMMAND bootstrap MASM invocation as well. All 36 shipped files and all compared `.SYS/.COM/.EXE/.OBJ/.MAP/.LIB` artifacts matched, and `cmp` of the two generated images passed. This tests build output without the switch, not an IBM-format boot image or IBM boot.
- **VA tests:** Reuse the named J0.4 vaeg executable (SHA-256 `a3ab65a03eac9fd2abccca3d51b8e464266a4b6141b9d5132b5b667495655906`) and its ROM setup. With distro images `$BASE_D88` and `$J1_D88`, the builder path `$BUILDER` and a scratch dir `$S` outside the repository:

  ```sh
  nasm -f bin tests/pc88va/J1DBCS.NAS -o "$S/J1DBCS.COM"
  export PYTHONPATH="$BUILDER/experiments/msdos4-va"
  # $REG contains LABELCHK.COM, LONG.TXT and CONKEY.COM per J0.4.
  python3 -B docs/J1/media.py va "$J1_D88" "$S/test.d88" "$S/J1DBCS.COM" --regressions "$REG"
  PYTHONPATH="$VAEG_SOURCE/tools/qa" python3 -B docs/J1/run-va.py \
    "$VAEG" "$VA_ROMS" "$BASE_D88" "$J1_D88" "$S/test.d88" "$S/runs"
  python3 -B docs/J1/verify-va.py "$S/runs" "$S/runs" "$S/test.d88"
  ```

  COM SHA-256 `e6a0009f2ceec0c4e001c6ba4d2f2cc17b88650d0ae47088970bb748722a4c82`; test D88 `e9323cbe15dabe0602e4a6c898bdd5c56a08ba7d7d39c6f66098cb709e04fdc0`. The counted J0 scripts ran before the final probe revision, on identical distribution disks or a scratch disk differing only in the unused J1DBCS.COM. The memory runs used unmodified distribution disks. The runner requires each cold run to reach `exit` and checks that every planned capture is present.
- **NEC tests:** Use the [J0.3b NP2kai setup](J0.3b-editing-keys.md#reproduce) and the SHA-verified system disk 1. Run `python3 -B docs/J1/media.py nec "$DOS33D_1_D88" "$S/nec.d88" "$S/J1DBCS.COM"` with the builder on `PYTHONPATH`. The helper deletes `README2.DOC`, `EMM386.SYS` and `EMM.SYS` on the scratch image and inserts the fixtures. Boot; cancel INSTDOS and exit MENU. At the root prompt run `J1DBCS`, `J1MAKE`, `J1DBCS L < BS.IN`, `REN J1LINE.OUT J1BS.OUT`, `J1DBCS L < ESC.IN`, `REN J1LINE.OUT J1ESC.OUT`. `CD J1DEL`, `TYPE TWO.OUT` shows the two files after `DEL ?`; use `CD ..` to return to root. Save a host scratch snapshot before `J1CLEAN` and another after it. A guest `DIR` was not sufficient to flush every pending write on our run; more disk I/O (including renaming `J1ESC.OUT` to `ESCNEW.OUT` and back) let the final changes reach the image. Decode each snapshot with `python3 -B docs/J1/check.py "$SNAPSHOT"`. No NEC media, ROMs, manuals, or extracted files are part of this branch.

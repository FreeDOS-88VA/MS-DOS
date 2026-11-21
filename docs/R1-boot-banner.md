# R1 — Boot banner with release identity

Baseline: `release/msdos-va` at `2f986c1` (J2c merged). R1 source built: `ef7074d0b7fa34f307a0bded4fc47015bf23c2e0`. No upstream refs were changed. Before testing `main`, a scratch clone's `release/msdos-va` was advanced to the R1 source commit to model the post-merge release build. The real branch remains at the baseline; a post-merge build will report the actual commit pinned in its lock, not the example hash below.

## Design

The permanent PC-88VA COMMAND shell (`/P`) prints the banner from its discardable [initialization code](../v4.0/src/CMD/COMMAND/INIT.ASM), after IO.SYS has installed the 80×25 console and its labels, and before `AUTOEXEC.BAT`. A DOS write to stdout uses the existing CON Shift-JIS renderer; the source encodes `日本語` as `93 FA 96 7B 8C EA` in hex. Neither IO.SYS nor the resident shell takes on banner data, and ordinary child COMMAND shells do not sign on. The PC-88VA path replaces any stock COMMAND sign-on. On the baseline distribution the visible single version line actually came from `VER` in `AUTOEXEC.BAT`; the [builder patch](R1/build-release.patch) removes that invocation, not the `VER` command. `CLS` still clears the main area (including the banner) and leaves the label row intact; it does not reprint the banner.

The tracked [VAREL.INC](../v4.0/src/CMD/COMMAND/VAREL.INC) defaults to `Release unknown (unknown, unknown)`. The patch for `experiments/msdos4-va` substitutes an ASCII MASM `DB` line only in the builder's source export, before CRLF conversion and before both the bootstrap and NMAKE COMMAND assemblies. The lock's `msdos.commit` is the full pinned object ID; the banner uses its first eight lowercase hex digits. `msdos.track` explicitly selects `main` or a canonical lowercase milestone such as `r1` or `j2c`; a lock declaring `msdos.branch: "release/msdos-va"` defaults to `main`. No track is inferred from a filename, branch spelling for milestones, or commit subject. `msdos.release_date` optionally supplies a calendar date as an eight-character `YYYYMMDD` string; otherwise the builder converts the pinned commit's **committer date** to UTC+9. The generated values and date source go into `msdos_release` in `build-record.json`. The main run used the commit date (`20261121`); the `r1` run explicitly used `20261122` to exercise the override.

Main screenshot text:

```text
日本語MS-DOS version 4.00 Release 20261121 (main, ef7074d0)
for NEC PC-88VA Series Personal Computer
Ported by Nakata Maho
A:\>
```

## Gate results

vaeg PR #82, `Rel.20261121 (m153, 6367e5d3)`, executable SHA-256 `a3ab65a03eac9fd2abccca3d51b8e464266a4b6141b9d5132b5b667495655906`. The [runner](R1/check-va.py) cold-booted the four distributions on each model and verified the [results](R1/va-checks.txt).

| Gate | VA | VA2 |
|---|---|---|
| Main, JST date and 8-digit commit | PASS · [screen](R1/va-main.png) | PASS · [screen](R1/va2-main.png) |
| Explicit `r1` track and date | PASS · [screen](R1/va-milestone.png) | PASS · [screen](R1/va2-milestone.png) |
| Unknown fallback | PASS · [screen](R1/va-unknown.png) | PASS · [screen](R1/va2-unknown.png) |
| One sign-on, full-width kanji, row-4 prompt, labels, `CLS`, `VER` | PASS | PASS |
| CHKDSK conventional free memory, baseline → main | 529,040 → 529,040 B (0 B) | 529,040 → 529,040 B (0 B) |
| Boot time, baseline → main | 378 → 384 guest frames (+6) | 370 → 375 guest frames (+5) |

`r1` reached the prompt at frame 383 on VA and 375 on VA2; unknown at 384 and 375. Both variants also reported 529,040 B free on each model. CHKDSK total was 655,360 B in every run. The boot-time metric is guest frames from a cold start, with no input until after the first prompt, not host elapsed time. The runner checked each DOS console output byte at `OUTCHR` through `A:\>`, ruling out an intervening second DOS banner. It captured at the next `CISTAT` hit and at idle; using the *first* `CISTAT` unconditionally was insufficient because R1 can hit it during the sign-on. The TVRAM check verified all six kanji half-cells and the 80×24 main split. The bottom row matched the baseline pixels; held Shift changed the labels and release restored them without changing the text. `CLS` left only the normal prompt, and interactive `VER` still printed `MS-DOS Version 4.00`.

**Non-PC88VA byte comparison: PASS.** Two clean builds with PC88VA undefined produced an identical disk and identical generated MS-DOS outputs (not just `COMMAND.COM`). On PC-88VA only `COMMAND.COM` (+128 B) and `AUTOEXEC.BAT` (−5 B) changed; IO.SYS, the boot sector, and all other shipped files were unchanged. A clean main repeat from the applied patch under another host timezone matched the full build record and image. See [build evidence](R1/build.txt).

**NOT RUN:** physical VA/VA2, 2D media, custom `CONFIG.SYS`/`AUTOEXEC.BAT`, an IBM-compatible boot, and frame-by-frame video (the test vaeg binary lacks recording support). The boot output check above used DOS console bytes and paused screenshots, not video.

## Reproduce

Use a scratch directory `$S` **outside this repository**. Export `experiments/msdos4-va` from FreeDOS-88VA/freedos `7f467a2187a9e15c0c1bb84f179f214fe925153f` to `$S/experiments/msdos4-va`. Point `$S/components/msdos` at a scratch clone containing both pins and `$S/components/emu2` at a Git checkout containing `9d8698d06e67359bc8b230c2d19d5b1503e60819`. Make the following copies under `$S/experiments/` and set each `msdos.commit` in its own `lock.json`:

| Experiment directory | Output directory in `$S` | Pin | Builder and disk template |
|---|---|---|---|
| `base` | `base` | `2f986c1` | Stock |
| `msdos4-va` | `main` | `ef7074d0` | Full patch; leave `msdos.track` and `msdos.release_date` absent |
| `milestone` | `milestone` | `ef7074d0` | Full patch; set `msdos.track` to `r1`, `msdos.release_date` to `20261122` (both JSON strings) |
| `unknown` | `unknown` | `ef7074d0` | Stock `build.py`; apply only the `disk/AUTOEXEC.BAT` hunk. The unpatched disk template would still run `VER` even though the shell prints the fallback. |
| `ibm-base` / `ibm-after` | `ibm-base` / `ibm-after` | `2f986c1` / `ef7074d0` | Stock, except set `DEFINES = ()` and remove `'-DPC88VA'` from the bootstrap MASM invocation in both copies. |

Use the full IDs from [build.txt](R1/build.txt). Apply the patch with `git apply /path/to/docs/R1/build-release.patch` in `$S` before copying the patched variant, leaving the stock copies untouched. Run `python3 -B "$S/experiments/$EXPERIMENT/build.py" --output "$S/$OUTPUT"` for each. Compare both non-PC88VA images with `cmp`, and the corresponding `tree/`, `bootstrap-command/` and `va/` contents with `diff -qr` (only the R1 source inputs should differ).

With Pillow and the vaeg QA tools available:

```sh
PYTHONPATH="$VAEG_SOURCE/tools/qa" python3 -B docs/R1/check-va.py \
  "$VAEG" "$VA_ROMS" "$S"
```

Do not stage the scratch distributions, ROMs, raw screen dumps or register captures.

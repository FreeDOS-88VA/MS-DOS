# J4 — Japanese build-time messages

## M1: pipeline and plan

The [inventory](J4/groups.tsv) lists the 57 group headers in USA-MS.MSG (1,060 declared records; not a count of visible strings). IDs are scoped by group, and many entries are blank, structural or shared. COMMAND splits its skeleton into resident, initialization and transient classes; its `:use` directives import or alias COMMON, PARSE and EXTEND records. The utilities have their own skeletons. `TOOLS.INI` runs BUILDIDX on the CRLF `.MSG`, then BUILDMSG with the country basename and `.SKL` to produce `.CTL` and class includes for MASM. DOS and SYSINIT use the separate NOSRVBLD `.SKL` → `.CL1` rule. The external builder bootstraps COMMAND directly with BUILDIDX/BUILDMSG before running NMAKE and checks that the two COMMAND builds match.

Keep a UTF-8 translation overlay beside USA-MS.MSG, materialize a Shift-JIS JPN-MS.MSG in the scratch export, and select the same catalog in both bootstrap and NMAKE. Preserve IDs, substitutions, controls, layout-only strings, and message metadata. Treat lengths as **bytes**, not Unicode characters: check one-byte message sizes, substitution expansion into fixed buffers, and column widths in DIR, CHKDSK and MEM. Preserve CR/LF, NUL and `$` terminators at their existing call sites. Prefer ordinary JIS characters supported by the VA ROM (see [J2a](J2a-sjis-output.md) and [J2b](J2b-escape-sequences.md)). [J1](J1-dbcs-kernel.md) already sets country 081 and code page 932, which is independent of the message catalog. Leave DATE's format strings and fixed three-byte weekday slots alone; translate the surrounding prompt without changing the parser or country tables.

Keep the single-byte response records and syntax ASCII (A/R/I/F and Y/N); display 中止(A), 再試行(R), 無視(I), 失敗(F). Keep option eligibility from INT 24h. Use ドライブ for drive, ディスク for disk and 空き for free space. Translate Microsoft text independently. NEC prompt terminology/accepted keys were not run in M1; see the M3 comparison below.

Out-of-catalog sources include direct DBs in the SYSINIT/BIOS skeleton and VAIO, FC's own sources, and the VA command ASM files (FORMAT, SYS, DISKCOPY, KEY, JFP, SPEED). Preserve data/protocol strings, instruction tables, numeric patch sites, key names, and command grammar. Boot sector diagnostics need separate space and output-path checks.

| Milestone | Files | Gate |
|---|---|---|
| M1 | This plan, group inventory | Plan and counts |
| M2 | Catalog/generator, scratch builder patch, evidence | VA and VA2: boot, DIR alignment, missing command, empty-B critical error with A/R/F, DATE/TIME, COPY error, CHKDSK and resident-size comparison |
| M3 | Utility catalog and hard-coded display text, builder patch, evidence | Each shipped utility on vaeg, EDLIN Y/N, English rebuild/boot |

## M2 results

The scratch builder uses `docs/D4/build-hdd-boot.patch` and `docs/J4/build-messages.patch`. Pin the MS-DOS lock to the source being tested. `--messages ja` selects the overlay; the ordinary build still selects English. The overlay preserves message grammar and regenerates the byte offsets before shipping its CRLF file to DOS tools. The initial J4 scratch builds stopped at VAFORMAT because the base builder lacked the D4-generated VAHDBOOT.INC; resumed the VA stage with D4 applied after confirming the NMAKE/bootstrap COMMAND comparison. Both catalogs produced images.

| Gate (vaeg m153) | VA | VA2 |
|---|---|---|
| Japanese image boots; DIR /W numeric columns, missing command, parse error, COPY missing source, DATE/TIME prompts, VOL/VER, CHKDSK | Observed | Observed |
| Empty B:, Japanese prompt, A returns to shell, R retries | Observed | Observed |
| F on empty B: | Accepted; another INT 24h prompt follows, as in English | Same as VA |
| DEL prompt and insert-disk prompt | NOT RUN | NOT RUN |

[Decoded screens](J4/core-output.txt). DATE retained the `yy-mm-dd` format. VER retains the product name and version. Normal resident COMMAND `DATARESEND`: `1636h` → `167Eh` (+72 bytes unrounded, +80 bytes in paragraphs); `/MSG` boundary `extmsgend`: `1A1Eh` → `1A63h` (+69 unrounded). English VA CHKDSK showed 524,112 bytes free; Japanese VA showed 524,032. This is not a measurement of `/MSG` boot or an isolation of all IO/kernel memory changes.

**English control:** On both models, `DIR B:` with B: empty, then `R`, `F`, `A`, and `ECHO AFTER-A`, produced the same sequence with either catalog. After `F` had been accepted, DIR printed its volume/directory headings and raised a new critical error on the next disk access. `A` then returned to the shell. This is existing DOS behavior on the port, not a J4 regression. See [paired captures](J4/fail-output.txt).

## M3: utilities and VA commands

Use Japanese (`--messages ja`) for the 日本語MS-DOS distribution recipe. This patch keeps `--messages en` as its default; the FreeDOS-88VA builder (PR #20) makes `ja` the default by maintainer decision (2026-11-23) and records the choice in `build-record.json`. The [builder patch](J4/build-messages.patch) now includes the VA DISKCOPY and SPEED build steps from D1 and A1, so do not apply their standalone patches as well. Apply the D4 HDD-boot patch first, then J4, to a scratch copy of the builder. Update the lock to the J4 source revision. For example, from that copy:

```sh
python3 -B experiments/msdos4-va/build.py --messages ja --output "$SCRATCH/ja"
python3 -B experiments/msdos4-va/build.py --messages en --output "$SCRATCH/en"
```

The [`JPN-MS.tsv`](../v4.0/src/MESSAGES/JPN-MS.tsv) overlay adds the remaining utility messages. FIND and SORT keep their command-name prefixes; they and NLSFUNC/SHARE get Japanese diagnostics from the shared classes. The [`JPN-ASM.tsv`](../v4.0/src/MESSAGES/JPN-ASM.tsv) overlay targets quoted `DB` fields in FC, SHARE, VAIO and the six VA commands. Its generator runs only on the Japanese export; it checks for a unique matching field before writing. Microsoft parsing syntax and the VADCOPY diagnostic-file format are unchanged. TREE uses the existing four single-byte ASCII alternate glyphs, and MEM uses ASCII rules with the original byte widths and heading column starts. This avoids interpreting OEM graphics bytes as Japanese characters.

Glossary additions: 初期化 (format), コピー元 / コピー先 (source / destination), 復元 (restore), ボリュームラベル (volume label), 書き込み禁止 (write protected), 読み取り専用 (read-only). Switches, filenames, key names and response letters stay ASCII.

Run the [capture harness](J4/run-va.py) with the vaeg `tools/qa` directory on `PYTHONPATH`, and point it at the m153 binary, private ROM directory, built image and fresh scratch output directory. `--suite utilities` runs each utility in a separate boot of a disposable copy, on VA and VA2. `--suite boot` and `--suite fail` run the English boot and empty-B control respectively (the latter also works on the Japanese image).

| Gate | VA | VA2 |
|---|---|---|
| 25 shipped Microsoft utilities and six VA commands: Japanese diagnostic, prompt, or report | 31/31 observed | 31/31 observed |
| EDLIN `Q`: `N` stays in EDLIN, `Y` returns to COMMAND | Observed | Observed |
| MEM debug headings and rules; TREE with two actual directories | Observed | Observed |
| Default English build boots to the shell; empty-B control agrees with M2 | Observed | Observed |

[Utility captures](J4/utilities-output.txt). Both full builds completed and passed the builder's bootstrap-versus-NMAKE COMMAND comparison. In the default English build, the boot sector and 36 of the 37 files shared with M2 English were byte-identical. COMMAND also matched after excluding the generated release banner. DISKCOPY.COM and SPEED.COM were the two added files. These are message smoke tests, not end-to-end utility tests. **NOT RUN:** real hardware, 2D media, SASI boot/error paths, destructive FORMAT/DISKCOPY actions, and all untranslated or unexercised error branches. The early boot sectors and packaged English README are outside the overlay.

### NEC style reference

Booted the scratch copy of NEC 3.3D system disk 1 in NP2kai SDL2 at `5939e0c6`, exited INSTDOS/MENU and checked VER, missing command, COPY with a missing input, DATE and TIME. The [screen](J4/nec-messages.png) shows that ordinary diagnostics and prompts are Japanese, with command names, filenames and numbers still in ASCII. In a separate [empty-B run](J4/nec-critical.png), NEC offered A/R/I, with Japanese option labels and visible ASCII letters. Lowercase `f` immediately reprompted without retrying, `r` retried the read, `a` returned to the shell, and `i` continued to the volume lookup before another error. J4 keeps DOS 4.0's different option eligibility and Fail support; it does not copy NEC's wording. The extracted NEC boot disk was removed after testing.

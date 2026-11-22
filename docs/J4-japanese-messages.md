# J4 — Japanese build-time messages

## M1: pipeline and plan

The [inventory](J4/groups.tsv) lists the 57 group headers in USA-MS.MSG (1,060 declared records; not a count of visible strings). IDs are scoped by group, and many entries are blank, structural or shared. COMMAND splits its skeleton into resident, initialization and transient classes; its `:use` directives import or alias COMMON, PARSE and EXTEND records. The utilities have their own skeletons. `TOOLS.INI` runs BUILDIDX on the CRLF `.MSG`, then BUILDMSG with the country basename and `.SKL` to produce `.CTL` and class includes for MASM. DOS and SYSINIT use the separate NOSRVBLD `.SKL` → `.CL1` rule. The external builder bootstraps COMMAND directly with BUILDIDX/BUILDMSG before running NMAKE and checks that the two COMMAND builds match.

Keep a UTF-8 translation overlay beside USA-MS.MSG, materialize a Shift-JIS JPN-MS.MSG in the scratch export, and select the same catalog in both bootstrap and NMAKE. Preserve IDs, substitutions, controls, layout-only strings, and message metadata. Treat lengths as **bytes**, not Unicode characters: check one-byte message sizes, substitution expansion into fixed buffers, and column widths in DIR, CHKDSK and MEM. Preserve CR/LF, NUL and `$` terminators at their existing call sites. Prefer ordinary JIS characters supported by the VA ROM (see [J2a](J2a-sjis-output.md) and [J2b](J2b-escape-sequences.md)). [J1](J1-dbcs-kernel.md) already sets country 081 and code page 932, which is independent of the message catalog. Leave DATE's format strings and fixed three-byte weekday slots alone; translate the surrounding prompt without changing the parser or country tables.

Keep the single-byte response records and syntax ASCII (A/R/I/F and Y/N); display 中止(A), 再試行(R), 無視(I), 失敗(F). Keep option eligibility from INT 24h. Use ドライブ for drive, ディスク for disk and 空き for free space. Translate Microsoft text independently. NEC prompt terminology/accepted keys in NP2kai: **NOT RUN**.

Out-of-catalog sources include direct DBs in the SYSINIT/BIOS skeleton and VAIO, FC's own sources, and the VA command ASM files (FORMAT, SYS, DISKCOPY, KEY, JFP, SPEED). Preserve data/protocol strings, instruction tables, numeric patch sites, key names, and command grammar. Boot sector diagnostics need separate space and output-path checks.

| Milestone | Files | Gate |
|---|---|---|
| M1 | This plan, group inventory | Plan and counts |
| M2 | Catalog/generator, scratch builder patch, evidence | VA and VA2: boot, DIR alignment, missing command, empty-B critical error with A/R/F, DATE/TIME, COPY error, CHKDSK and resident-size comparison |
| M3 | Utility catalog and hard-coded display text, builder patch, evidence | Each shipped utility on vaeg, EDLIN Y/N, English rebuild/boot |

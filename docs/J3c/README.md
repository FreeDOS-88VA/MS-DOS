# J3c comparison gate

## M1 — Shared VA/VA2 runner

Gate: run every scenario under `JFP ROM` and `JFP FEP` at VA 640 KiB,
VA2 256 KiB and VA2 640 KiB. Every run must reach the vaeg debug script's
`exit` (not its frame limit), with a capture event and a TVRAM file for
every planned shot. This is a capture gate, not a claim that the modes
behave identically.

The six scenarios cover prompt conversion/candidate cycle, phrase motion,
composition editing and Return, hidden labels, COPY CON, and EDLIN. At a
fixed model/RAM setting, the only script difference is the selector line.
Each run starts with a fresh writable copy of the same 2HD image, a fresh
RAM configuration, and no backup RAM. Shots wait for VAIO's `CISTAT`
entry after the scheduled frame; they are not latency measurements.

### Results

| Configuration | ROM cases to `exit` / TVRAM shots | FEP cases to `exit` / TVRAM shots |
|---|---:|---:|
| VA 640 KiB | 6/6 · 44 | 6/6 · 44 |
| VA2 256 KiB | 6/6 · 44 | 6/6 · 44 |
| VA2 640 KiB | 6/6 · 44 | 6/6 · 44 |
| Total | 18/18 · 132 | 18/18 · 132 |

[Per-run counts](m1-results.txt). All 18 rendered ROM/FEP script pairs
(six per configuration) differed only in the `JFP` selector. Decoding the
`enabled` capture with the
J3b.2 checker showed the intended activation message in all 36 cases.
The `prompt` case showed `日本語` on the system row after the first HENKAN
and printed `日本語` after confirmation and submission in all six
model/RAM/mode combinations. [ROM on VA](va-rom-first.png) ·
[FEP on VA](va-fep-first.png).

**NOT RUN for M1:** the full conversion corpus and segmentation
comparison, latency and memory measurements, key and file-byte gates,
NECAIK comparison, interrupt/dictionary/fault tests, and `JFP ON` or
plain-mode regression gates (M2–M6).

### Reproduce

Use the [J3b.3 candidate gate image](../J3b.3-bios-backend.md#reproduce),
including `LABELCHK.COM`. The tested copy was from the existing J3b.3
scratch build, not rebuilt for M1. Its distribution was built from
`2fb12a6`; `git diff --stat 2fb12a6..47faac9` shows only documentation and
QA changes. Distribution SHA-256 is in the
[J3b.3 build notes](../J3b.3/build.txt); the tested **packed** gate image
SHA-256 is `7913fbb9e9d283a1ae761d1fceb2c29a700f6aa65c7bc08a7bc5f6a95866365e`.
`IO.SYS` and `JFP.COM` read from that image match the J3b.3 candidate
hashes. The root directory contains no `.DIC` or `.DAT` files.

Use m153 vaeg (`6367e5d3`, binary SHA-256
`a3ab65a03eac9fd2abccca3d51b8e464266a4b6141b9d5132b5b667495655906`)
and local VA/VA2 ROMs. From the repository root:

```sh
python3 -B docs/J3c/run.py "$VAEG" "$ROMS" "$GATE_D88" "$S/m1" \
  --cistat 1000:09AA --screens --jobs 4
```

`1000:09AA` is **DOS VAIO code** from the tested MASM listing. `$S` is
scratch outside the repository and the output directory must not exist.
By default only TVRAM is captured; `--screens` also writes a BMP per shot.
`--case` can be repeated to select a subset. The output hierarchy is
`MODEL-RAM/MODE/CASE`; the event log, debugger script, emulator log,
captures and writable disk all stay in scratch.

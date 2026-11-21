# J3b.3 — Kanji conversion in the project FEP

Run **`JFP FEP`** at the DOS prompt. Type `ECHO `, tap **ZENKAKU**, type
`nihongo`, tap **HENKAN**, then **KETTEI** and **Return**. The first
candidate is `日本語` on the tested VA and VA2. HENKAN and Shift+HENKAN
select next and previous candidates for the focused phrase. Left/Right
move focus; Shift+Left/Right shorten/extend the focused phrase. Brackets
show focus on the system row but are never sent to DOS. **Return while
composing confirms only; a second Return submits the DOS line.** Boot is
still plain, and `JFP OFF` returns to plain input. `JFP ROM` still selects
the separate ROM front end. [VA prompt capture](J3b.3/va-nihongo.png):
candidate, KETTEI, then Return.

## Design

- **Foreground-only setup.** `VAJFP.ASM` reserves the system row through
  VAIO, then runs `ResJFP → KbFlsh → SetJFP`, selecting and verifying
  `8F80h` (master off). VAIO accepts the FEP commit only from that
  reservation and checks `GetJFP` before selecting project input.
  Invoking `JFP FEP` again in project mode does not reset the BIOS.
  `ResJFP` can open DOS files; it never runs in a device request. On the
  stock disks, activation succeeded with the expected two missing-file
  results from the COM's open hook. **`JFP FEP` itself opts into the
  built-in dictionary**; there is no separate `ROM` option for FEP.
  The guarded configuration rejects activation unless both default
  file opens report file/path not found. Successful external file opens,
  other open errors, and unexpected counts do not enter the FEP. This
  limits the qualified backend to the configuration actually tested;
  it does not change `JFP ON` or `JFP ROM` file policy.
- **Headless conversion.** `VAFEP.INC` passes an immutable, NUL-terminated
  Shift-JIS reading and a separate output buffer to `Sug1st`, `SugNxt`,
  `SugPrv`, `Kpfrwd`, `Kpback`, `LongB`, and `ShortB` (PC-88VA Technical
  Manual `618JFP`, §6.18.3). Only full-width hiragana and the prolonged
  sound mark enter the BIOS. Unsupported input stays editable and can
  still be confirmed as ordinary project input. The BIOS owns ordering,
  duplicates, and endpoints; the project does not enumerate or cache a
  candidate list. In particular, previous at the first candidate need
  not wrap. Both models resized and moved between phrases for the typed
  `nihongowohanasu` fixture, with different shortened candidate lengths.
  The VA and VA2 returned focus start in AH
  and length in AL on this fixture, the reverse of the local manual
  transcription. VAIO checks the span against the validated candidate;
  if it is out of range, it displays the candidate without focus marks.
- **Buffer and delivery bounds.** The existing 30-cell reader owns a
  61-byte ASCIIZ input. The separate 128-byte BIOS buffer accommodates
  60 double-byte cells plus terminator (the larger documented JFP
  input-mode limit), with a sentinel after the buffer. This BIOS ABI
  takes no capacity argument: the sentinel and validation detect some
  bad results, not arbitrary firmware overwrites. Only a nonempty,
  terminated, structurally valid full-width Shift-JIS string up to 72
  bytes is copied out; otherwise the frontend reverts to the reading.
  The 30-cell conversion gate is a limit fixture, not an exhaustive
  proof of the BIOS write bound. Project code owns the display, focus
  marks, peeks, lead/trail delivery and flush. No backend work runs in a
  keyboard IRQ.
- **No learning.** `618JFP` §6.18.3 documents `Decide` with learning and
  no non-learning variant. KETTEI or Return closes the session and
  publishes the validated project-owned snapshot. Closing uses `QuitJFP` (the
  documented cancel/reset operation in §6.18.2). ESC, editing away
  from a candidate and a pending candidate flush can also call
  `QuitJFP`; they publish nothing. A subsequent conversion always
  restarts with `Sug1st`. No `Decide` or dictionary write path is called
  or deferred. J3b.4 remains separate.

## Return: NEC reference

Reused the J0.3b NP2kai SDL2 IA-32 build (revision in [build.txt](J3b.3/build.txt)).
Booted the supplied NEC PC-98 MS-DOS 3.30D system from a scratch copy of
system disk 1 with `DEVICE=NECAIK1.DRV` and `DEVICE=NECAIK2.DRV` in
`CONFIG.SYS`, `NECAI.SYS` and `NECAIKEY.EXE` from disk 2, and
`NECAI33B.DAT` from disk 3. The startup screen
reported AI kana-kanji conversion available and `NECAI.SYS` as the
current-drive dictionary. At `A>`, typed `echo `, enabled NECAIK
(Ctrl+host right Alt), and typed `nihongo`. The first Return changed
pending hiragana to ordinary confirmed text without running ECHO; the
second printed it. Repeated with Space to convert to `日本語` before
Return, with the same two-Return behavior. [NEC captures](J3b.3/nec-return.png),
from top: converted text pending, first Return, second Return. Project FEP
follows this for both unconverted and converted input; idle Return still
goes through the existing DOS path. NEC media and extracted files were
kept in scratch and removed after the check.

## Safety evidence

`FEPMON.COM` installs temporary INT 21h, 83h and 8Dh hooks from the
foreground, then invokes DOS buffered console input (`AH=0Ah`). The
8Dh hook scopes the 21h and 83h counters to entry/return of the actual
firmware call; ordinary INT 83h system-row painting is outside that
scope. A nested INT 21h would be counted and rejected rather than
allowed to reenter DOS. A positive control first exercises both counters
with a harmless DOS version request and a text cursor query. `FEPBYTE.COM`
repeats the test while exercising status/peek, byte reads and flush
(`0Bh`, `06h`, `07h`, `0Ch`). Both COMs require the master-off mode before
and after the measured sequence.

| Context, per model/RAM | Quit | First | Next | Prev | Right | Left | Long | Short | nested INT 21h | nested INT 83h |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Buffered CON read + confirmation | 1 | 1 | 31 | 30 | 1 | 1 | 1 | 1 | **0** | **0** |
| Status/byte API + confirmation/flush/edit | 4 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | **0** | **0** |

These are 75 measured calls per configuration, 225 in the matrix. The
confirmation call is `QuitJFP`, not `Decide`. These hooks count interrupt
entries on specific tested ROMs with the built-in dictionary, not all
internal firmware activity, and do not establish a general nested-DOS
contract for other firmware revisions or external files.

## Gate and memory

See [checker output](J3b.3/observations.txt) and [build pins](J3b.3/build.txt).
Counts are grouped checks, not individual taps or boots. The vaeg m153
matrix used 33 fresh 2HD boots per configuration, explicit installed RAM
and no backup-RAM file. The candidate was rebuilt; the base is the
unchanged J3b.2 gate build.

| Brief step | VA 640 KiB | VA2 256 KiB | VA2 640 KiB | Checked |
|---|---:|---:|---:|---|
| 1. Plain and ROM | 31/31 | 31/31 | 31/31 | J0.3 1/5/9, J0.4 1–5, KEY, J2a TYPE and CHKDSK (24); J3a 2/6 (7) |
| 2. `nihongo` | 1/1 | 1/1 | 1/1 | `日本語` first, next/previous, KETTEI + Return |
| 3. Other readings/miss | 4/4 | 4/4 | 4/4 | `kanji`→`漢字`, `henkan`→`変換`, `toukyou`→`東京` first; `pepepupu` unchanged |
| 4. Cycle bound | 1/1 | 1/1 | 1/1 | 30 forward + 30 backward with no premature DOS bytes |
| 5. Nested interrupts | 2/2 | 2/2 | 2/2 | Blocking read and status/byte/flush; table above |
| 6. File-producing apps | 2/2 | 2/2 | 2/2 | COPY CON and EDLIN, `TYPE`, exact FAT file bytes |
| 7. Labels and CON API | 5/5 | 5/5 | 5/5 | Held Shift and hidden layout; repeated peek, byte order, pending and cached-trail flush |
| 8. Return | 2/2 | 2/2 | 2/2 | Reading and candidate confirm before DOS line submission |
| **Total** | **48/48** | **48/48** | **48/48** | Plus 4/4 supplemental per configuration: phrase motion/resize, 30 cells, mode exclusion/memory, editing a candidate |

`J.TXT`: `93 FA 96 7B 8C EA 0D 0A`; `E.TXT`: same plus `1A`.

VAIO resident `RESEND` grew by **538 bytes**, or **544 bytes** of usable
DOS memory after paragraph rounding. CHKDSK free went from **525,952 to
525,408 bytes** at 640 KiB (either model), and **132,736 to 132,192 bytes**
at 256 KiB (VA2). Selecting FEP had no additional measured cost. `IO.SYS`
grew from 24,186 to 24,730 bytes (24 → 25 sectors); `JFP.COM` is 1,162
bytes, nonresident. Firmware work areas are not reclaimed.

## Latency

The harness brackets the VAIO `INT 8Dh` instruction and its return PC
with vaeg's debugger. This reports elapsed **guest frame boundaries**, not
host time or input-to-screen latency; a sub-frame call can measure 0.
The checker also records the emulator clock delta. The longest measured
first conversion used 30 repeated `あ` cells; synchronous conversion can
hold the CON request that long. These are not hardware timings or latency
bounds for other readings.

| Backend sample | VA 640 KiB | VA2 256 KiB | VA2 640 KiB |
|---|---:|---:|---:|
| First (`nihongo`) | 4 | 4 | 4 |
| First (four short hits) | 4–12 | 3–4 | 3–4 |
| First (`pepepupu`, miss) | 5 | 8 | 8 |
| First (30 cells) | 49 | 102 | 102 |
| Next / previous (`nihongo`) | 0 / 0 | 2 / 2 | 2 / 2 |
| Quit on KETTEI (`nihongo`) | 0 | 0 | 0 |

**NOT RUN:** physical hardware, VA at 256 KiB, VA3, 2D, other ROM
revisions, fault-injected default-file load failures or present external
files, learning/`Decide`, exhaustive input/buffer/candidate corpus,
IRQ/NMI/DMA stress, and timings for phrase motion/resize or full
keystroke-to-display latency. The NEC comparison was at the prompt, not
in third-party NEC applications.

## Reproduce

Use the scratch builder from [J3b.2](J3b.2-project-kana-input.md#reproduce)
with the pins in [build.txt](J3b.3/build.txt). Keep every disk, capture,
listing, and tool output outside this repository. Prepare the candidate
regression disk as in [J2a](J2a-sjis-output.md#reproduce), then append the
two gate COMs with `pack_va` from `docs/J1/media.py`:

```sh
for name in FEPMON FEPBYTE; do
  nasm -I docs/J3b.3/ -f bin "docs/J3b.3/$name.NAS" -o "$S/$name.COM"
done
PYTHONPATH="$BUILDER_EXP:docs/J1" python3 -B - "$REG_D88" "$S" <<'PY'
import sys
from pathlib import Path
from media import pack_va
base, scratch = map(Path, sys.argv[1:])
pack_va(base, scratch / 'gate.d88', [(n, (scratch / n).read_bytes())
                                   for n in ('FEPMON.COM', 'FEPBYTE.COM')])
PY
export PYTHONPATH="$BUILDER_EXP:$VAEG_SOURCE/tools/qa"
export BASE_CISTAT=1000:099B AFTER_CISTAT=1000:09AA
export FEP_INT=1000:1691 FEP_RET=1000:1693
python3 -B docs/J3b.3/run.py "$VAEG" "$ROMS" "$BASE_D88" "$AFTER_D88" \
  "$S/gate.d88" "$S/results"
python3 -B docs/J3b.3/check.py "$S/results"
```

The four PC values are in **project VAIO** from the two MASM listings,
not addresses inside firmware. The captured keyboard and text evidence
is from the typed fixtures. No disk or raw emulator dumps are published.

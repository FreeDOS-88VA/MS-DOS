# M3 — Speed and conventional memory

**Gate:** CHKDSK total/free bytes before and after each selector on all
three configurations, and frame counts for both first and next candidate
for three short readings and one phrase. Use the M1 image, as in M2.

[`measure.py`](measure.py) uses vaeg's completed-frame screenshot
scheduler to sample rendered guest frames relative to the debugger's
HENKAN make event. It takes the first frame whose system-row pixels
match the settled screenshot, requires a nonmatch on the immediately
preceding frame, and checks that subsequent samples stay matched.
Separate settled TVRAM shots verify the text against M2, with distinct
first and next strings. There is no VAIO breakpoint inside a sampled
window. Short readings sample offsets 0–42 after the first make; the
phrase samples 0–27 and 80–94 because a pilot showed the much later
VA update. Next-candidate offsets are 0–18. Both modes and all models
use the same windows, within m153's 64-shot limit per run.
The numbers include input delivery, conversion, text update and the
emulator's rendering of the result. They are not host wall time,
physical display latency, or a bound for other readings.

CHKDSK runs once before selection and once after in each cold run; both
plain measurements per model/RAM have to agree. VAIO is already resident
in plain mode. These are DOS-available conventional-memory bytes, not
ROM work-area sizes.

```sh
export PYTHONPATH="$VAEG_SOURCE/tools/qa:$BUILDER_EXP"
python3 -B docs/J3c/measure.py "$VAEG" "$ROMS" "$GATE_D88" "$S/m3" \
  --cistat 1000:09AA
python3 -B docs/J3c/measure.py report "$S/m3" "$S/m2"
```

The counted matrix was **30/30 cases to `exit`**, with 114 settled
TVRAM shots and 1,536 scheduled frame screenshots. There was no measured
activation cost. Latency cells are **first / next**, in guest frames.

| Configuration | Plain free (bytes) | ROM free (bytes) | FEP free (bytes) |
|---|---:|---:|---:|
| va-640 | 525,408 | 525,408 | 525,408 |
| va2-256 | 132,192 | 132,192 | 132,192 |
| va2-640 | 525,408 | 525,408 | 525,408 |

| Reading | va-640 ROM | va-640 FEP | va2-256 ROM | va2-256 FEP | va2-640 ROM | va2-640 FEP |
|---|---|---|---|---|---|---|
| kanji | 13 / 2 | 13 / 2 | 6 / 4 | 6 / 4 | 6 / 4 | 6 / 4 |
| henkan | 10 / 2 | 11 / 2 | 5 / 4 | 5 / 4 | 5 / 4 | 5 / 4 |
| gakkou | 4 / 2 | 4 / 2 | 7 / 5 | 7 / 5 | 7 / 5 | 7 / 5 |
| kyouhaiitenkidesu | 88 / 2 | 89 / 2 | 22 / 4 | 22 / 4 | 22 / 4 | 22 / 4 |

## Resident VAIO bytes

The matching J3b.3 build lists `RESEND=20D3h` (**8,403 bytes** from the
start of VAIO's CODE segment), resident under plain, ROM and FEP alike.
The historical MASM `RESEND` differences measure the build-time cost of
adding each path and its shared integration, not separately reclaimable
blocks in this binary:

| Addition | VAIO resident bytes before paragraph rounding | Method |
|---|---:|---|
| ROM front end | 795 | J3a: `15BFh − 12A4h` ([build notes](../J3a/build.txt)) |
| Project FEP with kanji backend | 2,836 | J3b.2 + J3b.3: `20D3h − 15BFh` ([kana](../J3b.2/build.txt), [backend](../J3b.3/build.txt)) |

`JFP.COM` itself is nonresident. The table excludes BIOS work areas;
no independent firmware-work-area size was measured.

# M4 — Keys and application interaction

**Gate:** same keys in both selectors on VA 640 KiB and VA2 256/640 KiB;
report observations from TVRAM, screenshots and FAT file bytes. Check
NECAIK independently on NP2kai with NEC PC-98 MS-DOS 3.30D.

[`keys.py`](keys.py) combines the six M1 cases with nine supplemental
cases per selector/configuration. `CONKEY K` reports the exact bytes
produced by each idle tap, sampled after each tap, in both widths. For
keys during composition, the script cancels the previous reading and
retypes `ai`; a before shot checks that every tested key starts at the
same `echo` + pending `あい` state. `CONBYTE` checks repeated 0Bh peeks
and ordered 06h/07h reads, a Shift-triggered 0Ch flush with a candidate
pending, and another 0Ch after the lead byte with a cached trail. Its
final `A` tests that flush retained kana width. COPY CON and EDLIN are
checked both at the prompt and by reading the saved file from the D88.

`pass` means the named interaction matched the tested expectation;
`differs` denotes a visible front-end change without unintended leakage
into COMMAND, not a claim that the behavior is better or worse.

```sh
export PYTHONPATH="$VAEG_SOURCE/tools/qa:$BUILDER_EXP:docs/J1"
nasm -f bin docs/J3c/CONBYTE.NAS -o "$S/CONBYTE.COM"
python3 -B docs/J3c/pack.py "$GATE_D88" "$S/key-gate.d88" "$S/CONBYTE.COM"
python3 -B docs/J3c/keys.py "$VAEG" "$ROMS" "$S/key-gate.d88" "$S/m4" \
  --cistat 1000:09AA --screens
python3 -B docs/J3c/keys.py report "$S/m4"
```

A reload-based pilot was not counted: this build could save the pending
state but returned `M142_STATE_RESTORE` on load. The counted pending-key
plans use ordinary key events and verify the before state instead.

## NEC PC-98 reference

Fresh cold boots per case on NP2kai SDL2 IA-32 `5939e0c6`, using the supplied
3.30D disks. `nec.py media` preserved disk 1's boot sectors and system
files, enabled `NECAIK1.DRV` and `NECAIK2.DRV`, and copied `NECAI.SYS`,
`NECAIKEY.EXE` and `NECAI33B.DAT` from the supplied media. The NEC startup
screen reported that AI conversion was available and `NECAI.SYS` was the
current-drive dictionary. The prepared media were removed after use.

| Action | NEC NECAIK on NP2kai | VA/VA2 comparison |
|---|---|---|
| Width/IME toggle | Ctrl+XFER (host Ctrl+right Alt) enabled composition; repeating it after ESC returned to ASCII and `echo x` ran. | Both VA paths use ZENKAKU with no Ctrl chord when idle. |
| Convert | Space on pending `nihongo` displayed highlighted `日本語`. | Both VA paths use HENKAN and display the candidate on the system row, not inline. |
| Bare XFER / NFER | Tested separately from pending `nihongo`: bare XFER and NFER (host right and left Alt) changed yellow pending `にほんご` to ordinary confirmed `にほんご` without submission. Space after NFER did not start conversion of that confirmed text. | Closest to KETTEI on VA, not HENKAN. Do not equate the PC-98 key names with VA conversion. |
| BS / ESC | `あい` → `あ` with BS; ESC removed the pending reading and preserved `echo`. | Same editing outcomes as both VA paths on the fixture. |
| Return | First Return confirmed only, second printed the result, both for unconverted `にほんご` and converted `日本語`. | Both VA modes do this for the converted fixture; see M6 for the unconverted case. |

[NEC screenshots](nec-keys.png). To reproduce, run
`python3 -B docs/J3c/nec.py media "$NEC_ZIP" "$S/nec.d88"`, boot a fresh
scratch copy in NP2kai as in [J0.3b](../J0.3b-editing-keys.md#reproduce),
and wait for the `A>` prompt before sending keys. In that X11 display,
run `python3 -B docs/J3c/nec.py keys "$WINDOW" "$CASE" "$S/$CASE"`.
The five cases are `toggle`, `conversion`, `nfer`, `return`, and
`return-reading`. Use a fresh boot and writable copy for each. Early
attempts sending keys during boot are not counted.

## VA / VA2 observations

**90/90 counted cases reached `exit`**, including the six reused M1
cases per selector/configuration. The original Shift+F-key run is used
only through Shift+F9; an independent run starts Shift+F10 from a
verified clean reading. The table has 765 pass and 21 differs cells,
with no fail cells under these expectations. Idle `CONKEY K` matched
all 43 taps in both widths on all six paths. The differences are in
pending-state behavior, including ROM's ZENKAKU mode change and FEP's
explicit F7 katakana action.

| Key or interaction | va-640 ROM | va-640 FEP | va2-256 ROM | va2-256 FEP | va2-640 ROM | va2-640 FEP |
|---|---|---|---|---|---|---|
| ZENKAKU idle | pass: ASCII `a` → `あ` → ASCII `x` | pass: ASCII `a` → `あ` → ASCII `x` | pass: ASCII `a` → `あ` → ASCII `x` | pass: ASCII `a` → `あ` → ASCII `x` | pass: ASCII `a` → `あ` → ASCII `x` | pass: ASCII `a` → `あ` → ASCII `x` |
| ZENKAKU pending | differs: row `半英` | pass: reading unchanged | differs: row `? C1   ? CU   ? CA   ? S1   ? SU      ?VOID  ?NWL   ?INS   ?REP   ? ^Z  半英` | pass: reading unchanged | differs: row `? C1   ? CU   ? CA   ? S1   ? SU      ?VOID  ?NWL   ?INS   ?REP   ? ^Z  半英` | pass: reading unchanged |
| BS pending | pass: `あ` | pass: `[H] あ` | pass: `あ` | pass: `[H] あ` | pass: `あ` | pass: `[H] あ` |
| ESC pending | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains |
| Ctrl-C pending | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains | pass: cancelled; DOS `echo` remains |
| Ctrl-C idle | pass: `^C`, new prompt | pass: `^C`, new prompt | pass: `^C`, new prompt | pass: `^C`, new prompt | pass: `^C`, new prompt | pass: `^C`, new prompt |
| Return pending candidate | pass: confirm → submit | pass: confirm → submit | pass: confirm → submit | pass: confirm → submit | pass: confirm → submit | pass: confirm → submit |
| F1 template after converted line | pass: `A:\>e` | pass: `A:\>e` | pass: `A:\>e` | pass: `A:\>e` | pass: `A:\>e` | pass: `A:\>e` |
| F3 template after converted line | pass: `A:\>echo 日本語` | pass: `A:\>echo 日本語` | pass: `A:\>echo 日本語` | pass: `A:\>echo 日本語` | pass: `A:\>echo 日本語` | pass: `A:\>echo 日本語` |
| KEY-defined F1 | pass: `abc` + `NEW--` label | pass: `abc` + `NEW--` label | pass: `abc` + `NEW--` label | pass: `abc` + `NEW--` label | pass: `abc` + `NEW--` label | pass: `abc` + `NEW--` label |
| F1 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| F2 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| F3 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| F4 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| F5 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| F6 during reading | differs: `1:哀`; `A:\>echo` | pass: unchanged | differs: `1:哀`; `A:\>echo` | pass: unchanged | differs: `1:哀`; `A:\>echo` | pass: unchanged |
| F7 during reading | pass: unchanged | differs: `[K] アイ`; `A:\>echo` | pass: unchanged | differs: `[K] アイ`; `A:\>echo` | pass: unchanged | differs: `[K] アイ`; `A:\>echo` |
| F8 during reading | differs: `ｱｲ`; `A:\>echo` | pass: unchanged | differs: `ｱｲ`; `A:\>echo` | pass: unchanged | differs: `ｱｲ`; `A:\>echo` | pass: unchanged |
| F9 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| F10 during reading | differs: `アイアイアイ`; `A:\>echo` | pass: unchanged | differs: `アイアイアイ`; `A:\>echo` | pass: unchanged | differs: `アイアイアイ`; `A:\>echo` | pass: unchanged |
| SHIFT+F1 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+F2 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+F3 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+F4 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+F5 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+F6 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+F7 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+F8 during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+F9 during reading | differs: reading text unchanged; labels changed | pass: unchanged | differs: reading text unchanged; labels changed | pass: unchanged | differs: reading text unchanged; labels changed | pass: unchanged |
| SHIFT+F10 during reading | differs: reading text unchanged; labels changed | pass: unchanged | differs: reading text unchanged; labels changed | pass: unchanged | differs: reading text unchanged; labels changed | pass: unchanged |
| LEFT during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| RIGHT during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| UP during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| DOWN during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+LEFT during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| SHIFT+RIGHT during reading | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged | pass: unchanged |
| F1 idle (narrow) | pass: 1b 53 | pass: 1b 53 | pass: 1b 53 | pass: 1b 53 | pass: 1b 53 | pass: 1b 53 |
| F2 idle (narrow) | pass: 1b 54 | pass: 1b 54 | pass: 1b 54 | pass: 1b 54 | pass: 1b 54 | pass: 1b 54 |
| F3 idle (narrow) | pass: 1b 55 | pass: 1b 55 | pass: 1b 55 | pass: 1b 55 | pass: 1b 55 | pass: 1b 55 |
| F4 idle (narrow) | pass: 1b 56 | pass: 1b 56 | pass: 1b 56 | pass: 1b 56 | pass: 1b 56 | pass: 1b 56 |
| F5 idle (narrow) | pass: 1b 57 | pass: 1b 57 | pass: 1b 57 | pass: 1b 57 | pass: 1b 57 | pass: 1b 57 |
| F6 idle (narrow) | pass: 1b 45 | pass: 1b 45 | pass: 1b 45 | pass: 1b 45 | pass: 1b 45 | pass: 1b 45 |
| F7 idle (narrow) | pass: 1b 4a | pass: 1b 4a | pass: 1b 4a | pass: 1b 4a | pass: 1b 4a | pass: 1b 4a |
| F8 idle (narrow) | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 |
| F9 idle (narrow) | pass: 1b 51 | pass: 1b 51 | pass: 1b 51 | pass: 1b 51 | pass: 1b 51 | pass: 1b 51 |
| F10 idle (narrow) | pass: 1b 5a | pass: 1b 5a | pass: 1b 5a | pass: 1b 5a | pass: 1b 5a | pass: 1b 5a |
| SHIFT+F1 idle (narrow) | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d |
| SHIFT+F2 idle (narrow) | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d |
| SHIFT+F3 idle (narrow) | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 |
| SHIFT+F4 idle (narrow) | pass: 64 65 6c 20 | pass: 64 65 6c 20 | pass: 64 65 6c 20 | pass: 64 65 6c 20 | pass: 64 65 6c 20 | pass: 64 65 6c 20 |
| SHIFT+F5 idle (narrow) | pass: 72 65 6e 20 | pass: 72 65 6e 20 | pass: 72 65 6e 20 | pass: 72 65 6e 20 | pass: 72 65 6e 20 | pass: 72 65 6e 20 |
| SHIFT+F6 idle (narrow) | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d |
| SHIFT+F7 idle (narrow) | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d |
| SHIFT+F8 idle (narrow) | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 |
| SHIFT+F9 idle (narrow) | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d |
| SHIFT+F10 idle (narrow) | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d |
| ROLLUP idle (narrow) | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes |
| ROLLDOWN idle (narrow) | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes |
| INS idle (narrow) | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 |
| DEL idle (narrow) | pass: 1b 44 | pass: 1b 44 | pass: 1b 44 | pass: 1b 44 | pass: 1b 44 | pass: 1b 44 |
| UP idle (narrow) | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b |
| LEFT idle (narrow) | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 |
| RIGHT idle (narrow) | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c |
| DOWN idle (narrow) | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a |
| HOME idle (narrow) | pass: 1a | pass: 1a | pass: 1a | pass: 1a | pass: 1a | pass: 1a |
| HELP idle (narrow) | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes |
| SHIFT+UP idle (narrow) | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b |
| SHIFT+LEFT idle (narrow) | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 |
| SHIFT+RIGHT idle (narrow) | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c |
| SHIFT+DOWN idle (narrow) | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a |
| SHIFT+HOME idle (narrow) | pass: 1e | pass: 1e | pass: 1e | pass: 1e | pass: 1e | pass: 1e |
| CTRL+UP idle (narrow) | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b |
| CTRL+LEFT idle (narrow) | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 |
| CTRL+RIGHT idle (narrow) | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c |
| CTRL+DOWN idle (narrow) | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a |
| CTRL+HOME idle (narrow) | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes |
| BS idle (narrow) | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 |
| ESC idle (narrow) | pass: 1b | pass: 1b | pass: 1b | pass: 1b | pass: 1b | pass: 1b |
| CTRL+C idle (narrow) | pass: 03 | pass: 03 | pass: 03 | pass: 03 | pass: 03 | pass: 03 |
| F1 idle (wide) | pass: 1b 53 | pass: 1b 53 | pass: 1b 53 | pass: 1b 53 | pass: 1b 53 | pass: 1b 53 |
| F2 idle (wide) | pass: 1b 54 | pass: 1b 54 | pass: 1b 54 | pass: 1b 54 | pass: 1b 54 | pass: 1b 54 |
| F3 idle (wide) | pass: 1b 55 | pass: 1b 55 | pass: 1b 55 | pass: 1b 55 | pass: 1b 55 | pass: 1b 55 |
| F4 idle (wide) | pass: 1b 56 | pass: 1b 56 | pass: 1b 56 | pass: 1b 56 | pass: 1b 56 | pass: 1b 56 |
| F5 idle (wide) | pass: 1b 57 | pass: 1b 57 | pass: 1b 57 | pass: 1b 57 | pass: 1b 57 | pass: 1b 57 |
| F6 idle (wide) | pass: 1b 45 | pass: 1b 45 | pass: 1b 45 | pass: 1b 45 | pass: 1b 45 | pass: 1b 45 |
| F7 idle (wide) | pass: 1b 4a | pass: 1b 4a | pass: 1b 4a | pass: 1b 4a | pass: 1b 4a | pass: 1b 4a |
| F8 idle (wide) | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 |
| F9 idle (wide) | pass: 1b 51 | pass: 1b 51 | pass: 1b 51 | pass: 1b 51 | pass: 1b 51 | pass: 1b 51 |
| F10 idle (wide) | pass: 1b 5a | pass: 1b 5a | pass: 1b 5a | pass: 1b 5a | pass: 1b 5a | pass: 1b 5a |
| SHIFT+F1 idle (wide) | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d | pass: 64 69 72 20 61 3a 0d |
| SHIFT+F2 idle (wide) | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d | pass: 64 69 72 20 62 3a 0d |
| SHIFT+F3 idle (wide) | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 | pass: 63 6f 70 79 20 |
| SHIFT+F4 idle (wide) | pass: 64 65 6c 20 | pass: 64 65 6c 20 | pass: 64 65 6c 20 | pass: 64 65 6c 20 | pass: 64 65 6c 20 | pass: 64 65 6c 20 |
| SHIFT+F5 idle (wide) | pass: 72 65 6e 20 | pass: 72 65 6e 20 | pass: 72 65 6e 20 | pass: 72 65 6e 20 | pass: 72 65 6e 20 | pass: 72 65 6e 20 |
| SHIFT+F6 idle (wide) | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d | pass: 63 68 6b 64 73 6b 20 61 3a 0d |
| SHIFT+F7 idle (wide) | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d | pass: 63 68 6b 64 73 6b 20 62 3a 0d |
| SHIFT+F8 idle (wide) | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 | pass: 74 79 70 65 20 |
| SHIFT+F9 idle (wide) | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d | pass: 64 61 74 65 0d |
| SHIFT+F10 idle (wide) | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d | pass: 74 69 6d 65 0d |
| ROLLUP idle (wide) | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes |
| ROLLDOWN idle (wide) | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes |
| INS idle (wide) | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 | pass: 1b 50 |
| DEL idle (wide) | pass: 1b 44 | pass: 1b 44 | pass: 1b 44 | pass: 1b 44 | pass: 1b 44 | pass: 1b 44 |
| UP idle (wide) | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b |
| LEFT idle (wide) | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 |
| RIGHT idle (wide) | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c |
| DOWN idle (wide) | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a |
| HOME idle (wide) | pass: 1a | pass: 1a | pass: 1a | pass: 1a | pass: 1a | pass: 1a |
| HELP idle (wide) | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes |
| SHIFT+UP idle (wide) | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b |
| SHIFT+LEFT idle (wide) | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 |
| SHIFT+RIGHT idle (wide) | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c |
| SHIFT+DOWN idle (wide) | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a |
| SHIFT+HOME idle (wide) | pass: 1e | pass: 1e | pass: 1e | pass: 1e | pass: 1e | pass: 1e |
| CTRL+UP idle (wide) | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b | pass: 0b |
| CTRL+LEFT idle (wide) | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 |
| CTRL+RIGHT idle (wide) | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c | pass: 0c |
| CTRL+DOWN idle (wide) | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a | pass: 0a |
| CTRL+HOME idle (wide) | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes | pass: no bytes |
| BS idle (wide) | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 | pass: 08 |
| ESC idle (wide) | pass: 1b | pass: 1b | pass: 1b | pass: 1b | pass: 1b | pass: 1b |
| CTRL+C idle (wide) | pass: 03 | pass: 03 | pass: 03 | pass: 03 | pass: 03 | pass: 03 |
| Shift+Left/Right, Right/Left in candidate | pass: [日本語を]離す → [日本]五を離す → [日本語を]離す → 日本語を[離す] → [日本語を]離す | pass: [日本語を]離す → [日本]五を離す → [日本語を]離す → 日本語を[離す] → [日本語を]離す | pass: [日本語を]離す → [日本語]をはなす → [日本語を]離す → 日本語を[離す] → [日本語を]離す | pass: [日本語を]離す → [日本語]をはなす → [日本語を]離す → 日本語を[離す] → [日本語を]離す | pass: [日本語を]離す → [日本語]をはなす → [日本語を]離す → 日本語を[離す] → [日本語を]離す | pass: [日本語を]離す → [日本語]をはなす → [日本語を]離す → 日本語を[離す] → [日本語を]離す |
| Labels before/during/after | pass: row restored | pass: row restored | pass: row restored | pass: row restored | pass: row restored | pass: row restored |
| Hold Shift during candidate | pass: row unchanged | pass: row unchanged | pass: row unchanged | pass: row unchanged | pass: row unchanged | pass: row unchanged |
| ESC[>1h hidden labels / OFF | pass: 25 → 24 → 24 → 25 rows | pass: 25 → 24 → 24 → 25 rows | pass: 25 → 24 → 24 → 25 rows | pass: 25 → 24 → 24 → 25 rows | pass: 25 → 24 → 24 → 25 rows | pass: 25 → 24 → 24 → 25 rows |
| INT 21h 06h/07h/0Bh | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached |
| INT 21h 0Ch candidate flush | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached |
| INT 21h 0Ch cached trail flush | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached | pass: probe checkpoint reached |
| COPY | pass: `93 fa 96 7b 8c ea 0d 0a` | pass: `93 fa 96 7b 8c ea 0d 0a` | pass: `93 fa 96 7b 8c ea 0d 0a` | pass: `93 fa 96 7b 8c ea 0d 0a` | pass: `93 fa 96 7b 8c ea 0d 0a` | pass: `93 fa 96 7b 8c ea 0d 0a` |
| EDLIN | pass: `93 fa 96 7b 8c ea 0d 0a 1a` | pass: `93 fa 96 7b 8c ea 0d 0a 1a` | pass: `93 fa 96 7b 8c ea 0d 0a 1a` | pass: `93 fa 96 7b 8c ea 0d 0a 1a` | pass: `93 fa 96 7b 8c ea 0d 0a 1a` | pass: `93 fa 96 7b 8c ea 0d 0a 1a` |

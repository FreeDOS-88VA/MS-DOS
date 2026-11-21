# B1 — COPY CON stalls

**Cause on vaeg VA2:** vaeg can deliver a hardware IRQ after VAIO changes `SS` but before it changes `SP`. The IRQ pushes its frame through an inconsistent stack pointer, overwriting DOS data or damaging the return path. The stalled guest is no longer in the normal CON input loop. Several runs executed stray RAM, with no single stable stall address. The fix masks maskable interrupts during both VAIO stack switches and restores the previous flags afterward.

## Baseline evidence

Reproduced on `release/msdos-va` (`f8cd7e8`) with no body input. The [debugger script](B1/baseline-copy.debug) hit `CISTAT` (`1000:03FC`) at the boot prompt and missed it from frame 1400 through the frame limit at 2200. [Snapshots and stack dump](B1/baseline-debug.txt) show one stall at changing `1FF0:Fxxx` RAM addresses, with `SS:SP=108B:0981` and IF clear. That `SS` is the MSDOS.SYS segment; the sampled `CS:IP` is not mapped IO.SYS, MSDOS.SYS, COMMAND or ROM code. Another run stayed at `1000:118D` with IF set; despite `CS=1000h`, that linear address is in MSDOS.SYS disk-stack storage, not in VAIO's resident code. IF clear in the first snapshot series is a consequence of lost control flow, not evidence of a wait inside a ROM service.

The [IRQ breakpoint](B1/irq.gdb) caught vaeg accepting interrupts at `1000:0322`, immediately after VAIO's `MOV SS,AX` and before its `MOV SP,OFFSET STKTOP`. In one example the expected original stack was `108B:08F2`, but delivery used `1000:08F2`, followed by a corrupted `BCON` and no further `CISTAT` hit. A separate [write watchpoint](B1/watch.gdb) on `BCON` caught `upd9002_core_interrupt` itself changing `1000:0003` to `1022:0003` by pushing IP `0322h` to linear `108E4h`, the segment word of `108B:0032`. In a separate scratch-emulator rolling trace, `DSKSTATCHK` loaded a corrupted `BCON` (`DS=0322h`); `DEVIOCALL2` then called a bogus strategy address, `0322:CB00`, in zero-filled RAM. See the [mapped trace excerpt](B1/baseline-debug.txt). These are separate captures, not one stitched timeline.

### Suspects checked

- **Floppy and media check:** the corrupting write happened in hardware interrupt delivery at VAIO's stack switch, not in the drive-door query or mode selection in `pc88va/VAFDXFER.INC`. The subsequent console strategy call went through corrupted DOS data. No failing INT 80h service was identified.
- **ROM, stack, DF:** the v2.0 fixes `367767f`, `ec5e426` and `35b1837` have counterparts in v4.0: `CLD` at request entry and exit, a 512-byte private stack, and `HWINIT` retaining the boot stack. The trace shows an IRQ with IF set and a mismatched `SS:SP`, not a nested DOS request or a ROM service stuck with IF clear. No change to ROM call policy or the boot stack was needed.
- **COMMAND's CON read:** `COPY.ASM` checks the device via IOCTL, rejects explicit binary input for a device, and `COPYLP` issues a DOS read for the space left in the buffer (not a COMMAND-level one-byte loop). The traced loss of control is in the kernel's device dispatch after the pointer overwrite, not a COPY binary/cooked or EOF decision. The baseline fails even without body input.

## Fix

`857b4fc` changes only [`v4.0/pc88va/VAIO.ASM`](../v4.0/pc88va/VAIO.ASM). `PUSHF`/`CLI` saves and disables IF before either switch. The saved flags are carried through `SAVEFL` and restored by `POPF` after both registers are valid. The existing private stack, `CLD` handling and request status are unchanged; the mask does not cover ROM services or the console wait. This works around the observed vaeg behavior without changing vaeg. No hardware behavior is inferred from it.

The [fixed debug run](B1/fixed-switch.debug) entered `COPY CON` with no body input. At the entry and exit breakpoints between `MOV SS` and `MOV SP`, IF was 0; at the corresponding breakpoints after `POPF`, IF was 1. It hit the new `CISTAT` address `1000:0418` at frame 1400. See [events](B1/fixed-switch-events.tsv) and [registers](B1/fixed-switch-registers.txt).

## VA2 gate

All counted runs used stock vaeg `Rel.20261118 (m150, 5c2307ac)`, model VA2, a local VA2 ROM set, and a fresh writable 2HD D88 per cold boot. See [per-run results](B1/gate-runs.tsv).

| Check | Passes | Evidence |
|---|---:|---|
| `COPY CON T.TXT`, two lines, Ctrl-Z then Enter; `TYPE T.TXT` | **10/10** | [Screen](B1/two-lines.png); after emulator exit, `readfile.py` yielded exactly `FIRST LINE\r\nSECOND LINE\r\n` (25 bytes) every time. |
| `COPY CON T.TXT`, no body, Ctrl-Z then Enter | **10/10** | [Screen](B1/no-body.png); every run returned to the prompt with `0 File(s) copied`, and `readfile.py` reported `not found: T.TXT`. |
| `COPY A:README.TXT A:U.TXT` | **2/2** | [Screen](B1/disk-copy.png); `readfile.py` extracted both files, and the 1,525-byte contents matched in both runs. |
| `DIR` after the disk copy | **2/2** | [Screen](B1/dir.png); `U.TXT` was listed at 1,525 bytes and the prompt returned in both runs. |
| Boot prompt (dedicated capture in regression run) | **1/1** | [Frame 550](B1/regression-boot.png); the COPY runs also reached COMMAND. |
| J0.2 `regression.input`, byte-for-byte unchanged | **1/1** | [Typing](B1/regression-typed.png), [Backspace](B1/regression-backspace.png), [Enter](B1/regression-entered.png); four original PNGs and final TVRAM were byte-identical to a fresh baseline run with the same script. |

An initial launcher invocation lacked the final screenshot frame for the COPY scripts: the headless input scheduler reported completion but the emulator did not exit on script completion alone. Those timeout runs are excluded from the gate; the table is the fresh rerun with frame-bounded captures and clean emulator exits. Physical hardware, other emulator models/releases, other media formats, and the full J0.2 NEC-editor/ESC-Z gate were **NOT RUN**.

## Reproduction commands

Reused the baseline build from J0.2 (D88 SHA-256 `7c4b141d31e0034120e0b07eb93b9bea808e1c54822e48e15189cc7398385db0`). Built the fix with the same FreeDOS-88VA/freedos `66a6acef778ae6aebe5a9d85219788972d6eef9d` distribution builder and emu2 `9d8698d06e67359bc8b230c2d19d5b1503e60819`: copy `experiments/msdos4-va/` to scratch, link `components/msdos` and `components/emu2` to the local Git repos, change `msdos.commit` in the copied `lock.json`, then run `python3 experiments/msdos4-va/build.py --output "$OUT"` with a nonexistent absolute output path. The fixed image SHA-256 was `692fed3db2e872ef8681cd918370075adddfc9336f1a49a2eaf2718227c86ecf`. `cmp` also found MSDOS.SYS and COMMAND.COM byte-identical to baseline. For symbol mapping, MASM `-l VAIO.ASM,B1VAIO.OBJ,B1VAIO.LST;` under the builder's emu2 produced the VAIO listing; the two listing builds' `.OBJ`s matched their respective distribution `.OBJ`s.

In a scratch directory with a fresh image at `disk.d88`, set `REPO`, `VAEG` (absolute executable path), and `ROMS` (local ROM directory). For baseline snapshots:

```sh
mkdir capture
gdb -q -batch -x "$REPO/docs/B1/snapshot.gdb" --args "$VAEG" \
  --model va2 --no-cfg --no-bkupmem --nowait --roms "$ROMS" \
  --fdd1 disk.d88 --debug-script "$REPO/docs/B1/baseline-copy.debug" \
  --debug-output-dir capture
```

Substitute `irq.gdb` or `watch.gdb` for the two breakpoint variants. Entry timing varies; rerun cold boots. These GDB scripts use the Linux x86-64 binary's symbols and argument registers. Do not publish unfiltered ROM traces.

For a gate run, use a fresh fixed image and run e.g.:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy "$VAEG" \
  --model va2 --no-cfg --no-bkupmem --nowait --roms "$ROMS" \
  --fdd1 disk.d88 --headless-input-script "$REPO/docs/B1/two-lines.input" \
  --screenshot 3500:end.png --screen-tvram-dump end.tvram
python3 "$BUILDER/readfile.py" disk.d88 T.TXT > extracted.txt
```

Use frame 2200 for `no-body.input`, 2400 for `disk-copy-dir.input` (also frame 1100 for the COPY screen), and 550/730/1000/1450 for `j02-regression.input`. `BUILDER` is the directory containing `build.py` and `readfile.py`. Validate the extracted bytes only after the emulator exits and flushes its disk cache.

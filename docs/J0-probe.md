# J0.1 — PC-88VA ROM function-key probe

**Result:** The ROM can draw NEC-style labels, and a text-BIOS split kept them visible while DOS output scrolled. The ROM's main keyboard path was unusable on the tested DOS boot: it returned data before a key was sent, then attempted to call a null JFP callback. No product code changed.

## Build and run

Tested with `release/msdos-va` at `f8cd7e812a2408f8dd1fe4f83687920017affb1e`, FreeDOS-88VA/freedos at `66a6acef778ae6aebe5a9d85219788972d6eef9d`, and vaeg `Rel.20261118 (m150, 5c2307ac)` in `--model va2`. Used a local VA2 ROM set and no saved vaeg config or backup memory. Other models and hardware: **NOT RUN**.

Run the FreeDOS `experiments/msdos4-va/build.py` as in its README, using the lock's emu2 `9d8698d06e67359bc8b230c2d19d5b1503e60819` and the MS-DOS commit above. For the test, the build script and lock were copied to scratch and `components/msdos` and `components/emu2` there pointed at the corresponding local Git repositories. The unmodified builder produced the D88 with SHA-256 `7c4b141d31e0034120e0b07eb93b9bea808e1c54822e48e15189cc7398385db0`.

From the MS-DOS repository root (`OUT` is an absolute path to the completed distribution build):

```sh
REPO=$PWD
PROBE=$(mktemp -d)
cp "$REPO"/v4.0/src/TOOLS/{MASM,LINK,EXE2BIN}.EXE "$PROBE/"
python3 -c 'from pathlib import Path; import sys
Path(sys.argv[2]).write_bytes(Path(sys.argv[1]).read_bytes().replace(b"\n", b"\r\n"))' \
  "$REPO/pc88va/tests/FKPROBE.ASM" "$PROBE/FKPROBE.ASM"
(
  cd "$PROBE"
  export EMU2_DRIVE_D="$PWD" EMU2_DEFAULT_DRIVE=D: 'EMU2_CWD=D:\' EMU2_DOSVER=4.00
  EMU="$OUT/emu2/emu2"
  "$EMU" MASM.EXE 'FKPROBE.ASM,FKPROBE.OBJ,FKPROBE.LST;' &&
  "$EMU" LINK.EXE 'FKPROBE.OBJ,FKPROBE.EXE;' &&
  "$EMU" EXE2BIN.EXE FKPROBE.EXE FKPROBE.COM &&
  test -s fkprobe.com
)
```

MASM 5.10 reported zero warnings and errors; LINK 3.65 reported expected `L4021: no stack segment` for the COM. EXE2BIN produced 1,624 bytes, SHA-256 `db4a2a3f353ddb07197afca387068bb80d7182097afad3617ac8cef95042f7d7` ([build log](J0-probe/probe-build.txt)). To reproduce the bootable test copy, append that COM to the distribution's root using the same builder helpers (`FREEDOS` points at the FreeDOS-88VA/freedos checkout):

```sh
PYTHONPATH="$FREEDOS/experiments/msdos4-va" python3 -B - \
  "$OUT/msdos4-pc88va-2hd.d88" "$PROBE/fkprobe.com" "$PROBE/probe.d88" <<'PY'
import struct, sys
from pathlib import Path
from build import compose, d88
from readfile import raw_image, read_file
base, com, output = map(Path, sys.argv[1:])
image = base.read_bytes()
raw = raw_image(image)
files = []
for off in range(5 * 1024, 11 * 1024, 32):
    entry = raw[off:off + 32]
    if entry[0] == 0:
        break
    if entry[11] == 8:
        label = entry[:11].decode().rstrip()
        date = struct.unpack_from('<H', entry, 24)[0]
        continue
    name = entry[:8].decode().rstrip() + '.' + entry[8:11].decode().rstrip()
    files.append((name, read_file(raw, name), entry[11]))
serial = struct.unpack_from('<I', raw, 39)[0]
name = image[:17].split(b'\0', 1)[0].decode()
assert d88(compose(raw[:1024], files, label, date, serial), name) == image
files.append(('FKPROBE.COM', com.read_bytes(), 0x20))
output.write_bytes(d88(compose(raw[:1024], files, label, date, serial), name))
PY
```

The test D88's SHA-256 was `23c9ed30643af6901d2e9b2729a89ffbe13fe7dad79c2fff9d6b5ae19083048c`. The probe modifies BIOS state and does not restore it; cold boot the test copy for **each** mode. The `S`, `B`, `K` and `F` tests are bounded externally with screenshot frames; do not count on the guest returning. The raw mode `R` exits on `q`.

Run from a scratch directory, for example with `input.txt` containing `FKPROBE X`, `@wait 220`, `CLS` on separate lines:

```sh
vaeg --model va2 --no-cfg --no-bkupmem --nowait --roms "$ROMS" \
  --fdd1 "$PROBE/probe.d88" --headless-input-script input.txt \
  --screenshot 550:boot.png --screenshot 895:scrolled.png \
  --screenshot 1500:after-cls.png --screen-tvram-dump screen.tvram
```

For `P`, `N`, `M`, or `S`, use just `FKPROBE <mode>` (capture at frame 860 for `P/N/M`, 2200 for `S`). For `K` and `R`, follow `FKPROBE <mode>` with `@wait 160`, then `@key f1`, `@key shift-f1`, `@key insert`, `@key delete`, `@key up`, `@key home`, and `@text a`, with `@wait 35` between taps. Capture at frames 840 (pre-tap) and 2200. For `F`, send only F1 and `a` after the same initial wait, with `@wait 70` between them. For `B`, use `FKPROBE B`, `@wait 160`, `@text a` and capture at 840 and 1040. The actual injection frames and small extracts from the TVRAM/register dumps are in [observations.txt](J0-probe/observations.txt). Raw ROMs, state files, dumps and disk images are not included.

## 1. Enable the line, scroll DOS CON, then run CLS

- **Screen-editor path (`S`):** INT 94h `InitScr` (`AX=0004`) and `AlcSysL` (`AX=010A`) plus INT 83h `SftCtl` (`AX=2F0A`) displayed ten labels. `SftCtl` returned CF=0. At frame 2200, DOS had printed row `0001` and part of the next line (`DOS`); this run did not reach scrolling or return to the prompt. See [editor-scroll-stall.png](J0-probe/editor-scroll-stall.png). The cause of this stall was not established.
- **Text-BIOS path (`X`):** INT 83h `CrtCtl` (`AX=2404`), `Allocfb` (`AH=1C`), `Spltscn` (`AH=1D`) and `SftCtl` (`AX=2F0A`) set up an 80×25 display, with a 24-row scrolling main screen and a one-row system screen. The old 80×20 boot mode had no label line ([boot.png](J0-probe/boot.png)). The probe sent 40 numbered lines to DOS stdout (`INT 21h AH=40h`, handle 1, not redirected). This exercises VAIO's `OUTCHR` → INT 83h `Putstr`, not the probe's diagnostic printer. [split-early.png](J0-probe/split-early.png) (frame 757 in a repeat) shows the success codes, first row and labels; [split-scrolled.png](J0-probe/split-scrolled.png) shows the top rows scrolled away, `0028` (40 decimal) and the returned DOS prompt above the labels. The captured bottom row is pixel-identical before and after scrolling.
- **Actual COMMAND `CLS`:** Sent `CLS` at the returned prompt. It printed `[2J[H` instead of clearing; both the remaining DOS rows and the label line stayed visible ([split-cls.png](J0-probe/split-cls.png), same bottom-row pixels). The observed `INT 21h AX=4400h BX=1` stdout device info was `DX=80C3` in mode `M` ([memory.png](J0-probe/memory.png)). In `v4.0/src/CMD/COMMAND/TCMD2A.ASM`, `CLS` masks DX with `009Fh` and requires `0093h` to call INT 83h. `80C3h & 009Fh` is `0083h`, so the source takes the ordinary DOS write path for this device info; `VAIO.ASM` filters out ESC. This accounts for the literal brackets. Whether the **native clear sequence** would preserve the label line when it actually runs is **NOT RUN**; the observed `CLS` did not clear either screen.

## 2. Which bytes appear as the label?

`P` defines F1 as `1B 53 00` (`ESC S`); `N` defines it as `FE 20 43 31 20 20 1B 53 00` (`FEh, ' C1  ', ESC S`). F2 is `XYZ123!` in both runs. INT 82h `DefSft` (`AH=03`) returned CF=0, as did `SftCtl`. `DefSft` takes **ES:DX**, as documented in the BNN technical manual; an initial trial using `ES:DS` as printed in `603KEYB.TXT` returned CF=0 but did not copy the test definition. Repeating with ES:DX gave the following:

| Mode | Visible F1 | Visible F2 | Evidence |
|---|---|---|---|
| `P` | ESC glyph, `S`, then blanks | `XYZ123` | [label-plain.png](J0-probe/label-plain.png) |
| `N` | `C1` with label padding, no `S` | `XYZ123` | [label-nec.png](J0-probe/label-nec.png) |

The TVRAM character bytes confirm that the plain field starts with `1B 53`, and the prefixed field contains `FE 20 43 31 20 20` (FE renders as blank), not `1B 53`. Thus the default label is taken from the beginning of the string; the NEC field form is accepted **for display**. The local `lpproj/fdkernel` `nec98/kernel/conkey60.asm` at `c9ce245` has the same F1 field followed by `ESC S`. Neither skipping the prefix on keyboard input nor shifted-label redraw was established in this test.

## 3. Register results for the requested keys

`K` defines F1 `ESC S`, Shift+F1 `XY`, INS `ESC P`, DEL `ESC D`, Up `0B`, CLR `1A` and HOME `1E` (separate definitions to tell the latter two apart). It enables expansion with `AX=0200h`. It logs each CF=0 `SnsChar` and its paired `GetChar` directly via the text BIOS, and marks CF=1 after a burst. `F` substitutes the prefixed F1 definition. `R` makes no definitions and uses the primitive sense/get pair as an input-delivery control. Each KB call seeds BX with `A55A`.

`K` shows `S AX BX=890A 0000  G AX BX=890A 0000` **before** the first tap. All seven taps were injected, but there was no subsequent line, not even an empty mark. `F` shows the same single line after F1 and `a`. See [keys-before.png](J0-probe/keys-before.png), [keys-after.png](J0-probe/keys-after.png), and [keys-prefixed-after.png](J0-probe/keys-prefixed-after.png). No row from either main-function run can be attributed to a tested key.

In contrast, the same sequence in `R` produced the following in order. These are primitive `AH=0Ah/09h` results, **not** `SnsChar/GetChar` results. See [primitive-keys.png](J0-probe/primitive-keys.png).

| Injected key | Primitive sense AX BX (CF=0) | Primitive get AX BX |
|---|---|---|
| F1 | `6200 A55A` | `6200 A55A` |
| Shift+F1 | `8200 A55A` | `8200 A55A` |
| INS | `3800 A55A` | `3800 A55A` |
| DEL | `3900 A55A` | `3900 A55A` |
| Up | `3A00 A55A` | `3A00 A55A` |
| HOME/CLR | `3E00 A55A` | `3E00 A55A` |
| `a` | `1D61 A55A` | `1D61 A55A` |

Each primitive pair was followed by a sense with CF=1. The `A55A` values are unchanged canaries, not key codes. Per-key/per-byte **main-function** AX/BX and one-byte-per-call expansion could not be measured: the main path entered `0000:0000` before it could service the taps (section 4). A separate CLR-only injection was **NOT RUN**; vaeg's `home` tap supplied `3E00`.

## 4. Is the main path usable, and why did v2.0 bypass the JFP?

- **DOS 4 control (`B`):** A single blocking `GetChar` at the boot prompt, with no screen setup, key definitions, expansion control or preceding `SnsChar`, returned `AX=890A BX=0000` and exited before the script sent `a`. The later `a` echoed at COMMAND's prompt, not inside `GetChar`. See [get-before-a.png](J0-probe/get-before-a.png) and [get-after-a.png](J0-probe/get-after-a.png). No JFP pop-up was seen in these captures or the `K/F` runs. Key loss within an initialized JFP was **NOT RUN**.
- **DOS 4 dispatch (`K`):** Mode `M` found the KB BIOS JFP callback at `00AB:01DE` set to `0000:0000`, although INT 8Dh has a nonzero vector. Inspection identified a far call through that callback in the ROM `SnsChar` path (address kept in private evidence). In a separate vaeg debug run, breakpoints at the far call and then at `0000:0000` hit in the same frame, before any test key (see [observations.txt](J0-probe/observations.txt)). The path is unusable as-is, not merely waiting for a key. JFP initialization or replacement was **NOT RUN**.
- **History:** `4de71f3` used INT 82h `01h/00h`, filtering non-single-byte results. `714a26e` changed `CISTAT` to `0Ah/09h` and checked only AL; its comment explicitly says this bypasses the JFP. `origin/experiment/msdos2-va` then adds distinct DF, private-device-stack and boot-stack fixes (`367767f`, `ec5e426`, `35b1837`); `origin/experiment/msdos4-va` and the release inherit the keyboard change. The FreeDOS `docs/porting/m11-console-input-adr.md` mentions the primitive BIOS pair as a public-demo precedent, not this incident; `m16-console-input-adr.md` chooses a matrix adapter, not the ROM main path. No additional reason for `714a26e` was documented there. `experiments/msdos2-va/README.md` describes the resulting primitive, ASCII-only console.
- **Historical A/B reproduction:** Assembled and linked scratch images of the exact parent `4de71f3` and `714a26e` using their own `v2.0/pc88va/{VAIO,VABOOT}.ASM`, MASM/LINK from the DOS 4 test, and the matching `v2.0/bin` `SYSINIT.OBJ`, `SYSIMES.OBJ`, `MSDOS.SYS`, `COMMAND.COM`. No product sources were edited. The boot source was identical between the commits. Used the builder's 2HD FAT12 geometry and the original contiguous boot: filled its BPB, extent words at offset 62 (first data LBA, total system sectors, IO sectors) and both signatures. The only other file was `AUTOEXEC.BAT` (`ECHO OFF`, `VER`). Both boots received the same script (`@text v`, `@wait 200`, `@enter`, `@wait 200`, `VER`). At frame 1400 the parent still showed just a cursor; `714a26e` reached COMMAND and ran `VER` ([v2-before.png](J0-probe/v2-before.png), [v2-after.png](J0-probe/v2-after.png)). The parent hit the same far call and then `0000:0000` at frame 247; `714a26e` did not hit the dispatch breakpoint in a 1,000-frame debug run armed from reset. This reproduces a boot-blocking failure removed by the bypass in vaeg, without conflating it with the later stack or DF fixes. It does not establish what originally happened on hardware.

## 5. RAM and overlap with the DOS system files

All addresses below are hexadecimal. `FKPROBE M` reads the pointers and compares just its own three F1 bytes, without dumping the firmware contents ([memory.png](J0-probe/memory.png), ROM vector target redacted).

| Area | Evidence and placement |
|---|---|
| KB BIOS | `KyBook` (INT 82h `AH=0E`) returned `0040:06B0`, the same physical `00AB0` as documented `00AB:0000` (`603KEYB.TXT` §6.3.5). F1 at `00AB:0001` matched `ESC S NUL`. The documented string slots begin at `00AB:0001` (20 × 16 bytes) and `00AB:0141` (11 × 6 bytes): physical `00AB1` through `00C32`. |
| Text BIOS / system line | `Getbook` (INT 83h `AH=2B`) returned `0040:0070` (physical `00470`). `617SCRNE.TXT` §6.17.2 puts the main and system framebuffers at TVRAM offsets `0000` and `0FA0`. In both tested setups the label bytes were found at `0FA0` plus their column offsets. The character cells of the displayed system row occupy TVRAM offsets `0FA0–103F` (80 words); InitScr reserves two rows. This is separate banked text VRAM, exposed at `A0000h` with the TVRAM bank selected in vaeg (`memoryva/memoryva.c`), not DOS conventional RAM. |
| JFP | `618JFP.TXT` §6.18.6 places bookkeeping at `0440:0000` (physical `04400`). Its conversion input/output, status and user-dictionary environment pointers were all `0000:0000` in `M`; the control byte was `00`. The display area is shared with the system line per §6.17.2. Backing RAM for active conversion or dictionaries could not be measured: no active JFP configuration was exercised (**NOT RUN**). |

`pc88va/VABOOT.ASM` and `v4.0/pc88va/VAIO.ASM` use `BIOSSEG=1000h`. The built IO.SYS is 18,458 bytes, loaded at `10000`, and rounds to 19 sectors (`4C00` bytes). MSDOS.SYS is 37,376 bytes, loaded at `14C00` and rounded to `9400` bytes; the boot-loaded extent ends at `1E000` (exclusive). `HWINIT` sets the kernel's final segment to `BIOSSEG + ceil(RESEND/16)`; `RESEND=08A4` in the MASM listing, so `SYSINIT1.ASM` moves the kernel to `108B:0000`, still above `10000`. No overlap with the identified conventional-RAM areas or with the TVRAM system line. This does not prove non-overlap for an initialized JFP's unmeasured backing buffers.

## Recommendation

Use a key table in VAIO over the primitive queue. It delivered every requested scan in this test and does not call the missing JFP callback. Keep display independent of input: the ROM's text-BIOS split and label rendering can be evaluated for the label line, but do not switch CON input to `DefSft`/`GetChar`. Fix and retest COMMAND's actual clear path before relying on CLS to preserve labels.

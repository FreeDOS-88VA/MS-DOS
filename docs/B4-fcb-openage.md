# B4 — FCB read/write errors lose the SFT open age and LRU count

## Bug

FCB opens use a separate SFT cache (`FCBS=`). In an FCB SFT the high word
of `sf_position` holds the open age `sf_OpenAge` (`INC/SF.INC`), and
`LRUFCB` uses that age to keep the oldest network or SHARE entries
(`FCBS=n,keep`). `FCBIO` in `DOS/FCBIO2.ASM` puts the byte position into
`sf_position` for `DOS_Read`/`DOS_Write`. It `XCHG`s the high word of the
position with the open age and `PUSH`es the age. The age is restored
(`POP … sf_Position+2`) only on the success path. On failure, `JC FCBDeath`
skips the `POP`. `Enter`/`Leave` rebalance the stack, so nothing crashes,
but the SFT keeps the position's high word in place of its open age.
The age becomes 0 for files under 64 KiB, and stays wrong until the file
is reopened.

The same path also leaves the low word, the LRU count `sf_LRU`, holding the
byte position's low word. Only `SaveFCBInfo` on the success path wrote a
valid LRU back. The review of the first fix found this.

## Fix (`d7e17a4`, `d869339`)

The error path, taken on carry after the I/O call, now:
- reloads the SFT pointer;
- pops the saved age back into the SFT (`d7e17a4`);
- gives the entry a fresh LRU count, as `SaveFCBInfo` does on success
  (`d869339`).

```
	JNC	FCBIOSuccess
	LES	DI,CS:[ThisSFT]
	POP	ES:[DI].sf_OpenAge
	SaveReg <AX,BX,CX>		; AX = error code for FCBDeath
	invoke	FCBPokeLRU
	RestoreReg  <CX,BX,AX>
	JMP	FCBDeath
FCBIOSuccess:
```

`FCBPokeLRU` is a new `entry` label in `SaveFCBInfo` (`DOS/FCBIO.ASM`),
placed at the existing LRU update:
- `sf_LRU = ++FCBLRU`;
- on wrap, `ResetLRU` with `BX = sf_position`.

The label emits no code, so `SaveFCBInfo` and the success path of `FCBIO`
are unchanged apart from the jump sense. The code after the label changes
AX, BX and CX (`ResetLRU` uses CX), so the error path saves them. AX holds
the error code that `FCBDeath` → `FCB_Ret_Err` maps. In the after build,
MSDOS.SYS grows from 38,848 to 38,864 bytes. The MASM diagnostics are the
same as before.

Why the LRU needed a fix: `sf_LRU` is the low word of `sf_position`.
`FCBIO` writes the byte position there, and only `SaveFCBInfo` on the
success path wrote a valid LRU back. After a failed call the entry kept
the position's low word, which is 0 for record 0. With `FCBS=2,0`,
`LRUFCB` (keep 0) goes straight to its LRU scan. That scan does not
prefer free entries, and a free entry's LRU 0 ties with the failed one.
The next FCB open therefore evicted the open, failed FCB even though an
entry was free.

Review:
- **`ThisSFT` is valid on both paths.** `SFTFromFCB` sets `ThisSFT` just
  before the `PUSH`, and its success path is the only way to reach the
  `PUSH`. Both `DOS_Read` and `DOS_Write` take the SFT from `ThisSFT`. The
  FCB open path already relies on `LES DI,ThisSFT` after a failed
  `DOS_Open` (`$FCB_Open`).
- **The INT 24h handler does not move `ThisSFT`.** It may only use
  functions 01h–0Ch and 59h. Those (`CPMIO`) do not set `ThisSFT`.
- **`ES:DI` must be reloaded.** `DOS_Read`/`DOS_Write` do not promise to
  preserve `ES:DI` on failure.
- **The stack is balanced.** The `BUFFERFLAG` block's own
  `PUSHF`/`POPF` pairs are complete before the test.
- **SS is DOSGroup for `FCBPokeLRU`.** It runs inside the INT 21h
  dispatcher, exactly as `SaveFCBInfo` does.
- **The pattern occurs only here.** `sf_position+2`/`sf_OpenAge` is saved
  and restored around a call at this one site (`grep` of `DOS/*.ASM`).
  `SetOpenAge`, `LRUFCB`, `BlastSFT` and `FCBRegen` only assign or read it.
- **The builds contain the fix.** Build records and sign-on stamps:
  `847a33c5` (before), `d7e17a4a` (age only), `d869339e` (age and LRU,
  the final fix).

## Probe

- [`tests/pc88va/FCBAGE.NAS`](../tests/pc88va/FCBAGE.NAS) (NASM, `.COM`)
  finds the FCB SFT cache through the list of lists (`SYSI_FCB`, offset
  1Ah).
- [`tests/pc88va/fcb-age-media.py`](../tests/pc88va/fcb-age-media.py)
  builds the scratch disks from a distribution image with the builder's
  FAT helpers:
  - A: boots with `FCBS=2,0` and has the probe on it.
  - B: has `BAD.DAT`, whose data sector has a D88 sector ID that no read
    asks for, so the FDC reports No Data. vaeg ignores the D88 CRC
    status byte. `DENY.DAT` is read-only. `NEXT.DAT` is a normal file.
- [`B4/run-probe.py`](B4/run-probe.py) boots both disks on VA and VA2,
  runs `FCBAGE > AGE.LOG` and reads `AGE.LOG` back from the image.

Steps:
1. Open BAD. Do a random block read (27h). INT 24h comes up and the
   probe's handler answers Fail. Then check that BAD's open age is
   unchanged and that its LRU count is above its old value and the newest
   among the live entries.
2. Open DENY. The cache still has a free entry, so DENY must take it and
   BAD must stay in the cache.
3. Do a random block write (28h) on DENY, which is refused. Check DENY's
   age and LRU the same way.
4. Read DENY, open and read NEXT, then open BAD again. That open must
   evict DENY, the LRU entry, into DENY's own slot and keep NEXT.
5. Read the evicted DENY FCB again; DOS must regenerate its SFT.
6. Close all three FCBs and check that the cache has no live entry. Open,
   read and close NEXT once more.

Exit code 0 = PASS. Otherwise 2 means the open age was lost and 4 means
the LRU was stale or a free entry was not used; the two can add up to 6.
Exit code 1 means a step failed.

## Evidence (vaeg m153, Japanese 2HD distribution image)

Three builds were tested:
- **Before** = `847a33c5`, the B4 gate commit, without the fix.
- **Age only** = `d7e17a4a`.
- **After** = `d869339e`, the final fix.

VA and VA2 printed identical logs for each build:
[before](B4/age-before-va.txt), [age only](B4/age-d7e17a4-va.txt),
[after](B4/age-after-va.txt). Each cell below holds for both VA and VA2.

| Check | Before | Age only | After |
|---|---|---|---|
| Failed FCB read (BAD): AL, CX, ext. error, INT 24h | 01, 0, 53h, 1× (08 sector not found) | same | same |
| BAD open age before → after the failed read | 0001 → **0000** | 0001 → 0001 | 0001 → 0001 |
| BAD LRU before → after the failed read | 0001 → **0000** | 0001 → **0000** | 0001 → 0002 (newest) |
| Next FCB open (DENY) with one entry free | **evicts BAD** | **evicts BAD** | uses the free entry; BAD kept |
| Refused FCB write (DENY, read-only): AL, CX, ext. error, INT 24h | 01, 0, 05h (access denied), none | same | same |
| DENY open age before → after the refused write | 0002 → **0000** | 0002 → 0002 | 0002 → 0002 |
| DENY LRU before → after the refused write | 0002 → **0000** | 0002 → **0000** | 0003 → 0004 (newest) |
| Cache full: third open evicts the LRU entry (DENY), keeps NEXT | PASS | PASS | PASS |
| Evicted FCB reads again (regenerated SFT, age FFFF by `BlastSFT`) | PASS | PASS | PASS |
| Closes, empty cache, reopen/read/close | PASS | PASS | PASS |
| Probe exit code | 6 (age + LRU) | 4 (LRU) | 0 |
| `DIR B:` after the probe | 3 files, 1,296,384 free | same | same |
| B2 smoke (`docs/B2/run-smoke.py`), two boots | PASS | PASS | PASS |
| CHKDSK disk free (boot 1 / boot 2) | 719,872 / 761,856 | same | same |
| CHKDSK memory free (FASTOPEN loaded) | 513,664 | 513,664 | 513,648 |
| COPY / EDLIN `1D`, `L`, `E` / TYPE / CHKDSK spot check | PASS | PASS | PASS |
| CHKDSK memory free (no FASTOPEN) | 524,064 | 524,064 | 524,048 |

- **B2 smoke:** apart from the build stamp, file times and the 16-byte
  memory difference, the screens are identical across the three builds.
  The final build was run twice. In both runs, some screens of the final
  build were captured while a command was still being typed or was still
  printing. Its later screens show those commands complete, and the end
  states match (36 files, 761,856 bytes free). Both `FC /B` comparisons say "no
  differences encountered", and CHKDSK reports no errors.
- **Spot check:** the screens match, apart from the stamp, the times, the
  16-byte memory difference, and one screen of the before run captured
  while COPY was still printing.
- **Resident size:** before and with the age-only fix, 655,360 − 513,664 =
  141,696 bytes are in use after boot with FASTOPEN. With the final fix
  it is 141,712 bytes: 16 bytes (one paragraph) more, from the larger
  MSDOS.SYS (38,848 → 38,864 bytes).

## NOT RUN

- FCB I/O through a network redirector (no redirector on VA).
- A refused write on a write-protected disk. The refusal tested is the
  read-only-file check, which needs no INT 24h.
- SHARE loaded with `FCBS=n,keep` (keep > 0), the only setting where
  `LRUFCB` reads the open age. B4 shows that the field is now preserved,
  not that eviction with a keep count changes.
- The FCB sequential and random-record calls (14h/15h/21h/22h). They go
  through the same `FCBIO` code but were not run.
- An age above 0 in the position high word (files of 64 KiB or more).
- The `FCBLRU` wrap (`ResetLRU`) reached from the error path. It needs
  65,535 FCB calls.
- K1 key-input regression: B4 changes no console code.
- HDD boot, 2D media, real hardware.

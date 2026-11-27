# B4 — FCB read/write errors lose the SFT open age

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

## Fix (`d7e17a4`)

On carry after the I/O call, the error path reloads the SFT pointer and pops
the saved age into it before it jumps to `FCBDeath`:

```
	JNC	FCBIOSuccess
	LES	DI,CS:[ThisSFT]
	POP	ES:[DI].sf_OpenAge
	JMP	FCBDeath
FCBIOSuccess:
```

The success path is unchanged, apart from the jump sense.

Review:
- **`ThisSFT` is valid on both paths.** `SFTFromFCB` sets `ThisSFT` just
  before the `PUSH`, and its success path is the only way to reach the
  `PUSH`. Both `DOS_Read` and `DOS_Write` take the SFT from `ThisSFT`. The
  FCB open path already relies on `LES DI,ThisSFT` after a failed
  `DOS_Open` (`$FCB_Open`).
- **The INT 24h handler does not move `ThisSFT`.** It may only use
  functions 01h–0Ch and 59h, and those do not set `ThisSFT`.
- **`ES:DI` must be reloaded.** `DOS_Read`/`DOS_Write` do not promise to
  preserve `ES:DI` on failure.
- **The stack is balanced.** The `BUFFERFLAG` block's own
  `PUSHF`/`POPF` pairs are complete before the test.
- **The pattern occurs only here.** `sf_position+2`/`sf_OpenAge` is saved
  and restored around a call at this one site (`grep` of `DOS/*.ASM`).
  `SetOpenAge`, `LRUFCB`, `BlastSFT` and `FCBRegen` only assign or read it.
- **The after build contains the fix.** Its build record says
  `msdos_commit d7e17a4a…`, the sign-on says `(j3b3, d7e17a4a)`, and the
  built `FCBIO2.ASM` has the new lines. `MSDOS.SYS` is 38,848 bytes in
  both builds.

**Found, not fixed:** the same error path also leaves the *LRU* word
(`sf_LRU` = `sf_position` low word) holding the byte position's low word.
On success, `SaveFCBInfo` overwrites it with a fresh LRU count; `FCBDeath`
does not. The probe shows it on both builds (BAD `LRU 0001 → 0000`, DENY
`0002 → 0000`). With `FCBS=2,0`, the next FCB open then evicted the open
BAD entry instead of using the free second entry. `LRUFCB` with keep 0
goes straight to the LRU scan, and the free entry's LRU 0 ties with it.
The result is an unneeded eviction and a later regeneration, not data loss.
This is outside B4's open-age scope and left for a decision.

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
   probe's handler answers Fail.
2. Open DENY. Do a random block write (28h), which is refused.
3. Read DENY, open and read NEXT, then open BAD again. That open must
   evict DENY, the LRU entry, into DENY's own slot and keep NEXT.
4. Read the evicted DENY FCB again; DOS must regenerate its SFT.
5. Close all three FCBs and check that the cache has no live entry. Open,
   read and close NEXT once more.

Exit code 0 = PASS, 2 = open age lost, 1 = a step failed.

## Evidence (vaeg m153, Japanese 2HD distribution image)

Before = `847a33c5` (B4 gate commit, without the fix); after = `d7e17a4a`.
VA and VA2 printed identical logs:
[before](B4/age-before-va.txt), [after](B4/age-after-va.txt).

| Check | Before VA | Before VA2 | After VA | After VA2 |
|---|---|---|---|---|
| Failed FCB read (BAD): AL, CX, ext. error, INT 24h | 01, 0, 53h, 1× (08 sector not found) | same | same | same |
| BAD open age before → after the failed read | 0001 → **0000** | 0001 → **0000** | 0001 → 0001 | 0001 → 0001 |
| Refused FCB write (DENY, read-only): AL, CX, ext. error, INT 24h | 01, 0, 05h (access denied), none | same | same | same |
| DENY open age before → after the refused write | 0002 → **0000** | 0002 → **0000** | 0002 → 0002 | 0002 → 0002 |
| DENY age after a later successful read | 0000 (still lost) | 0000 | 0002 | 0002 |
| Cache full: third open evicts the LRU entry (DENY), keeps NEXT | PASS | PASS | PASS | PASS |
| Evicted FCB reads again (regenerated SFT, age FFFF by `BlastSFT`) | PASS | PASS | PASS | PASS |
| Closes, empty cache, reopen/read/close | PASS | PASS | PASS | PASS |
| Probe verdict / exit code | AGE LOST / 2 | AGE LOST / 2 | PASS / 0 | PASS / 0 |
| `DIR B:` after the probe | 3 files, 1,296,384 free | same | same | same |
| B2 smoke (`docs/B2/run-smoke.py`), two boots | PASS | PASS | PASS | PASS |
| CHKDSK free (boot 1 / boot 2) | 719,872 / 761,856 | same | same | same |
| CHKDSK memory free (FASTOPEN loaded) | 513,664 | 513,664 | 513,664 | 513,664 |
| COPY / EDLIN `1D`, `L`, `E` / TYPE / CHKDSK spot check | PASS | PASS | PASS | PASS |
| CHKDSK memory free (no FASTOPEN) | 524,064 | 524,064 | 524,064 | 524,064 |

- **B2 smoke:** the before and after screens are identical, apart from the
  build stamp and file times. Both `FC /B` comparisons say "no differences
  encountered", and CHKDSK reports no errors.
- **Spot check:** the screens match, apart from the stamp, the times and
  one screen captured while COPY was still printing.
- **Resident size:** unchanged. 655,360 − 513,664 = 141,696 bytes are in
  use after boot with FASTOPEN, the same in both builds.

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
- K1 key-input regression: B4 changes no console code.
- HDD boot, 2D media, real hardware.

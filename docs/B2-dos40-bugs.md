# B2 — Bugs in MS-DOS 4.0 itself

## M1: 4.01, PD0255 and IR80263 fixes

Source: the MIT-licensed community rebuild
[tsupplis/msdos40-hacking](https://github.com/tsupplis/msdos40-hacking).
Its README describes what Microsoft changed for MS-DOS 4.01 (commit
`23106c3`), the PD0255 patch disk (`b4648be`) and IBM APAR IR80263
(`c015db4`). The maintainer asked to take its fixes in as they are. The
diffs were applied unchanged, with only the paths mapped to this tree
(`kernel/dos/` → `DOS/`, `kernel/bios/` → `BIOS/`, `commands/` → `CMD/`,
`kernel/ansi/` → `DEV/ANSI/`). All hunks applied cleanly.

| File | Fix | Origin | Shipped on VA |
|---|---|---|---|
| `DOS/DEV.ASM` | The secondary-cache start sector takes its high word from `HIGH_SECTOR`, not the word after the one-word `CALLSSEC` | 4.01 | MSDOS.SYS |
| `DOS/CTRLC.ASM` | No EMS map restore on the INT 24h path | 4.01 | MSDOS.SYS |
| `DOS/MKNODE.ASM` | MKDIR zeroing carries into the high sector word | PD0255 | MSDOS.SYS |
| `DOS/DISK3.ASM` | Append/grow near 32 MB keeps the high sector word | PD0255 | MSDOS.SYS |
| `CMD/FASTOPEN/FASTSEEK.ASM` | Truncation walks the extent chain | 4.01 | FASTOPEN.EXE |
| `CMD/FORMAT/FORMAT.ASM` | The bad-sector test uses the high sector word | 4.01 | No (VA uses `pc88va/VAFORMAT.ASM`) |
| `BIOS/MSINIT.ASM` | Another boot-record OEM name is accepted | 4.01 | No (VAIO) |
| `CMD/GRAPHICS/GRINT2FH.ASM` | Multiplex number 0ACh, not MSCDEX's 15h | PD0255 | No |
| `DEV/ANSI/ANSIINIT.ASM`, `IOCTL.ASM` | Shift-PrtSc above 25 rows | IBM IR80263 | No |

These were not taken:
- the 4.01 version number change (COMMAND `VER`, USA-MS.MSG); the sign-on stays 4.00;
- SELECT's panel borders (SELECT is not built);
- comment-only encoding changes.

On VA, a 40 MB NEC SASI volume has about 40k 1024-byte sectors. The 32 MB
high-word paths therefore stay at zero, and only the DEV.ASM and FASTOPEN
fixes can affect a VA volume.

### Evidence (vaeg m153, Japanese image)

[`B2/run-smoke.py`](B2/run-smoke.py) runs two boots per model, on VA and
VA2.
- First boot: FASTOPEN, COPY of COMMAND.COM, MD, COPY into the
  subdirectory, overwriting a file with ECHO, TYPE, CHKDSK.
- Second boot, on the same disk: FASTOPEN, COPY back, `FC /B` against
  COMMAND.COM, DEL, RD, DIR, CHKDSK.

The same script ran on the release image (87b1c85) and the B2 image. The
screens are identical except for the build stamp, directory times, and 16
bytes less free memory (513,648 → 513,632). Both `FC /B` comparisons
match. CHKDSK reports no errors on either boot
([VA second boot](B2/va-boot2.txt), [VA2 first boot](B2/va2-boot1.txt)).

**Found while testing, older than B2:** with any look-ahead buffers
(`BUFFERS=20,1` or `20,8`), VA stops after the sign-on, before the
prompt. `BUFFERS=20` boots. The release image does the same, so the
DEV.ASM fix does not cure it. This is a VA port bug in the
secondary-cache path. It is a follow-up.

**NOT RUN:**
- HDD boot;
- volumes over 32 MB (not possible with VA SASI);
- EMS (`BUFFERS /X`);
- a FASTOPEN mid-extent truncation case;
- real hardware.

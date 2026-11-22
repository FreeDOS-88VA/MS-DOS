# J3b.4 — Project FEP user dictionary

## Gates (defined before implementation)

1. On vaeg, ADD/DEL/LIST, exact FAT file format, malformed/oversized input,
   duplicate and full-table rejection.
2. On vaeg, load, reload and confirm user candidates before the BIOS;
   reverse across the boundary, and verify a reading with no user match.
3. On VA 640 KiB and VA2 256/640 KiB, run the nested-interrupt monitor,
   COPY CON/EDLIN byte checks, the J3c switch gate and CHKDSK in three modes.

## Foreground commands and format

`JFP ADD <reading> <word>`, `JFP DEL <reading> <word>` and `JFP LIST`
operate on `A:\JFPUSER.DIC` independently of the current directory and
input mode. The current VABOOT/VAIO boot path uses A:; the port did not
return a usable boot drive via INT 21h AX=3305h in the first gate attempt.
Revisit the path when a different boot drive is supported. Type both arguments
as full-width Shift-JIS; use ASCII spaces/tabs as separators. Each argument
is 1–30 cells. A reading accepts hiragana and the prolonged sound mark
(`ー`), the same repertoire as the conversion backend. A word accepts
structurally valid two-byte Shift-JIS with leads 81h–9Fh/E0h–EFh and trails
40h–FCh except 7Fh. This is not an assigned-character or font check.

Version 1 starts with five ASCII bytes `JFPUD` followed by byte `01h`.
Zero to eight 122-byte records follow, in registration order, with no
terminator: one reading-byte count, one word-byte count, 60 bytes for
the reading and 60 for the word. Each field contains its counted bytes
followed by zero padding. Exact duplicate pairs are invalid; different
words for the same reading are permitted. Maximum file size: 982 bytes.
The file contains user input, not a copy of any ROM dictionary.

Saves stage a complete file in `JFPUSER.TMP`, rename an existing dictionary
to `JFPUSER.BAK`, then rename the staged file into place and remove the
backup. An existing staging or backup file is never overwritten. On a
failed publish the command attempts to restore the backup. This is not
a crash-atomic filesystem transaction: after interruption or an I/O error,
inspect the three files before removing a stale temporary file or restoring
a backup. Keep backups of important registrations.

## Firmware reference

PC-88VA Technical Manual `618JFP` §6.18.4 documents `AddWd` and `DelWd`
(INT 8Dh CL=14h/15h), and `GetUDEnv` / `SetUDEnv` for the firmware's user
dictionary name. The manual explicitly describes `AddWd` opening, writing
and closing the ROM-managed file. We use none of these functions: the
format and lifetime are project-owned, and J3b.3 qualifies only the
built-in conversion backend (its activation guard requires both firmware
default files absent). The project file does not change that guard.

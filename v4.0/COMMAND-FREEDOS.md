# Optional FreeDOS COMMAND.COM compatibility profile

This is an opt-in adaptation of the published MS-DOS 4 COMMAND sources, not a
FreeDOS kernel patch. Assemble all COMMAND modules with MASM `/DFREEDOS`.
Without that definition the original source paths remain selected.

- Accept OEM FD with DOS version 4 or newer instead of requiring an exact
  MS-DOS 4.00 version. The kernel and other applications keep their native
  reported version.
- The FreeDOS FAT profile has no OS/2 per-file extended attributes. COPY and
  TYPE omit the extended-attribute/code-page-tag operations. Normal open,
  read, write, timestamp and close errors are still handled normally.
- Keep parser, extended-error and critical-error message pointers inside each
  shell instead of relying on MS-DOS INT 2Fh/122Eh registration (ignored by
  FreeDOS). Preserve the original on-disk message loading for permanent shells
  without `/MSG`. This is shell-local adaptation, not a replacement kernel API
  for other MS-DOS utilities. `/Y` remains unsupported and reports an invalid
  switch; this profile does not add AUTOEXEC single-stepping.
- `/DPC88VA` additionally selects native text-BIOS clear/home output for CLS
  only when stdout is standard CON. The DOS character adapter filters escape
  and form-feed bytes, so DOS form feed alone cannot clear the display.
  Redirected output uses DOS AH=40h and receives the ANSI clear/home sequence.
  The adapter preserves registers/flags and rejects an absent text-BIOS vector;
  it never calls IBM INT 10h. Use this selector with `/DFREEDOS` on PC-88VA.

The ordinary environment, DOS file operations and transient reload algorithm
remain from the original COMMAND sources. No FAT long filenames, OS/2 extended
attributes, or arbitrary DOS/BIOS compatibility is promised by this profile.
Use an explicit SHELL path and configure PATH in AUTOEXEC.BAT. Do not spoof the
DOS version globally. Runtime tests belong to the exact linked binary and
platform; compilation alone is not a compatibility result.

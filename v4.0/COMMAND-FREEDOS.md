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
- `/DPC88VA` additionally selects DOS form-feed output for CLS, using the
  VA CON driver's clear/home operation instead of IBM INT 10h. This selector
  must be used together with `/DFREEDOS` on the PC-88VA FreeDOS port.

The ordinary environment, DOS file operations and transient reload algorithm
remain from the original COMMAND sources. No FAT long filenames, OS/2 extended
attributes, or arbitrary DOS/BIOS compatibility is promised by this profile.
Use an explicit SHELL path and configure PATH in AUTOEXEC.BAT. Do not spoof the
DOS version globally. Runtime tests belong to the exact linked binary and
platform; compilation alone is not a compatibility result.

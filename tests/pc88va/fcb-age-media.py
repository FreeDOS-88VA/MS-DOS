#!/usr/bin/env python3
"""Create scratch A.d88 and B.d88 for FCBAGE, using the builder's FAT12 helpers.

Usage: fcb-age-media.py BUILDER_EXPERIMENT IMAGE FCBAGE.COM SCRATCH_DIR
BUILDER_EXPERIMENT is the directory containing build.py and readfile.py.
"""
import argparse
import struct
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for arg in ('builder_experiment', 'image', 'probe', 'scratch_dir'):
        ap.add_argument(arg, type=Path)
    a = ap.parse_args()
    out = a.scratch_dir.resolve()
    if out.is_relative_to(Path(__file__).resolve().parents[2]):
        ap.error('scratch directory must be outside the repository')
    out.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(a.builder_experiment))
    from build import compose, d88, FIRST_DATA, SECTOR, SPT
    from readfile import raw_image, read_file

    raw = raw_image(a.image.read_bytes())
    boot = raw[:SECTOR]
    serial, = struct.unpack_from('<I', boot, 39)
    date = 0x5821  # 2024-01-01
    # Keep the builder's system file ordering and attributes on A:.
    files = [(name, read_file(raw, name), attr) for name, attr in
             [('IO.SYS', 7), ('MSDOS.SYS', 7), ('COMMAND.COM', 32)]]
    # AUTOEXEC.BAT keeps COMMAND from stopping at the date prompt.
    files += [('CONFIG.SYS', b'FILES=20\r\nBUFFERS=10\r\nFCBS=2,0\r\n', 32),
              ('AUTOEXEC.BAT', b'PROMPT $P$G\r\n', 32),
              ('FCBAGE.COM', a.probe.read_bytes(), 32)]
    (out / 'A.d88').write_bytes(d88(compose(boot, files, 'B4 BOOT', date, serial), 'B4-BOOT'))

    # BAD.DAT is the first allocated cluster. Give just its data sector a
    # sector ID (R) that no read asks for, so the FDC reports No Data and the
    # read fails; its FAT and directory stay good. (vaeg does not act on the
    # D88 status byte, so a CRC status alone would read back as good data.)
    payload = b'B4 test data'.ljust(SECTOR, b'.')
    data = [('BAD.DAT', payload, 32), ('DENY.DAT', payload, 33), ('NEXT.DAT', payload, 32)]
    disk = bytearray(d88(compose(boot, data, 'B4 TEST', date, serial ^ 1), 'B4-TEST'))
    track, sector = divmod(FIRST_DATA, SPT)
    offset, = struct.unpack_from('<I', disk, 0x20 + track * 4)
    header = offset + sector * (16 + SECTOR)
    assert disk[header + 2] == sector + 1
    disk[header + 2] = 0xf5
    (out / 'B.d88').write_bytes(disk)


if __name__ == '__main__':
    main()

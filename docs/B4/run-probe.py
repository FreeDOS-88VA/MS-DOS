#!/usr/bin/env python3
"""B4 probe run: boot the FCBAGE media on VA and VA2, keep AGE.LOG and screens.
Env: VAEG, VAEG_ROMS, VAEG_QA (vaeg tools/qa).
Usage: run-probe.py BUILDER_EXPERIMENT MEDIA_DIR OUTDIR
MEDIA_DIR holds A.d88/B.d88 from tests/pc88va/fcb-age-media.py; MEDIA_DIR and
OUTDIR are scratch directories outside the repository."""
import sys, os, shutil, subprocess
from pathlib import Path
sys.path.insert(0, os.environ['VAEG_QA'])
from m75_scsi_harness import decode_screen
vaeg, roms = os.environ['VAEG'], os.environ['VAEG_ROMS']
CMDS = ['FCBAGE > AGE.LOG', 'IF ERRORLEVEL 2 ECHO EXIT=2',
        'IF NOT ERRORLEVEL 1 ECHO EXIT=0', 'DIR B:']


def run(media, out, model, interval=900):
    out.mkdir(parents=True)
    for n in ('A', 'B'):
        shutil.copyfile(media / f'{n}.d88', out / f'{n}.d88')
    frame = 700
    plan = ['debug-script 1', f'limit-frame {frame + interval * len(CMDS) + 600}']
    for i, c in enumerate(['', *CMDS]):
        if c:
            plan.append('input-line ' + c)
        plan += [f'wait-frame {frame}', 'wait-pc 1000:0A73 1', f'capture s{i} tvram screen']
        frame += interval
    (out / 'run.debug').write_text('\n'.join(plan + ['exit', '']))
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')
    p = subprocess.Popen([vaeg, '--roms', roms, '--model', model, '--no-cfg', '--no-bkupmem',
                          '--nowait', '--fdd1', 'A.d88', '--fdd2', 'B.d88',
                          '--debug-script', 'run.debug', '--debug-output-dir', '.'],
                         cwd=out, env=env, stdout=open(out / 'run.log', 'wb'),
                         stderr=subprocess.STDOUT)
    print(f'{model}: vaeg pid {p.pid}', flush=True)
    p.wait(timeout=600)
    txt = []
    for i in range(len(CMDS) + 1):
        d = out / f's{i}.tvram.bin'
        if d.exists():
            txt.append('\n'.join(s.rstrip('? ') for s in decode_screen(d)['lines']))
    (out / 'screens.txt').write_text('\n=====\n'.join(txt) + '\n')
    log = read_file(raw_image((out / 'A.d88').read_bytes()), 'AGE.LOG')
    (out / 'AGE.LOG').write_bytes(log)
    print(log.decode('ascii', 'replace'), flush=True)


builder, media, base = (Path(a) for a in sys.argv[1:4])
sys.path.insert(0, str(builder))
from readfile import raw_image, read_file
for m in ('va', 'va2'):
    run(media, base / m, m)

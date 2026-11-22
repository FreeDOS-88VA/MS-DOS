#!/usr/bin/env python3
"""B2 smoke test: two boots per model. Env: VAEG, VAEG_ROMS, VAEG_QA (vaeg tools/qa).
Usage: run-smoke.py IMAGE.d88 OUTDIR (OUTDIR in scratch)."""
import sys, os, shutil, subprocess
from pathlib import Path
sys.path.insert(0, os.environ['VAEG_QA'])
from m75_scsi_harness import decode_screen
vaeg = os.environ['VAEG']
roms = os.environ['VAEG_ROMS']
def run(disk, out, model, cmds, interval=900):
    out.mkdir(parents=True); shutil.copyfile(disk, out/'disk.d88')
    frame=700; plan=['debug-script 1', f'limit-frame {frame+interval*len(cmds)+600}']
    for i,c in enumerate(['',*cmds]):
        if c: plan.append('input-line '+c)
        plan += [f'wait-frame {frame}', 'wait-pc 1000:0A73 1', f'capture s{i} tvram screen']
        frame += interval
    (out/'run.debug').write_text('\n'.join(plan+['exit','']))
    env=dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')
    subprocess.run([vaeg,'--roms',roms,'--model',model,'--no-cfg','--no-bkupmem','--nowait','--fdd1','disk.d88','--debug-script','run.debug','--debug-output-dir','.'],cwd=out,env=env,stdout=open(out/'run.log','wb'),stderr=subprocess.STDOUT,timeout=600)
    txt=[]
    for i in range(len(cmds)+1):
        d=out/f's{i}.tvram.bin'
        if d.exists(): txt.append('\n'.join(s.rstrip('? ') for s in decode_screen(d)['lines']))
    (out/'screens.txt').write_text('\n=====\n'.join(txt)+'\n')
    return out/'disk.d88'
img=Path(sys.argv[1]); base=Path(sys.argv[2])
A=['TYPE CONFIG.SYS','FASTOPEN A:','COPY COMMAND.COM X.COM','MD SUB','COPY X.COM SUB','COPY README.TXT SUB','DIR SUB','ECHO HELLO> X.COM','TYPE X.COM','CHKDSK']
B=['FASTOPEN A:','COPY SUB\\X.COM Z.COM','FC /B Z.COM COMMAND.COM','FC /B SUB\\X.COM COMMAND.COM','DEL SUB\\X.COM','DEL SUB\\README.TXT','RD SUB','DEL Z.COM','DEL X.COM','DIR /W','CHKDSK']
for m in ('va','va2'):
    d=run(img, base/m/'a', m, A)
    run(d, base/m/'b', m, B)

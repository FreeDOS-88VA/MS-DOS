#!/usr/bin/env python3
"""Cold-boot J3.0 probes. All media, private states and captures stay in scratch.

Set PYTHONPATH to the FreeDOS experiments/msdos4-va builder directory.
Arguments: vaeg rom-directory distribution.d88 new-scratch-dir [case ...]
"""
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

PROBES = Path(__file__).resolve().parent
ROOT = PROBES.parents[1]


def prepare(base, out):
    sys.path.insert(0, str(ROOT / 'docs/J1'))
    from media import pack_va

    for src, dest in [('JFPBOOT.NAS', 'boot.bin'), ('JFPPROBE.NAS', 'JFPPROBE.COM')]:
        subprocess.run(['nasm', '-f', 'bin', '-o', out / dest, PROBES / src], check=True)
    pack_va(base, out / 'probe.d88', [('JFPPROBE.COM', (out / 'JFPPROBE.COM').read_bytes())])
    disk = bytearray(base.read_bytes())
    sec, = struct.unpack_from('<I', disk, 0x20)
    assert struct.unpack_from('<H', disk, sec + 14) == (1024,)
    boot = bytearray((out / 'boot.bin').read_bytes())
    assert len(boot) == 1024
    sec += 16
    boot[3:62] = disk[sec + 3:sec + 62]
    disk[sec:sec + 1024] = boot
    (out / 'boot.d88').write_bytes(disk)


def keys_at(start, actions):
    """Every tap is followed by an idle interval before the next snapshot."""
    commands = []
    for n, (key, label) in enumerate(actions):
        frame = start + n * 45
        commands.append(f'wait-frame {frame}')
        if key.startswith('CTRL+'):
            commands.extend(('key-down CTRL', f'key-tap {key[5:]} 3', 'key-up CTRL'))
        else:
            commands.append(f'key-tap {key} 3')
        if label:
            commands.extend((f'wait-frame {frame + 30}', f'save-state {label}'))
    return commands


def scenarios():
    yield 'boot', 'boot', ['wait-pc 3000:0100 1', 'capture handoff registers',
                           'save-state handoff']
    yield 'dos', 'base', ['wait-pc 1000:0000 1', 'save-state io-entry',
                          'wait-pc 1139:07F2 1', 'save-state sysinit',
                          'wait-pc 112B:0000 1', 'save-state dos-entry',
                          'wait-frame 550', 'wait-pc 1000:06D0 1', 'capture prompt screen tvram',
                          'save-state prompt']
    for options in ('N', 'P', 'G', 'B', 'I', 'K', 'R', 'S', 'KR', 'KRS',
                    'IRKJ', 'KRJ', 'RT', 'IT', 'T', 'RS', 'RK', 'RF',
                    'RJ', 'IRJ', 'HRJ', 'RFJ', 'RZ', 'RJX'):
        body = ['wait-frame 600', f'input-line JFPPROBE {options}', 'wait-frame 1800',
                'save-state setup']
        if options in ('P', 'G', 'B', 'I', 'K', 'R', 'KRJ', 'IRKJ'):
            body += ['key-tap A 3', 'wait-frame 1850', 'key-tap F1 3', 'wait-frame 1900',
                     'key-tap HENKAN 3', 'wait-frame 1950', 'key-down KANA', 'key-tap A 3',
                     'wait-frame 1990', 'key-up KANA', 'key-tap KETTEI 3', 'wait-frame 2050',
                     'save-state keys']
        if options in ('RJ', 'IRJ', 'HRJ', 'RFJ'):
            body += keys_at(1850, [(k, None) for k in 'NIHON'] + [
                ('HENKAN', 'candidate'), ('KETTEI', 'commit'),
                ('A', 'kana-pending'), ('KETTEI', 'kana-commit')])
        if options == 'RZ':
            body += keys_at(1850, [('HENKAN', 'henkan'), ('ZENKAKU', 'wide'),
                                   ('A', 'a'), ('ZENKAKU', 'wide-pending'),
                                   ('KETTEI', 'decided'), ('ZENKAKU', 'narrow'),
                                   ('A', 'ascii')])
        if options == 'RJX':
            body += keys_at(1850, [('A', None), ('I', 'ai'), ('BS', 'bs'),
                                   ('KETTEI', 'bs-confirm'), ('A', 'pre-esc'), ('ESC', 'esc'),
                                   ('A', 'pre-ctrl-c'), ('CTRL+C', 'ctrl-c'),
                                   ('A', 'pre-f1'), ('F1', 'f1'), ('F6', 'f6'),
                                   ('KETTEI', 'fkeys-confirm'), ('ESC', 'idle-esc'),
                                   ('CTRL+C', 'idle-ctrl-c'), ('F1', 'idle-f1')])
        yield options.lower(), 'probe', body


def main():
    vaeg, roms, base, out = (Path(x).resolve() for x in sys.argv[1:5])
    if out.is_relative_to(ROOT):
        raise SystemExit('scratch must be outside the repository')
    out.mkdir()
    prepare(base, out)
    images = {'base': base, 'boot': out / 'boot.d88', 'probe': out / 'probe.d88'}
    wanted = sys.argv[5:]
    env = dict(os.environ, SDL_VIDEODRIVER='dummy', SDL_AUDIODRIVER='dummy')

    def run(case):
        model, name, image, body = case
        work = out / model / name
        work.mkdir(parents=True)
        shutil.copyfile(images[image], work / 'disk.d88')
        script = ['debug-script 1', 'limit-frame 4000', *body, 'exit', '']
        (work / 'run.debug').write_text('\n'.join(script))
        with (work / 'run.log').open('wb') as log:
            result = subprocess.run([str(vaeg), '--model', model, '--roms', str(roms), '--no-cfg',
                                     '--no-bkupmem', '--nowait', '--fdd1', 'disk.d88',
                                     '--debug-script', 'run.debug', '--debug-output-dir', '.',
                                     '--screen-dump', 'end.bmp', '--screen-tvram-dump', 'end.tvram'],
                                    cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=180)
        events = work / 'events.tsv'
        if result.returncode or not events.exists() or not events.read_text().splitlines()[-1].startswith('exit\t'):
            raise RuntimeError(f'{work}: script did not exit normally; inspect the scratch log')
        print(model, name, flush=True)

    cases = [(model, *case) for model in ('va', 'va2') for case in scenarios()
             if not wanted or case[0] in wanted]
    with ThreadPoolExecutor(4) as pool:
        list(pool.map(run, cases))


if __name__ == '__main__':
    main()

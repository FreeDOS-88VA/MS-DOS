#!/usr/bin/env python3
"""Send PC-98 keys to the focused NP2kai X11 window at the DOS prompt."""
import argparse
from pathlib import Path
import subprocess
import time


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('window', help='X11 window ID (xdotool search)')
    p.add_argument('out', type=Path)
    p.add_argument('--raw', action='store_true', help='use the scratch disk with CONKEY.COM')
    args = p.parse_args()
    args.out.mkdir(parents=True)
    subprocess.run(['xdotool', 'windowfocus', '--sync', args.window], check=True)

    def key(*keys):
        for name in keys:
            subprocess.run(['xdotool', 'keydown', name], check=True)
            time.sleep(.05)
            subprocess.run(['xdotool', 'keyup', name], check=True)
            time.sleep(.09)

    def snap(name):
        time.sleep(.2)
        subprocess.run(['import', '-window', args.window, str(args.out / f'{name}.png')],
                       check=True)

    def cls():
        key('c', 'l', 's', 'Return')
        time.sleep(.35)

    cases = {
        'up': ('Up', 'Up'), 'right': ('Right', 'Right'),
        'home': ('Home', 'Home'), 'shift-home': ('Shift+Home', 'Shift+Home'),
        'mixed': ('Shift+a', 'Up', 'Shift+b', 'Right'),
        'down': ('Shift+a', 'Shift+b', 'Down'),
        'left': ('Shift+a', 'Shift+b', 'Left'), 'del': ('Shift+a', 'Shift+b', 'Delete'),
        'roll-up': ('Shift+a', 'Shift+b', 'Page_Up'),
        'roll-down': ('Shift+a', 'Shift+b', 'Page_Down'),
        'help': ('Shift+a', 'Shift+b', 'End'),
    }
    if args.raw:
        cls()
        key('c', 'o', 'n', 'k', 'e', 'y', 'space', 'Shift+k', 'Return')
        time.sleep(.5)
        # Ordinary ASCII digits delimit every physical key's response, including empty ones.
        key('1', 'Up', '2', 'Right', '3', 'Down', '4', 'Left', '5', 'Home',
            '6', 'Shift+Home', '7', 'Delete', '8', 'Insert', '9', 'Page_Up',
            '0', 'Page_Down', '1', 'End', '2', 'BackSpace', '3')
        snap('raw')
        key('q')
        return
    for name, keys in cases.items():
        cls()
        key(*keys)
        snap(f'{name}-before')
        key('BackSpace')
        snap(f'{name}-erased')
        key('Return')
        time.sleep(.35)
        if name == 'down':
            key('F3')
            snap('down-recalled')
            key('Return')
            time.sleep(.35)
    cls()
    key('Shift+a', 'Shift+b', 'Shift+c', 'Shift+d', 'Shift+e', 'Shift+f', 'Return')
    time.sleep(.35)
    key('Shift+x', 'Insert', 'Shift+y')
    snap('ins-before')
    key('BackSpace')
    snap('ins-erased')
    key('Shift+z', 'F3')
    snap('ins-recalled')
    key('Return')


if __name__ == '__main__':
    main()

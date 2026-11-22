"""Shared assertions for the J3c screen and FAT checks (J3a QA dependencies)."""
import importlib.util

from run import ROOT


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


j3a = load('j3a_check', 'docs/J3a/check.py')
j3b3 = load('j3b3_run', 'docs/J3b.3/run.py')
P = j3a.PROMPT
v, screen, labels, pixels = j3a.relevant, j3a.screen, j3a.label_words, j3a.label_pixels
MSG = {'ROM': 'JFP on (ROM fallback: default file missing).',
       'FEP': 'Project FEP on. ZENKAKU: kana; F7: katakana; HENKAN: candidates.'}


def verify_selection(path, mode):
    assert MSG[mode] in v(path), (path, v(path))


def expect_echo(path, text):
    return v(path)[-3:] == [P + 'echo ' + text, text, P]


def adopt(p, original, **replace):
    """Preserve the old keyboard schedule and capture names, substituting selectors."""
    p.body = [replace.get(cmd, cmd) for cmd in original.body]
    p.frame = original.frame
    p.shots = [cmd.partition('\ncapture ')[2].split()[0] for cmd in p.body if '\ncapture ' in cmd]
    return p

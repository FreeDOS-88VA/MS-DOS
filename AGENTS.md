# AGENTS.md — MS-DOS 4.0 for NEC PC-88VA

Working tree of `FreeDOS-88VA/MS-DOS`, branch `release/msdos-va`.
PC-88VA code lives in `pc88va/`, `v4.0/pc88va/` and `v2.0/pc88va/`;
changes to the Microsoft sources stay under `v4.0/src`.

## Workflow

1. **Implement: pi.** Opus 5.5 writes instructions for the `pi` agent,
   sized for the 6.2-Sol model at medium effort. Split the work into small
   milestones, each with one goal, a list of files it touches, and a
   pass/fail gate (build, boot on vaeg, a specific command's output).
   Hand pi one milestone at a time. Briefs live in `docs/tasks/`; run
   them with
   `pi -p --model gpt-6.2-sol:medium @docs/tasks/<brief>.md`.
2. **Review: Opus 5.5, adversarial.** After each milestone, Opus 5.5
   reviews pi's diff and results adversarially. The review assumes the
   change is wrong until the code and the gate output show it is right,
   and it looks for regressions, unhandled PC-88VA cases (1024-byte
   sectors, 2HD/2D media, ROM BIOS calls) and claims that were never
   tested.
3. **Decide: Opus 5.5.** Opus 5.5 decides whether to accept the
   milestone, send it back to pi with specific fixes, or split it again.
   The next milestone starts only after this decision.

The maintainer decides whether to push or publish.

## Milestones

The plan is in `docs/ROADMAP.md`. Work on `topic/mNN-<name>` with
commit prefix `MNN:`. Record each
milestone's gate before starting. Do not stack a milestone on one whose
gate has not passed.

## Files that never enter the repository directory

NEC disk images (D88, FDI, HDI), NEC manuals (PDF), product photos, ROM
files and anything extracted from them must stay outside this
repository's directory tree — not committed, and not left untracked in
the working tree either. Extract and run them only in a scratch
directory outside the repository (for example under `/tmp` or
`../pc88va/tmp/`) and delete the scratch copy when done. The only
exception is the maintainer's own `NEC 日本語MS-DOS 3.3D 基本機能セット.zip`
in the repository root, which is excluded from Git and must not be
unpacked in place. Screenshots of NEC screens may be committed as
evidence; ROM contents, dumps and ROM-internal addresses may not.

## References

- `NEC 日本語MS-DOS 3.3D 基本機能セット.zip` (untracked): PC-98 MS-DOS 3.3D
  disks as D88 images plus manuals. Use it as the reference for which
  commands and drivers a Japanese NEC DOS ships. Do not commit it.
- To observe NEC MS-DOS behavior on a PC-98, use NP2kai
  (https://domisan.sakura.ne.jp/article/np2kai/np2kai.html), not MAME.
  Build it outside the repository; PC-98 ROMs and NEC disk images stay
  out of Git.

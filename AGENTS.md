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

## References

- `NEC 日本語MS-DOS 3.3D 基本機能セット.zip` (untracked): PC-98 MS-DOS 3.3D
  disks as D88 images plus manuals. Use it as the reference for which
  commands and drivers a Japanese NEC DOS ships. Do not commit it.

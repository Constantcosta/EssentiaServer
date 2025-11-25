# Handover for Claude Sonnet 4.5 (operational instructions)

Purpose
- This document tells Claude Sonnet 4.5 exactly what it must do and must not do when working on this repository (`EssentiaServer`) to avoid breaking the analysis pipeline or losing data.

Scope & context
- Repo root: `/Users/costasconstantinou/Documents/GitHub/EssentiaServer`
- Active branch with recent work: `copilot/improve-slow-code-efficiency` (backup snapshot pushed to origin).
- Key recent work (important): a mid-tempo octave validator and a BPM calibration framework were added to improve preview (30s) analysis accuracy.

Key modified files (read these first)
- `backend/analysis/tempo_detection.py` — tempo detection logic and the new mid-tempo octave validator.
- `backend/analysis/calibration.py` — linear calibration and the new BPM calibration loader & applier.
- `backend/analysis/pipeline.py` and `backend/analysis/pipeline_core.py` — calibration hook wiring (scalers → key → bpm → models).
- `backend/analyze_server.py` — loads calibration assets at startup and registers BPM calibration hook.
- `config/bpm_calibration.json` — BPM calibration rules (careful: rules may be disabled or conservative by intent).

Goals for the agent
1. Preserve and improve preview (short-clip) tempo and key detection without regressing other tracks.
2. Make focused, minimal changes. Prefer detection-time fixes over aggressive post-hoc calibration.
3. Keep a clear audit trail: small commits, descriptive messages, and tests passing before push/PR.

Absolute Do's (requirements)
- DO run tests locally before committing. Primary test command for previews:

```zsh
./run_test.sh a
```

- DO inspect logs at `/tmp/essentia_server.log` (or the configured server log) for detection and calibration messages.
- DO write small, focused commits with precise messages like: `fix(tempo): refine mid-tempo validator threshold for preview clips`.
- DO run only the tests affected by your change first; then run full suite if those pass.
- DO add unit tests or regression tests for any new detection heuristic added.
- DO limit changes to the smallest scope needed: prefer editing `tempo_detection.py` or `calibration.py` only when solving BPM/key issues.
- DO preserve existing runtime behavior for full-length tracks unless explicitly required by a tested change.
- DO respect the short-clip adaptive parameters in `backend/analysis/settings.py` (e.g., preview thresholds). If you change them, document rationale and add regression tests.
- DO back up branches: push to a feature branch (not overwrite `main`). Use names like `feat/bpm-midtempo-fix-<short-desc>`.

Absolute Don'ts (forbidden actions — follow these strictly)
- DON'T commit or push large binary or generated test asset files (audio exports, CSV mass exports) to git. If you accidentally add them, do NOT rewrite history on `main`. Instead create a new commit that removes them and add a `.gitignore` entry.
- DON'T force-push to shared branches (including `main`) without explicit human approval.
- DON'T rewrite commit history for published branches; avoid `git rebase --force` on branches others may use.
- DON'T delete or massively refactor `backend/analysis/*` files without a clear migration plan and tests — those are sensitive.
- DON'T apply broad auto-formatting changes across the repo in a single commit (this makes diffs useless). If formatting is needed, limit to the edited files and run linters as separate commit.
- DON'T disable tests or remove test cases to make CI pass — fix the root cause.
- DON'T add or change calibration rules in `config/bpm_calibration.json` with sweeping patterns that target many songs at once; keep rules conservative and well-documented.
- DON'T change server startup behavior (how calibration files are loaded) without adding clear logs and a fallback path.

Operational procedures (step-by-step)
1. Prepare environment (macOS zsh): ensure dependencies installed per `backend/requirements.txt` or `requirements.txt`.
2. Check status and branch:

```zsh
git status
git branch --show-current
git fetch origin
```

3. Create a feature branch from the current branch or `main` (prefer current feature branch if continuing work):

```zsh
git checkout -b feat/bpm-midtempo-fix-<short-desc>
```

4. Run the preview tests for quick feedback:

```zsh
./run_test.sh a
```

5. Make a focused code change. Example safe workflow when tuning the mid-tempo validator:
- Edit `backend/analysis/tempo_detection.py`.
- Run the single-file unit/regression test if one exists, or run `./run_test.sh a` again.
- Check `/tmp/essentia_server.log` for lines like `Mid-tempo octave correction` and `Applied calibration layer`.

6. Commit with a small message and push your branch:

```zsh
git add backend/analysis/tempo_detection.py
git commit -m "fix(tempo): adjust mid-tempo validator factors and threshold"
git push --set-upstream origin feat/bpm-midtempo-fix-<short-desc>
```

7. Open a PR to `main` with a clear description, test logs (attach sample server log excerpts), and request 1 reviewer.

PR checklist (must be satisfied before merge)
- Tests that exercise the change pass locally and in CI.
- No new large files were added.
- Commits are small, focused, and documented.
- Regression tests added for any heuristic changes.
- A human sign-off on calibration rule changes (because they can be brittle).

Calibration and tuning notes (important)
- The detection-time validator uses onset energy separation heuristics; it tries multipliers [1.5, 5/3, 2.0] and applies a candidate only if separation improves by >= the configured improvement factor.
- The calibration layer (linear scalers) runs after detection-time corrections — calibrators can nudge values slightly (example: 143.6→137). If calibration moves results undesirably, prefer to adjust detection heuristics first, then adjust calibration conservatively.
- For preview clips (<45s): conservative heuristics are preferred. Avoid aggressive 2× corrections unless separation metric strongly supports it.

How to debug a mis-detected file (stepwise)
1. Reproduce the problematic file with the preview test suite: `./run_test.sh a` (or the relevant single-file test harness).
2. Capture server log and detection diagnostic lines:
   - Search for `Mid-tempo octave correction` log entries.
   - Search for `Applied calibration layer` to see post-detection changes.
3. Run the analyzer interactively (if available) to print candidate tempos, onset separation scores, and chosen multiplier.
4. If the choice is wrong, tune the improvement threshold in `tempo_detection.py` or add an exclusion rule in `config/bpm_calibration.json` as a last resort.
5. Add a focused regression test for that single preview to prevent regressions.

Emergency rollback steps (if a push/PR breaks things)
- If you pushed a problematic branch: create a new commit that reverts the change (do NOT force-push to `main`). Example:

```zsh
git checkout main
git pull origin main
git checkout -b revert/problematic-change
git revert <commit-sha>   # creates a revert commit
git push origin revert/problematic-change
# open PR to merge revert into main
```

- If you need to restore the last known backup branch (the backup branch is `copilot/improve-slow-code-efficiency`):

```zsh
git fetch origin
git checkout -b restore-from-copilot origin/copilot/improve-slow-code-efficiency
# run tests locally
```

- If you accidentally committed large generated files, remove them with a normal commit (do not rewrite public history):

```zsh
git rm --cached path/to/large-file
echo "path/to/large-file" >> .gitignore
git commit -m "chore: remove accidental large file and update .gitignore"
git push origin <branch>
```

Explicit examples of permitted edits
- Tuning numeric thresholds in `tempo_detection.py` for onset separation improvement factor.
- Adding a small regression test (new file under `Test files/` or test harness) that exercises the changed behavior.
- Adding logging that helps debug detection decisions.

Explicit examples of prohibited edits
- Replacing the entire `backend/analysis` folder with a new implementation without a staged migration.
- Mass changes to `config/` files that apply sweeping corrections across many songs without per-rule justification.
- Force-pushing `main` or rewriting previously pushed commit history in public branches.

Contact & approvals
- Always request a human reviewer for merges that:
  - change calibration rules in `config/bpm_calibration.json`.
  - adjust detection heuristics used for previews (<45s).
- If unsure, open a draft PR and request guidance rather than pushing to `main`.

Final checklist before closing a task
- [ ] Branch name uses `feat/` or `fix/` prefix and describes the change.
- [ ] Tests pass locally and CI shows green (where applicable).
- [ ] No large binary/test artifacts added.
- [ ] PR description includes sample logs and rationale for parameter choices.
- [ ] At least one human reviewer acknowledged and approved the change.

Notes about the tone and conduct expected from Claude Sonnet 4.5
- Be explicit and conservative: err on the side of *not changing* large or shared state without human approval.
- When in doubt, stop and ask: open a draft PR or a GitHub issue describing the intended change and request a human sign-off.
- Never use coarse, sweeping heuristics (``apply to all``) as a first attempt.

End of handover.

File path: `HANDOVER_FOR_CLAUDE_SONNET_4.5.md`

If you want, I can now:
- Open a PR from the backup branch to `main`, or
- Remove test assets accidentally added and push a cleaned branch, or
- Continue tuning one specific failing preview (tell me which one).

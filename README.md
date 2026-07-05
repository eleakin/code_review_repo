# code_review_repo

An automated **Claude → GitHub → Greptile** review loop. Code written in
Claude gets pushed here as a PR, Greptile reviews it, and if the review
scores **4/5 or higher** the PR is automatically approved.

## How the loop works

```
Claude writes code
      │
      ▼
commit → push feature branch → open PR          (scripts/greptile_loop.py)
      │
      ▼
Greptile GitHub App reviews the PR and posts a score (X/5)
      │
      ├── score ≥ 4 ──► greptile-gate workflow APPROVES the PR
      │                 (+ auto-merges if AUTO_MERGE=true)
      │
      └── score < 4 ──► feedback is fed back to Claude,
                        Claude fixes, commits, and the loop repeats
```

Two pieces implement this:

| Piece | File | Role |
|---|---|---|
| Score gate | `.github/workflows/greptile-gate.yml` | Runs in GitHub Actions when Greptile posts its review. Parses the X/5 score; approves + labels at ≥ 4, requests changes below. |
| Loop driver | `scripts/greptile_loop.py` | Run by Claude Code (or you). Pushes the branch, opens the PR, polls for Greptile's score, and prints the review feedback on failure so Claude can fix it. |
| Claude command | `.claude/commands/ship.md` | `/ship` in Claude Code drives the whole cycle, including the fix-and-retry loop. |

## One-time setup

1. **Install the Greptile GitHub App** on this repo:
   <https://github.com/apps/greptile-apps> (sign in at
   <https://app.greptile.com> and grant it access to
   `eleakin/code_review_repo`). Make sure PR reviews are enabled — it
   reviews every new PR by default.
2. **GitHub token for the loop driver**: export a `GITHUB_TOKEN` (classic
   PAT with `repo` scope, or fine-grained with PR read/write) in the
   environment where you run Claude Code.
3. **Optional — auto-merge**: in the repo settings, add an Actions
   **variable** `AUTO_MERGE` = `true` to have passing PRs squash-merged
   automatically. Leave it unset to keep merges manual.
4. **Optional — tune the threshold**: edit `SCORE_THRESHOLD` in
   `.github/workflows/greptile-gate.yml` (default `4`).

## Using it

From Claude Code, in this repo:

```
/ship
```

Or manually, after committing on a feature branch:

```bash
export GITHUB_TOKEN=ghp_...
python scripts/greptile_loop.py            # defaults: threshold 4, 15 min timeout
python scripts/greptile_loop.py --threshold 4.5 --timeout 1200
```

Exit code `0` means the gate passed, `1` means Greptile's feedback was
printed and a fix is needed, `2` means setup/timeout trouble.

## Notes

- The score is parsed from Greptile's PR summary (it phrases it as a
  confidence/merge-readiness score out of 5). If Greptile changes its
  wording, update the regex patterns in both the workflow and the script.
- The gate approves with the default `GITHUB_TOKEN`, which cannot approve
  a PR authored by itself — this is only an issue if the PR is opened *by*
  GitHub Actions rather than by your account/PAT.
- Pushing new commits to a PR triggers a fresh Greptile review
  automatically, which re-runs the gate.

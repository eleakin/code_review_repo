# How to: push Claude Code work through the Greptile gate

The short version: **work on a feature branch, then `/ship`.** Greptile
reviews the PR, and a score of **4/5 or higher** gets it auto-approved.

## One-time prerequisites (already done for this repo)

- Greptile GitHub App installed and enabled on the repo
- `.github/workflows/greptile-gate.yml` on the default branch
- Repo setting on: *Settings → Actions → General → "Allow GitHub Actions
  to create and approve pull requests"*
- A `GITHUB_TOKEN` with repo scope exported wherever you run the loop
  script (only needed for the manual flow below)

## The everyday flow

1. **Start Claude Code in this repo** and describe what you want built.
2. **Make sure the work lands on a feature branch**, not `main`:
   ```bash
   git checkout -b feature/my-change
   ```
   (If Claude did the work, just ask it to commit on a feature branch.)
3. **Type `/ship`.** Claude will:
   - commit anything outstanding and push the branch
   - open a PR against `main` (or reuse an open one for that branch)
   - wait for Greptile's review and read the **Confidence Score: X/5**
   - **score ≥ 4** → the gate approves the PR and adds the
     `greptile-approved` label — you just merge
   - **score < 4** → Claude reads Greptile's feedback, fixes the code,
     pushes, and waits for the re-review (up to 5 rounds)

That's it. Pushing new commits to an open PR automatically triggers a
fresh Greptile review, which re-runs the gate.

## Manual flow (without `/ship`)

```bash
git checkout -b feature/my-change
# ...write code, commit...
export GITHUB_TOKEN=ghp_...
python scripts/greptile_loop.py
```

Exit codes: `0` = passed the gate, `1` = below threshold (feedback was
printed — fix and re-run), `2` = setup problem or review timeout.

## Reading the result on GitHub

- Greptile's summary comment on the PR contains the score
  (`Confidence Score: X/5`). On re-reviews it **edits the same comment**
  rather than posting a new one.
- A passing PR gets an approving review from `github-actions` plus the
  `greptile-approved` label.
- A failing PR gets the `greptile-changes-requested` and
  `needs-human-review` labels, and **you are assigned and @mentioned** so
  GitHub notifies you to review it. After your review, re-trigger the
  pipeline by (a) pushing a fix, (b) commenting `@greptileai` on the PR,
  or (c) clicking "Re-trigger Greptile" in Greptile's summary comment.
  A passing re-review clears the failure labels and approves the PR.

## Options

| Want | Do |
|---|---|
| Auto-merge passing PRs | Add repo Actions **variable** `AUTO_MERGE` = `true` |
| Prompt someone else on failures | Add repo Actions **variable** `REVIEW_PROMPT_USER` = their GitHub username (defaults to the repo owner) |
| Stricter/looser gate | Edit `SCORE_THRESHOLD` in `.github/workflows/greptile-gate.yml` |
| Different poll timeout | `python scripts/greptile_loop.py --timeout 1200` |

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| No Greptile review appears | App not enabled for the repo, or review trigger mode changed at app.greptile.com |
| Gate run fails with "not permitted to approve" | The Actions approval setting got turned off again |
| Gate never fires | Workflow file missing from the **default** branch |
| Loop script exits 2 immediately | `GITHUB_TOKEN` not set, or you're on the default branch |

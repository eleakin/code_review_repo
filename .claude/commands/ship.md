---
description: Ship code through the Greptile review gate — push, PR, wait for a 4/5+ score, fix and retry until approved
---

Run the Greptile review loop for the code changes in this session:

1. Make sure all work is committed on a feature branch (never the default
   branch). Write a clear commit message describing the change.
2. Run `python scripts/greptile_loop.py`. It pushes the branch, opens or
   reuses a PR, and waits for Greptile's review score.
3. Interpret the exit code:
   - **0** — Greptile scored the PR ≥ 4/5. The `greptile-gate` workflow
     approves it (and merges if AUTO_MERGE is enabled). Report the PR URL
     and stop.
   - **1** — score was below 4/5. The script printed Greptile's review
     feedback. Read every item, fix the code accordingly, commit with a
     message referencing what was addressed, and go back to step 2.
   - **2** — setup problem or timeout. Diagnose (is GITHUB_TOKEN set? is
     the Greptile app installed?), report the blocker, and stop.
4. Repeat the fix-and-resubmit cycle up to 5 times. If the score still
   hasn't reached 4/5 after 5 attempts, stop and summarize the remaining
   feedback for the user instead of looping forever.

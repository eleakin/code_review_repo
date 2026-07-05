#!/usr/bin/env python3
"""Greptile review loop driver.

Pushes the current branch, opens (or reuses) a PR against the default
branch, waits for Greptile's review, and reports the X/5 score.

Exit codes:
  0 — score >= threshold (approved; the greptile-gate workflow posts the
      formal approval and optionally merges)
  1 — score < threshold; Greptile's review feedback is printed to stdout
      so the calling agent (Claude Code) can fix the code and re-run
  2 — setup/usage error or timed out waiting for a review

Requires: GITHUB_TOKEN env var (repo scope), `git` on PATH.
Usage: python scripts/greptile_loop.py [--threshold 4] [--timeout 900]
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

REPO = "eleakin/code_review_repo"
API = "https://api.github.com"
SCORE_PATTERNS = [
    re.compile(r"confidence\s*score:?\s*\**\s*(\d+(?:\.\d+)?)\s*/\s*5", re.I),
    re.compile(r"score:?\s*\**\s*(\d+(?:\.\d+)?)\s*/\s*5", re.I),
    re.compile(r"(\d+(?:\.\d+)?)\s*/\s*5"),
]


def gh(path, method="GET", body=None):
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not token:
        sys.exit("GITHUB_TOKEN is not set")
    req = urllib.request.Request(
        f"{API}{path}",
        method=method,
        data=json.dumps(body).encode() if body else None,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read() or "null")


def sh(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.strip()


def current_branch():
    return sh("git", "rev-parse", "--abbrev-ref", "HEAD")


def default_branch():
    return gh(f"/repos/{REPO}")["default_branch"]


def push_branch(branch):
    subprocess.run(["git", "push", "-u", "origin", branch], check=True)


def find_or_create_pr(branch, base):
    owner = REPO.split("/")[0]
    prs = gh(f"/repos/{REPO}/pulls?head={owner}:{branch}&state=open")
    if prs:
        return prs[0]
    title = sh("git", "log", "-1", "--pretty=%s")
    return gh(
        f"/repos/{REPO}/pulls",
        "POST",
        {"title": title, "head": branch, "base": base,
         "body": "Automated PR — pending Greptile review gate."},
    )


def extract_score(text):
    for pat in SCORE_PATTERNS:
        m = pat.search(text or "")
        if m:
            return float(m.group(1))
    return None


def greptile_feedback(pr_number, since):
    """Collect Greptile's score and review comments posted after `since`."""
    score, feedback = None, []
    for review in gh(f"/repos/{REPO}/pulls/{pr_number}/reviews?per_page=100"):
        if "greptile" in review["user"]["login"].lower() and review["submitted_at"] >= since:
            s = extract_score(review.get("body"))
            if s is not None:
                score = s
            if review.get("body"):
                feedback.append(review["body"])
    for comment in gh(f"/repos/{REPO}/issues/{pr_number}/comments?per_page=100"):
        if "greptile" in comment["user"]["login"].lower() and comment["created_at"] >= since:
            s = extract_score(comment.get("body"))
            if s is not None:
                score = s
            feedback.append(comment["body"])
    # Inline file comments are the actionable fix list.
    for comment in gh(f"/repos/{REPO}/pulls/{pr_number}/comments?per_page=100"):
        if "greptile" in comment["user"]["login"].lower() and comment["created_at"] >= since:
            feedback.append(f"[{comment['path']}:{comment.get('line', '?')}] {comment['body']}")
    return score, feedback


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--threshold", type=float, default=4.0)
    ap.add_argument("--timeout", type=int, default=900, help="seconds to wait for review")
    ap.add_argument("--poll", type=int, default=30, help="poll interval in seconds")
    args = ap.parse_args()

    branch = current_branch()
    base = default_branch()
    if branch == base:
        sys.exit(f"Refusing to run on the default branch ({base}); create a feature branch first.")

    since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    print(f"Pushing {branch}...")
    push_branch(branch)
    pr = find_or_create_pr(branch, base)
    print(f"PR #{pr['number']}: {pr['html_url']}")
    print(f"Waiting for Greptile review (timeout {args.timeout}s)...")

    deadline = time.time() + args.timeout
    while time.time() < deadline:
        score, feedback = greptile_feedback(pr["number"], since)
        if score is not None:
            print(f"\nGreptile score: {score}/5 (threshold {args.threshold})")
            if score >= args.threshold:
                print("PASSED — the greptile-gate workflow will approve the PR.")
                return 0
            print("\nFAILED — fix the following Greptile feedback, commit, and re-run:\n")
            for item in feedback:
                print(f"---\n{item}\n")
            return 1
        time.sleep(args.poll)

    print("Timed out waiting for a Greptile review. Is the Greptile GitHub App "
          "installed on this repo and enabled for PR reviews?")
    return 2


if __name__ == "__main__":
    sys.exit(main())

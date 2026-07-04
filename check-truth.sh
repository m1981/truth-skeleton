#!/usr/bin/env bash
# check-truth.sh -- pre-commit / CI gate for the truth ledger.
#
# INV-A: .truth/claims.jsonl is append-only. Any staged change that deletes
#        or modifies an existing line fails the commit. (Modifying a line
#        shows up in the diff as a deletion + addition, so blocking
#        deletions blocks both.)
# INV-B: every staged record satisfies the schema (via `truth validate`).
#
# Wire it in: call this from your pre-commit hook (or check-governance.sh).
# Exit codes: 0 ok / 1 governance failure / 2 environment problem.

set -u
LEDGER=".truth/claims.jsonl"
TRUTH="scripts/truth"

# Nothing staged for the ledger -> nothing to check.
if ! git diff --cached --name-only -- "$LEDGER" | grep -q .; then
  exit 0
fi

# INV-A: no deleted lines. `git diff --cached` prefixes removed lines with
# a single '-' (the '---' file header is excluded by [^-]).
if git diff --cached -- "$LEDGER" | grep -Eq '^-[^-]'; then
  echo "check-truth: INV-A violation -- $LEDGER is append-only." >&2
  echo "  An existing record was modified or deleted. To change a claim's" >&2
  echo "  status, append a verdict or invalidation record instead." >&2
  exit 1
fi

# INV-B: validate the staged version of the ledger, not the worktree.
if [ ! -x "$TRUTH" ] && [ ! -f "$TRUTH" ]; then
  echo "check-truth: cannot find $TRUTH (exit 2: environment, not governance)" >&2
  exit 2
fi
if ! git show ":$LEDGER" | python3 "$TRUTH" validate --stdin; then
  echo "check-truth: INV-B violation -- staged ledger fails schema validation." >&2
  exit 1
fi

exit 0

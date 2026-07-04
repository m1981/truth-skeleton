#!/usr/bin/env bash
# truth-canary.sh -- seeded-fault acceptance suite.
#
# A truth-maintenance system cannot be validated on honest input; the only
# meaningful test is planting known lies and measuring detection. This
# script builds a throwaway git repo and runs three deterministic canaries:
#
#   FAULT A (INV-A): mutate a historical ledger line     -> commit blocked
#   FAULT B (INV-C): commit touches a claim's evidence   -> claim goes stale
#   FAULT C (T1)   : recorded evidence no longer matches -> recheck diverges
#
# All three must be CAUGHT for the suite to pass. Run weekly; a detection
# system that has caught nothing in months is either guarding a solved
# problem or broken, and without canaries you cannot tell which.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
PASS=0; FAIL=0

say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); say "  CAUGHT: $*"; }
miss() { FAIL=$((FAIL+1)); say "  MISSED: $*"; }

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# ---- sandbox repo -----------------------------------------------------
cd "$TMP"
git init -q .
git config user.email canary@truth.local
git config user.name  truth-canary
mkdir -p scripts .truth
cp "$HERE/truth" scripts/truth
cp "$HERE/check-truth.sh" scripts/check-truth.sh
chmod +x scripts/truth scripts/check-truth.sh
echo "hello" > watched.txt
echo "v1"    > fabricated.txt
git add -A && git commit -qm "canary: init"

T="python3 scripts/truth"
export TRUTH_ACTOR=canary TRUTH_SESSION=s-canary

# ---- FAULT B: causal invalidation ------------------------------------
say "FAULT B: commit touching evidence paths must mark the claim stale"
CID_B=$($T claim "watched.txt says hello" --class VERIFIED \
        --evidence-cmd "cat watched.txt" --paths "watched.txt" --tier P0)
$T verdict "$CID_B" --recheck >/dev/null   # honest claim -> live
git add .truth/claims.jsonl && git commit -qm "canary: file claim B"
echo "changed" >> watched.txt
git add watched.txt && git commit -qm "canary: mutate evidence path"
$T invalidate-scan --quiet
if $T list --stale --json | grep -q "$CID_B"; then
  ok "claim $CID_B flipped to stale after evidence path changed"
else
  miss "claim $CID_B still trusted after its evidence changed"
fi

# ---- FAULT C: fabricated / rotted evidence ----------------------------
say "FAULT C: recheck must diverge when reality no longer matches the record"
CID_C=$($T claim "fabricated.txt says v1" --class VERIFIED \
        --evidence-cmd "cat fabricated.txt" --paths "fabricated.txt" --tier P1)
echo "v2" > fabricated.txt   # reality drifts; the recorded hash is now a lie
OUT=$($T verdict "$CID_C" --recheck)
if echo "$OUT" | grep -q "diverge"; then
  ok "recheck flagged hash mismatch on $CID_C"
else
  miss "recheck accepted stale evidence on $CID_C ($OUT)"
fi

# ---- FAULT A: append-only enforcement ---------------------------------
say "FAULT A: mutating a historical ledger line must block the commit"
git add -A && git commit -qm "canary: settle ledger before tamper"
sed -i '1s/claim/CLAIM_TAMPERED/' .truth/claims.jsonl
git add .truth/claims.jsonl
if bash scripts/check-truth.sh; then
  miss "check-truth.sh allowed a mutated historical record"
else
  ok "check-truth.sh blocked the tampered ledger"
fi
git checkout -q -- .truth/claims.jsonl

# ---- verdict ----------------------------------------------------------
say ""
say "canary result: $PASS caught, $FAIL missed"
if [ "$FAIL" -gt 0 ]; then
  say "CANARY FAILED -- the immune system has a hole."
  exit 1
fi
say "ALL CANARIES CAUGHT."

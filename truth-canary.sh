#!/usr/bin/env bash
# truth-canary.sh v0.2 -- seeded-fault acceptance suite.
#
# Every gap fix ships with the lie that proves it works. Ten faults:
#
#   A (INV-A) mutate a historical ledger line        -> commit blocked
#   B (INV-C) commit touches evidence paths          -> claim goes stale
#   C (T1)    recorded evidence no longer reproduces -> recheck diverges
#   D (G10)   claim past its ttl_days                -> expired to stale
#   E (G14)   anchor commit erased by history rewrite-> stale, reason logged
#   F (G1)    VERIFIED claim in a zero-commit repo   -> refused at intake
#   G (G6)    nondeterministic evidence command      -> refused at intake
#   H (G12)   verdict after retraction               -> retraction holds
#   I (G8)    near-duplicate of an active claim      -> refused at intake
#   J (ADR-001) issue premised on a stale claim      -> HELD by truth ready
#
# Plus a doctor round-trip (G4): doctor must FAIL on an unwired repo and
# PASS after wiring. Run weekly. Uses the TRUTH_NOW test hook for D.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0
say()  { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); say "  CAUGHT: $*"; }
miss() { FAIL=$((FAIL+1)); say "  MISSED: $*"; }

TMP1="$(mktemp -d)"; TMP2="$(mktemp -d)"; TMP3="$(mktemp -d)"
cleanup() { rm -rf "$TMP1" "$TMP2" "$TMP3"; }
trap cleanup EXIT

mkrepo() { # $1 = dir
  cd "$1"
  git init -q -b main .
  git config user.email canary@truth.local
  git config user.name  truth-canary
  mkdir -p scripts .truth prompts
  touch .truth/claims.jsonl
  cp "$HERE/truth" scripts/truth
  cp "$HERE/check-truth.sh" scripts/check-truth.sh
  chmod +x scripts/truth scripts/check-truth.sh
}
T="python3 scripts/truth"
export TRUTH_ACTOR=canary TRUTH_SESSION=s-canary

# ======================================================= sandbox 1 (main)
mkrepo "$TMP1"
echo "hello" > watched.txt
echo "v1"    > fabricated.txt
printf 'verifier header\n---\nVERIFIER BODY\n' > prompts/truth-verifier.md
git add -A && git commit -qm "canary: init"

# ---- doctor round-trip (G4) -------------------------------------------
say "DOCTOR (G4): must FAIL on an unwired repo, PASS after wiring"
if $T doctor >/dev/null 2>&1; then
  miss "doctor passed a repo with no hooks, no gitattributes, no discovery"
else
  ok "doctor failed the unwired repo"
fi
echo ".truth/claims.jsonl merge=union" >> .gitattributes
printf '#!/usr/bin/env bash\nexec bash scripts/check-truth.sh\n' > .git/hooks/pre-commit
printf '#!/usr/bin/env bash\npython3 scripts/truth invalidate-scan --quiet\n' > .git/hooks/post-merge
chmod +x .git/hooks/pre-commit .git/hooks/post-merge
printf '# Agents\nTruth ledger: use scripts/truth (see .truth/README.md)\n' > AGENTS.md
git add -A && git commit -qm "canary: wire installation" --no-verify
if $T doctor >/dev/null 2>&1; then
  ok "doctor passed the wired repo"
else
  miss "doctor failed a correctly wired repo"; $T doctor || true
fi

# ---- FAULT B: causal invalidation --------------------------------------
say "FAULT B (INV-C): commit touching evidence paths must mark the claim stale"
CID_B=$($T claim "watched.txt says hello" --class VERIFIED \
        --evidence-cmd "cat watched.txt" --paths "watched.txt" --tier P0)
$T verdict "$CID_B" --recheck >/dev/null
git add .truth/claims.jsonl && git commit -qm "canary: claim B" --no-verify
echo "changed" >> watched.txt
git add watched.txt && git commit -qm "canary: mutate evidence" --no-verify
$T invalidate-scan --quiet
if $T list --stale --json | grep -q "$CID_B"; then
  ok "claim $CID_B stale after evidence path changed"
else
  miss "claim $CID_B still trusted after its evidence changed"
fi

# ---- FAULT C: rotted evidence -------------------------------------------
say "FAULT C (T1): recheck must diverge when reality no longer matches"
CID_C=$($T claim "fabricated.txt says v1" --class VERIFIED \
        --evidence-cmd "cat fabricated.txt" --paths "fabricated.txt" --tier P1)
echo "v2" > fabricated.txt
if $T verdict "$CID_C" --recheck | grep -q diverge; then
  ok "recheck flagged hash mismatch on $CID_C"
else
  miss "recheck accepted stale evidence on $CID_C"
fi

# ---- FAULT D: TTL expiry (G10) ------------------------------------------
say "FAULT D (G10): claim past its ttl_days must expire to stale"
CID_D=$(TRUTH_NOW="2026-06-01T00:00:00+00:00" $T claim \
        "external API allows 100 req/min" --class INFERRED \
        --basis "vendor docs read 2026-06-01" --ttl-days 7 --tier P1)
$T invalidate-scan --quiet
if $T list --stale --json | grep -q "$CID_D"; then
  ok "claim $CID_D expired after ttl elapsed"
else
  miss "ttl_days is still a dead field: $CID_D outlived its ttl"
fi

# ---- FAULT G: nondeterministic evidence (G6) ----------------------------
say "FAULT G (G6): nondeterministic evidence command must be refused"
if $T claim "the clock ticks" --class VERIFIED \
     --evidence-cmd "date +%s%N" --paths "watched.txt" --tier P2 2>/dev/null; then
  miss "intake accepted nondeterministic evidence"
else
  ok "intake refused nondeterministic evidence"
fi

# ---- FAULT H: retraction is terminal (G12) ------------------------------
say "FAULT H (G12): a verdict after retraction must not resurrect the claim"
CID_H=$($T claim "this claim is simply wrong" --tier P2)
$T verdict "$CID_H" retracted --basis "human: factually wrong, tombstoned" >/dev/null
if $T verdict "$CID_H" agree --basis "resurrection attempt" >/dev/null 2>&1; then
  miss "tool accepted a verdict on a retracted claim"
else
  ok "tool refused a verdict on retracted $CID_H"
fi
if $T list --retracted --json | grep -q "$CID_H" && \
   ! $T list --live --json | grep -q "$CID_H"; then
  ok "fold holds $CID_H as retracted (terminal)"
else
  miss "retracted claim $CID_H changed status"
fi

# ---- FAULT I: duplicate claim (G8) ---------------------------------------
say "FAULT I (G8): near-duplicate of an active claim must be refused"
$T claim "the payments module handles all currency conversion logic" --tier P2 >/dev/null
if $T claim "the payments module handles currency conversion" --tier P2 2>/dev/null; then
  miss "intake accepted a near-duplicate active claim"
else
  ok "intake refused the near-duplicate"
fi
if DUP=$($T claim "the payments module handles currency conversion" \
         --tier P2 --duplicate-ok 2>/dev/null); then
  ok "--duplicate-ok override works ($DUP)"
else
  miss "--duplicate-ok override rejected a legitimate refile"
fi

# ---- FAULT J: epistemic readiness (ADR-001) ------------------------------
say "FAULT J (ADR-001): issue premised on a stale claim must be HELD"
cat > bd <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "ready" ]; then
  echo '[{"id":"bd-x1","title":"issue on stale premise"},{"id":"bd-x2","title":"issue on live premise"}]'
fi
EOF
chmod +x bd
CID_L=$($T claim "watched.txt now says hello changed" --class VERIFIED \
        --evidence-cmd "cat watched.txt" --paths "watched.txt" --tier P1 --duplicate-ok)
$T verdict "$CID_L" --recheck >/dev/null
$T premise bd-x1 "$CID_B" >/dev/null    # stale premise
$T premise bd-x2 "$CID_L" >/dev/null    # live premise
READY_OUT=$(PATH="$PWD:$PATH" $T ready)
if echo "$READY_OUT" | grep -q "^HELD bd-x1" && echo "$READY_OUT" | grep -q "^bd-x2"; then
  ok "bd-x1 held on stale premise; bd-x2 passed on live premise"
else
  miss "ready join wrong: $READY_OUT"
fi

# ---- FAULT A: append-only (last: it tampers with the ledger) -------------
say "FAULT A (INV-A): mutating a historical ledger line must block the commit"
git add -A && git commit -qm "canary: settle ledger" --no-verify
sed -i '1s/claim/CLAIM_TAMPERED/' .truth/claims.jsonl
git add .truth/claims.jsonl
if bash scripts/check-truth.sh >/dev/null 2>&1; then
  miss "check-truth.sh allowed a mutated historical record"
else
  ok "check-truth.sh blocked the tampered ledger"
fi
git checkout -q -- .truth/claims.jsonl

# ======================================================= sandbox 2 (G1)
say "FAULT F (G1): VERIFIED claim in a zero-commit repo must be refused"
mkrepo "$TMP2"
echo x > f.txt   # exists on disk, but nothing is committed
if $T claim "f.txt exists" --class VERIFIED --evidence-cmd "cat f.txt" \
     --paths "f.txt" --tier P0 2>/dev/null; then
  miss "intake anchored a claim in a repo with no commits"
else
  ok "intake refused: no commits, no anchor"
fi

# ======================================================= sandbox 3 (G14)
say "FAULT E (G14): erased anchor commit must invalidate, with reason"
mkrepo "$TMP3"
echo data > g.txt
git add -A && git commit -qm "canary: init"
CID_E=$($T claim "g.txt says data" --class VERIFIED \
        --evidence-cmd "cat g.txt" --paths "g.txt" --tier P0)
$T verdict "$CID_E" --recheck >/dev/null
git checkout -q --orphan rewritten
git add -A && git commit -qm "canary: history rewritten"
git branch -D main -q
git reflog expire --expire=now --expire-unreachable=now --all
git gc --prune=now -q
$T invalidate-scan --quiet
if $T list --stale --json | grep -q "$CID_E" && \
   grep -q "anchor unreachable" .truth/claims.jsonl; then
  ok "claim $CID_E stale with reason 'anchor unreachable'"
else
  miss "history rewrite left $CID_E trusted or unexplained"
fi

# ---- verdict --------------------------------------------------------------
say ""
say "canary result: $PASS caught, $FAIL missed"
if [ "$FAIL" -gt 0 ]; then
  say "CANARY FAILED -- the immune system has a hole."
  exit 1
fi
say "ALL CANARIES CAUGHT."

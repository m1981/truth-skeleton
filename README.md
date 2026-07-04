# .truth — append-only claims ledger (v0.2)

> Reader: any agent or human about to assert, trust, or re-verify a fact about this repository | Enables: filing a claim in one command, and knowing which claims are still live before acting on them | Update-trigger: the record schema, invariants, or CLI contract change

A plain-JSONL truth layer that lives beside Beads (E1: Beads is read-only
from here). Work records answer *what to do*; this ledger answers *what is
known and how*. The join — `truth ready` — returns Beads-ready issues whose
premises still hold (semantics: docs/adr/001).

v0.2 closes the USE-CASES gap register: G1 G3 G4 G6 G8 G10 G12 G13 G14 G15
fixed or decided; G2 handled in HANDOFF; G5 G7 G9 G11 documented below.

## Layout

    .truth/claims.jsonl                the ledger (append-only, event-sourced)
    .truth/schema/claims.schema.json   the formal contract (survives fires)
    scripts/truth                      the CLI (stdlib Python 3.9+, POSIX)
    scripts/check-truth.sh             pre-commit/CI gate: INV-A + INV-B
    scripts/truth-canary.sh            10 seeded faults (run weekly)
    prompts/truth-verifier.md          fixed verifier prompt (use `truth dispatch`)
    docs/adr/001-*.md                  premise-validity decision (G15)
    examples/github-actions-truth.yml  CI equivalents of both hooks (G3)

## Install (day 1)

1. Copy the files above into your repo, `chmod +x scripts/truth scripts/*.sh`,
   `touch .truth/claims.jsonl`.
2. Append to `.gitattributes`: `.truth/claims.jsonl merge=union`
3. Wire hooks: pre-commit calls `scripts/check-truth.sh`; post-merge runs
   `scripts/truth invalidate-scan --quiet`. No hooks available? Use the CI
   workflow in examples/ instead — one of the two MUST exist.
4. Add the discovery snippet (below) to EVERY instruction file your agent
   runtimes load — AGENTS.md, CLAUDE.md, .cursorrules, copilot-instructions
   (G2: a snippet in a file no runtime reads is silent death).
5. `scripts/truth doctor` — installation must pass (G4: the canary tests
   the scripts in a sandbox; only doctor tests YOUR wiring).
6. `bash scripts/truth-canary.sh` — ten faults, all CAUGHT, or stop.

## Discovery snippet (E4 — the friction budget is four lines)

    This project keeps a truth ledger. Before relying on a repository fact,
    check it: `scripts/truth list --live`. When you verify a fact, file it:
    `scripts/truth claim "<fact>" --class VERIFIED --evidence-cmd "<cmd>" --paths "<globs>" --tier P1`
    Facts about the world outside the repo: add `--ttl-days N` instead of --paths.
    Never edit .truth/claims.jsonl directly; status changes are new records.

## The fold (how status is derived)

Never stored, never edited; replay the ledger in file order, last event
wins, one terminal state:

    no events                 -> unverified
    verdict agree             -> live
    verdict diverge           -> diverged       (queue, any tier)
    verdict cannot_verify     -> cannot_verify  (queue if P0)
    verdict retracted         -> retracted      (TERMINAL tombstone, G12;
                                                 humans only, later events ignored)
    invalidation              -> stale          (queue if P0/P1)

`truth queue` shows each item's age in days (G13); `truth doctor` warns
when items sit past 14 days.

## Intake protections (what `truth claim` refuses)

- VERIFIED with no commits in the repo — nothing to anchor to (G1).
- VERIFIED with neither --paths nor --ttl-days — uninvalidatable (G10).
- Nondeterministic evidence commands — two intake runs must hash the same;
  skip with `--single-run` for expensive commands, accepting the
  false-divergence risk explicitly (G6).
- Near-duplicates (token overlap >= 0.6) of ACTIVE claims — override with
  `--duplicate-ok`; corrections of stale/diverged/retracted claims are
  always allowed (G8).

## Invalidation triggers (what `invalidate-scan` catches)

Evidence paths touched since the anchor commit (INV-C); ttl_days elapsed —
for facts git cannot see, like host versions or vendor APIs (G10); anchor
commit unreachable after rebase/squash/gc — fails toward distrust with
reason "anchor unreachable" (G14); and any other diff failure, same policy.

## Verification (E5 + G11)

`scripts/truth dispatch <id>` prints the exact verifier context — fixed
prompt plus claim record, nothing else — to feed a fresh session.
Deterministic recheck rules: hash mismatch = diverge; command not found
(exit 127) = cannot_verify; deleted evidence files = diverge. Verifiers may
not retract; retraction is a human decision.

## Invariants (each names its refutation; all canary-gated)

| ID    | Property | Falsified by | Canary |
|-------|----------|--------------|--------|
| INV-A | Ledger is append-only | one mutated historical line committed | A |
| INV-B | VERIFIED claims carry command, hash, anchor, paths-or-ttl | one bare VERIFIED accepted | F, intake |
| INV-C | Evidence-path changes mark claims stale before re-trust | one stale claim rendered live | B |
| INV-D | Recheck detects evidence that no longer reproduces | one hash mismatch scored agree | C |
| INV-E | TTL'd claims expire | one claim outliving its ttl_days | D |
| INV-F | History rewrites invalidate, with reason | one orphaned anchor still trusted | E |
| INV-G | Retraction is terminal | one resurrected tombstone | H |
| INV-H | Broken premises hold work | one issue ready on a stale premise | J |

## Daily operation

Daily (~2 min): `truth queue` — empty means carry on. Weekly (~30 s):
`truth-canary.sh`. After any repo surgery (rebase spree, hook changes,
new agent runtime): `truth doctor`. Monthly: re-audit a few fresh
sessions' claims by hand against your day-0 baseline — if false-VERIFIED
rates haven't moved, the green checkmarks mean nothing.

## Test hook

`TRUTH_NOW=<iso8601>` overrides the clock (canary uses it for TTL faults).
Never set it in production; a backdated claim is a forged timestamp.

## Remaining accepted limits (stated so the layer never overstates itself)

Recheck proves reproducibility, not sound interpretation — a correct grep
with a wrong conclusion passes INV-D and must be caught by the semantic
verifier or the human. Side-effectful evidence is undetectable at intake
(G7): keep to the evidence vocabulary — grep, find, ls, test runs, type
checks. Verifier/author priors correlate; decorrelate by evidence modality,
not verifier count (G11 is scripted-context, not enforced isolation).
Concurrent same-machine appends rely on POSIX O_APPEND atomicity (G9:
folklore; revisit under real parallelism). POSIX-only (G5). `truth ready`
requires Beads; on contract drift it fails loudly — fall back to
`bd ready` + `truth list --live`.

## Growth gates (do not build early)

| Trigger fires | Then build |
|---------------|------------|
| Recheck too slow/narrow in practice | session-manifest attestation (E2 upgrade) |
| First false VERIFIED recheck could not catch | attestation becomes P0 |
| Ledger unreadable at agent context limits (~500+ records) | pruned live-view export; git history keeps the log |
| Warning fatigue on unverified premises | supersede ADR-001 (fallback noted there) |
| First doc worth generating from claims | docs-as-rendered-views, one document first |

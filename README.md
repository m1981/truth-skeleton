# .truth — append-only claims ledger

> Reader: any agent or human about to assert, trust, or re-verify a fact about this repository | Enables: filing a claim in one command, and knowing which claims are still live before acting on them | Update-trigger: the record schema, invariants, or CLI contract change

A plain-JSONL truth layer that lives beside Beads (E1: Beads is read-only
from here). Work records answer *what to do*; this ledger answers *what is
known and how*. The join — `truth ready` — returns Beads-ready issues whose
premises still hold.

## Layout

    .truth/claims.jsonl          the ledger (append-only, event-sourced)
    .truth/schema/claims.schema.json   the formal contract (survives fires)
    scripts/truth                the CLI (stdlib Python, no dependencies)
    scripts/check-truth.sh       pre-commit/CI gate: INV-A + INV-B
    scripts/truth-canary.sh      seeded-fault acceptance suite (run weekly)
    prompts/truth-verifier.md    fixed prompt for the independent verifier

## Install (day 1)

1. Copy the files above into your repo, `chmod +x scripts/truth scripts/*.sh`.
2. Append to `.gitattributes` (E3 — concurrent branches merge by union):

       .truth/claims.jsonl merge=union

3. Call `scripts/check-truth.sh` from your pre-commit hook (or add it as
   check 5 in check-governance.sh). Exit 1 = governance failure, 2 = env.
4. Add a post-merge hook (or CI step) for causal invalidation:

       scripts/truth invalidate-scan --quiet

5. Run `scripts/truth-canary.sh` once now, then weekly. Three seeded
   faults, three CAUGHT lines, or the layer is not installed.

## AGENTS.md snippet (E4 — the friction budget is three lines)

    This project keeps a truth ledger. Before relying on a repository fact,
    check it: `scripts/truth list --live`. When you verify a fact, file it:
    `scripts/truth claim "<fact>" --class VERIFIED --evidence-cmd "<cmd>" --paths "<globs>" --tier P1`

## The fold (how status is derived)

Status is never stored or edited; it is computed by replaying the ledger in
file order — last event wins:

    no events                 -> unverified
    verdict agree             -> live
    verdict diverge           -> diverged      (human queue, any tier)
    verdict cannot_verify     -> cannot_verify
    invalidation              -> stale         (human queue if P0/P1)

`truth queue` lists exactly what a human must look at: divergence plus
stale P0/P1. Everything else waits.

## Invariants (each names its refutation)

| ID    | Property | Falsified by | Enforced by |
|-------|----------|--------------|-------------|
| INV-A | Ledger is append-only | one mutated historical line committed | check-truth.sh (FAULT A) |
| INV-B | VERIFIED claims carry command, hash, anchor commit, paths | one bare VERIFIED accepted | truth claim + validate (intake and gate) |
| INV-C | Evidence-path changes mark claims stale before re-trust | one stale claim rendered live | invalidate-scan (FAULT B) |
| INV-D | Recheck detects evidence that no longer reproduces | one hash mismatch scored agree | verdict --recheck (FAULT C) |

## Ratified edges (change via superseding ADR, not by edit)

E1 Beads read-only, truth side owns all cross-links (`premise` records
reference `bd-*` ids as opaque strings; dangling ids surface as broken
premises, never crashes). E2 re-execution instead of attestation for v0 —
VERIFIED evidence must be a re-runnable command; side-effectful evidence can
only earn cannot_verify. E3 event-sourced append-only with union merge.
E4 one-command claim filing. E5 verifier and queue are consumers of the
fold, not components.

## Growth gates (do not build early)

| Trigger fires | Then build |
|---------------|------------|
| Recheck too slow or too narrow in practice | session-manifest attestation (the E2 upgrade) |
| First false VERIFIED that recheck could not catch | attestation becomes P0 |
| Ledger unreadable at agent context limits (~500+ records) | pruned live-view export; git history keeps the log |
| First doc worth generating from claims | docs-as-rendered-views, one document first |
| One month of real use | re-audit fresh sessions against your day-0 baseline; if false-VERIFIED rates have not moved, the green checkmarks mean nothing |

## Known limits (stated so the layer never overstates its guarantees)

Recheck proves reproducibility, not sound interpretation — a correct grep
with a wrong conclusion passes INV-D and must be caught by the semantic
verifier or the human. Verifier and author share priors (correlated-error
risk); decorrelate by evidence modality, not verifier count. `truth ready`
requires Beads; without it, use `truth list --live` directly.

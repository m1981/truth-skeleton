# HANDOFF — install the truth layer v0.2 into this repository

> Reader: a fresh agent session with no prior context | Enables: wiring the truth layer into this repo in one session, verified by doctor + ten seeded faults | Update-trigger: the layer's file layout or CLI contract changes

You are installing a small append-only claims ledger ("truth layer") that
lives beside the Beads issue tracker. Everything ships in the
`truth-skeleton-v0.2/` folder the human gives you with this file.

Rules for this session: follow the repo's AGENT-CHARTER.md if present
(evidence tags, no scope creep). Do ONLY the steps below. Do not refactor
the scripts, rename anything, or add features. One commit per step. If a
step fails, stop and report — do not improvise around it.

## Step 0 — ask the human ONE question first (G2)

"Which agent runtimes touch this repo?" (Claude Code, Cursor, Copilot,
Codex, a custom harness...). You need this for Step 4: the discovery
snippet must land in EVERY instruction file those runtimes actually load.
A snippet in a file no runtime reads is silent death, and you cannot
detect that from inside the repo.

## Step 1 — place the files

Copy from `truth-skeleton-v0.2/` into the repo root, merging directories:

    scripts/truth
    scripts/check-truth.sh
    scripts/truth-canary.sh
    .truth/schema/claims.schema.json
    .truth/README.md
    prompts/truth-verifier.md
    docs/adr/001-premise-validity-semantics.md
    examples/github-actions-truth.yml   (reference; wired only in Step 3b)

Then: `chmod +x scripts/truth scripts/check-truth.sh scripts/truth-canary.sh`
and `touch .truth/claims.jsonl`.

If the repo has an existing docs/adr or adr folder with its own numbering,
renumber the ADR file to the next free number and update its filename —
do not create a second ADR sequence.

## Step 2 — merge rule

Append to `.gitattributes` (create if absent):

    .truth/claims.jsonl merge=union

## Step 3 — enforcement (hooks, or CI — one MUST exist)

3a. Hooks path: add `scripts/check-truth.sh` to the pre-commit hook (or as
a check in an existing check-governance.sh; respect exit codes 1=block,
2=environment, also block). Create `.git/hooks/post-merge`:

    #!/usr/bin/env bash
    scripts/truth invalidate-scan --quiet

Make both executable.

3b. If `.git/hooks` is unusable in this environment (bare repo, CI-only):
copy `examples/github-actions-truth.yml` to `.github/workflows/truth.yml`
(adjust branch names) instead, and say so in your report.

## Step 4 — discovery (per Step 0's answer)

Append the snippet below to every instruction file the named runtimes load
(AGENTS.md, CLAUDE.md, .cursorrules, .github/copilot-instructions.md, ...),
creating files that don't exist:

    ## Truth ledger
    This project keeps a truth ledger. Before relying on a repository fact,
    check it: `scripts/truth list --live`. When you verify a fact, file it:
    `scripts/truth claim "<fact>" --class VERIFIED --evidence-cmd "<cmd>" --paths "<globs>" --tier P1`
    Facts about the world outside the repo: add `--ttl-days N` instead of --paths.
    Never edit .truth/claims.jsonl directly; status changes are new records.

## Step 5 — acceptance gates (not done until ALL pass)

1. `scripts/truth doctor` exits 0 — this checks YOUR installation:
   commits exist, ledger validates, union rule present, both enforcement
   points wired, discovery snippet found. (If you chose 3b, the two hook
   checks will FAIL by design — state this in the report and confirm the
   workflow file exists instead.)
2. `bash scripts/truth-canary.sh` prints "ALL CANARIES CAUGHT." (ten
   seeded faults in throwaway sandboxes; touches nothing in this repo).
3. Append-only round-trip in THIS repo: file
   `scripts/truth claim "install smoke test" --tier P2`, stage, confirm the
   gate PASSES; edit that line in place, stage, confirm the gate BLOCKS;
   restore with `git checkout -- .truth/claims.jsonl`.
4. File the first REAL claim: one fact you can verify right now, filed as
   VERIFIED with a re-runnable, deterministic evidence command. Report the
   id. If your first candidate command is refused as nondeterministic,
   that is the layer working — pick a deterministic formulation, do not
   reach for --single-run.
5. Dispatch round-trip: `scripts/truth dispatch <that id>` prints the
   verifier prompt + claim record. Do not act on it; just confirm output.
6. If `bd` is installed: run `scripts/truth ready` once and report whether
   the join worked or errored (Beads contract drift is a KNOWN E1 risk —
   report it, do not patch around it).

Report per gate with evidence tags (VERIFIED = you ran it this session).
Commit: `chore: install truth layer v0.2 -- doctor green, canary 10/10`

## Daily operation (tell the human this once, at the end)

Daily ~2 min: `scripts/truth queue` (items show age; anything past 14 days
is attention debt). Weekly ~30 s: the canary. After repo surgery or new
runtimes: `scripts/truth doctor`. Monthly: hand-audit a few fresh sessions'
claims against the day-0 baseline.

## What NOT to do

- No features, no daemons, no colors, no refactors.
- Do not touch `.beads/` — Beads is read-only from here (E1).
- Do not set TRUTH_NOW outside the canary — it forges timestamps.
- Do not mark any gate passed without running it this session.

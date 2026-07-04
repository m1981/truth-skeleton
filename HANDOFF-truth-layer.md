# HANDOFF — install the truth layer into this repository

> Reader: a fresh agent session with no prior context | Enables: wiring the truth-skeleton files into this repo in one session, verified by seeded faults | Update-trigger: the skeleton's file layout or CLI contract changes

You are installing a small append-only claims ledger ("truth layer") that
lives beside the Beads issue tracker. It records facts about the repo with
evidence, detects when later commits invalidate them, and surfaces disputes
to the human. Everything you need ships in the `truth-skeleton/` folder the
human gives you alongside this file.

Rules for this session: follow the repo's AGENT-CHARTER.md if present
(evidence tags, no scope creep). Do ONLY the steps below. Do not refactor
the scripts, do not rename anything, do not add features. One commit per
step. If a step fails, stop and report — do not improvise around it.

## Step 1 — place the files

Copy from `truth-skeleton/` into the repo root, merging with existing dirs:

    scripts/truth
    scripts/check-truth.sh
    scripts/truth-canary.sh
    .truth/schema/claims.schema.json
    prompts/truth-verifier.md
    (the skeleton README.md -> save as .truth/README.md)

Then: `chmod +x scripts/truth scripts/check-truth.sh scripts/truth-canary.sh`
Create an empty ledger: `touch .truth/claims.jsonl`

## Step 2 — merge rule (append-only union merge)

Append this line to `.gitattributes` (create the file if absent):

    .truth/claims.jsonl merge=union

## Step 3 — hooks

Pre-commit: if the repo has `scripts/check-governance.sh` or an existing
pre-commit hook, add a call to `scripts/check-truth.sh` at the end (respect
its exit codes: 1 = block commit, 2 = environment problem, also block).
If there is no pre-commit hook, install a two-line shim at
`.git/hooks/pre-commit`:

    #!/usr/bin/env bash
    exec bash scripts/check-truth.sh

Post-merge (causal invalidation): create `.git/hooks/post-merge`:

    #!/usr/bin/env bash
    scripts/truth invalidate-scan --quiet

Make both hooks executable.

## Step 4 — agent instructions

Append to AGENTS.md (and CLAUDE.md if the repo uses one):

    ## Truth ledger
    This project keeps an append-only claims ledger beside Beads.
    - Before relying on a repository fact, check it: `scripts/truth list --live`
    - When you verify a fact, file it in one command:
      `scripts/truth claim "<fact>" --class VERIFIED --evidence-cmd "<re-runnable cmd>" --paths "<globs>" --tier P1`
    - Facts you infer but did not verify: `--class INFERRED --basis "<why>"`
    - Never edit .truth/claims.jsonl directly; status changes are new records.

## Step 5 — acceptance gates (you are not done until all pass)

1. `bash scripts/truth-canary.sh` prints exactly three CAUGHT lines and
   "ALL CANARIES CAUGHT." (runs in a throwaway sandbox; touches nothing).
2. `scripts/truth validate` exits 0 on the (empty) ledger.
3. Commit a scratch mutation test: append any valid record via
   `scripts/truth claim "install smoke test" --tier P2`, stage it, confirm
   the pre-commit hook PASSES; then edit that line in place, stage, confirm
   the hook BLOCKS; then `git checkout -- .truth/claims.jsonl` to restore.
4. File the first REAL claim: pick one fact you can verify about this repo
   right now (e.g. "no file imports X", "test suite passes") and file it as
   VERIFIED with a re-runnable evidence command. Report its id.
5. If `bd` is installed: run `scripts/truth ready` once and report whether
   the JSON join worked or errored (a shape mismatch with the current Beads
   version is a KNOWN RISK — report it, do not patch around it).

Report results per gate with evidence tags (VERIFIED = you ran it this
session). Then commit everything with message:
`chore: install truth layer (append-only claims ledger) — canary green`

## Daily operation (tell the human this, once, at the end)

- Daily (~2 min): `scripts/truth queue` — empty means carry on; items mean
  a claim diverged or went stale and needs a human decision.
- Weekly (~30 s): `bash scripts/truth-canary.sh` — three CAUGHT or broken.
- Everything else is automatic (hooks) or done by agents as they work.
- After one month: re-audit a few fresh sessions' claims by hand against
  today as baseline; if false-VERIFIED rates haven't dropped, say so loudly.

## Optional — Step 6: turn this into a Copier template

Only if the human asked for the template repo. In a NEW repo (e.g.
`doc-governance-template`), lay out:

    copier.yml
    template/
      scripts/truth.jinja                (verbatim; no variables needed -> copy as-is without .jinja)
      scripts/check-truth.sh
      scripts/truth-canary.sh
      .truth/schema/claims.schema.json
      .truth/README.md
      prompts/truth-verifier.md
      .gitattributes.jinja               (must MERGE the union line if file exists — document this limitation: copier overwrites, so instead ship the line in a post-generation task)

Minimal `copier.yml`:

    _subdirectory: template
    project_name:
      type: str
      help: Repo name (used only in .truth/README.md heading)
    _tasks:
      - "chmod +x scripts/truth scripts/check-truth.sh scripts/truth-canary.sh"
      - "touch .truth/claims.jsonl"
      - "grep -q 'claims.jsonl merge=union' .gitattributes 2>/dev/null || echo '.truth/claims.jsonl merge=union' >> .gitattributes"
      - "bash scripts/truth-canary.sh"

Note the last task: the canary runs at template instantiation, so every new
project proves its truth layer works before the first commit. If the repo
already uses the existing DOC-GOVERNANCE Copier template, add these files
and tasks to it rather than creating a second template — two templates for
one governance system is the duplication failure mode this whole layer
exists to prevent.

Hook installation cannot be a Copier task portably (`.git` may not exist at
generation time); add the hook shim instructions to the template's
bootstrap prompt instead, mirroring Step 3 above.

## What NOT to do

- Do not add features to `truth` (no daemon, no server, no colors).
- Do not touch `.beads/` or any Beads files — Beads is read-only from here.
- Do not write additional documentation beyond this install.
- Do not mark any gate passed without running it this session.

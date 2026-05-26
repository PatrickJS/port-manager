# Port Manager Repo

## Objective

Create and verify a private GitHub repository named `PatrickJS/port-manager`, with a local checkout at `/Users/patrickjs/code/patrickjs/port-manager`, using a `pnpm` workspace that starts with the Node/CLI port-finding contract and leaves room for the native macOS app.

## Original Request

"lets create a private repo on github called port-manager for now to push our code to make sure the repo shape makes sense and use pnpm"

## Intake Summary

- Input shape: `specific`
- Audience: Patrick and future AI/developer agents using the port manager repo
- Authority: `requested`
- Proof type: `test`
- Completion proof: the private GitHub repo exists, contains the scaffolded source, and local plus remote checks pass
- Goal oracle: `pnpm run check` passes locally, GitHub Actions `Check` passes on the pushed `main` branch, and `gh repo view PatrickJS/port-manager` reports a private repo
- Likely misfire: stopping after a local scaffold without pushing to GitHub, or shipping a package shape that cannot support common Node port-finding package compatibility
- Blind spots considered: npm `port-manager` name collision, GitHub Actions SHA pinning, package replacement should be opt-in instead of global, and port reservation needs to avoid the free-port race
- Existing plan facts: use `pnpm`; repo name `port-manager`; primary package name `@patrickjs/port-manager`; include CLI and compatibility adapters for common port-finding APIs

## Goal Oracle

The oracle for this goal is:

`gh repo view PatrickJS/port-manager --json visibility,defaultBranchRef,url` reports a private repo on `main`; the remote `main` commit matches local `HEAD`; `pnpm run check` passes locally; GitHub Actions `Check` passes on the pushed commit; and the repo contains the Node core, CLI, and compatibility packages.

The PM must keep comparing task receipts to this oracle. Planning, discovery, a passing tiny slice, or a clean-looking board is not enough. The goal finishes only when a final Judge/PM audit maps receipts and verification back to this oracle and records `full_outcome_complete: true`.

## Goal Kind

`specific`

## Current Tranche

The full owner outcome for this tranche is a pushed private GitHub repository with a coherent `pnpm` workspace shape and a verified initial Node/CLI implementation slice. The native macOS app remains a later tranche after the Node/CLI contract is stable.

## Non-Negotiable Constraints

- Use `pnpm`.
- Keep the repo private on GitHub.
- Use `port-manager` as the GitHub repo name.
- Do not use the unscoped npm package name `port-manager`; it is already occupied.
- Prefer dependency-light Node built-ins for the initial package.
- Make replacement of common npm packages opt-in through adapters/aliases, not automatic or global.
- Pin external GitHub Actions to full commit SHAs with version comments.

## Stop Rule

Stop only when a final audit proves the full original outcome is complete.

Do not stop after planning, discovery, or local-only implementation when the user asked for a private GitHub repo with pushed code.

## Slice Sizing

Safe means bounded, explicit, verified, and reversible. It does not mean tiny.

For this tranche, the useful slice is the whole initial repository scaffold plus verified push, not a single helper or one local file.

## Canonical Board

Machine truth lives at:

`docs/goals/port-manager-repo/state.yaml`

If this charter and `state.yaml` disagree, `state.yaml` wins for task status, active task, receipts, verification freshness, and completion truth.

## Run Command

```text
/goal Follow docs/goals/port-manager-repo/goal.md.
```

## PM Loop

On every `/goal` continuation:

1. Read this charter.
2. Read `state.yaml`.
3. Re-check the repo, GitHub remote, and verification state before claiming completion.
4. Work only on the active board task unless performing final audit.
5. Write compact receipts.
6. Finish only with a Judge/PM audit receipt that maps receipts and verification back to the original user outcome and records `full_outcome_complete: true`.


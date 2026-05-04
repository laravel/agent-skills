---
name: starter-kit-upgrade
description: Selectively pull upstream improvements from a Laravel starter kit (laravel/vue-starter-kit, laravel/react-starter-kit, laravel/livewire-starter-kit) into a project bootstrapped from one. Use when the user wants to update, sync, or migrate features from their starter kit. Applies one feature at a time on a dedicated branch; never auto-merges customized files.
---

# Laravel Starter Kit Upgrade

## Why this skill exists

Laravel's starter kits (`vue-starter-kit`, `react-starter-kit`, `livewire-starter-kit`) give you a working app to start from, but once you start and customize, you own the code. There's no plain way to pull in subsequent upstream improvements — toast notifications, security patches, dep bumps, the password visibility toggle, Teams support — without risking your customizations.

This skill picks features one at a time from upstream and applies only those, with the highest priority being: do not change the application's existing behavior.

## Safety contract — non-negotiable

Read these to the user before any side effects, and live by them throughout:

1. Working tree must be clean. If `git status` shows uncommitted changes, refuse to proceed and tell the user to commit or stash. Do not attempt to "stash for them."
2. All work happens on a dedicated branch (`starter-kit-upgrade/<short-id>`). The user's current branch is never modified.
3. Each applied feature is its own commit. That is how revertability works — they can `git revert` or drop a single feature without losing the others.
4. Never auto-resolve conflicts. If a change touches code the user has customized, surface it; default action is to skip the file. The user can opt to apply.
5. Never silently overwrite manifests or lockfiles (`composer.json`, `package.json`, `*.lock`). Always show the diff and let the user decide.
6. Verify behavior preservation. After applying, run the user's existing test suite. A previously-passing test that now fails is a regression — stop, surface it, recommend revert.
7. When uncertain, stop and ask. Best-effort guessing is forbidden. Guessing on someone's codebase is how trust dies.

If any of these fail, abort the skill with a clear message about what went wrong and how the user can recover.

## Required tools

- `git` (in the user's project)
- `gh` (GitHub CLI, authenticated — `gh auth status` returns OK)
- `bash` (for the bundled scripts)

## Workflow

The flow has eight phases. Do them in order. Don't skip ahead — each phase establishes invariants the next relies on.

### Phase 1 — Identify the kit and branch variant

Inspect the user's project to figure out which starter kit they're tracking:

- Vue kit — `resources/js/components/ui/` contains shadcn-vue (`.vue` files), `package.json` has `vue` and `@inertiajs/vue3`.
- React kit — `resources/js/components/ui/` contains shadcn/ui (`.tsx` files), `package.json` has `react` and `@inertiajs/react`.
- Livewire kit — no `resources/js/components/ui/`, presence of `livewire/livewire` and `livewire/flux` in `composer.json`.

State your detection out loud and ask the user to confirm. If you can't tell, ask.

Then ask which branch variant they're tracking — typically `main` (Fortify-based auth) or `workos` (WorkOS-based auth). This is not detectable from project state; ask explicitly.

See `references/kits.md` for kit-specific notes.

### Phase 2 — Enumerate available upstream features

The user can't tell you "what version they're on" reliably (and we don't try). Instead, look at what's recently happened upstream and present it as a feature catalog.

Use `gh` to fetch the raw data:

```bash
# Recent commits on the chosen branch
gh api "repos/laravel/<kit>/commits?sha=<branch>&per_page=100" \
  -q '.[] | {sha: .sha[0:7], date: .commit.author.date[0:10], msg: .commit.message | split("\n")[0]}'

# Recent merged PRs targeting the branch (richer descriptions)
gh pr list --repo "laravel/<kit>" --state merged --base "<branch>" --limit 100 \
  --json number,title,mergeCommit,mergedAt
```

Then cluster commits/PRs into user-facing features. This is the part you reason about — the data is deterministic, but turning a list of commits into a coherent catalog requires judgment. Examples of feature names a user would recognize:

- "Toast notifications across all kits" (1 commit, several files)
- "Password visibility toggle in auth forms" (1 commit)
- "2FA autofocus fix" (1 commit, 1 file)
- "Teams support" (1 PR, many files — flag as large)
- "Inertia 3 upgrade" (lockfile-heavy — flag as needing review)
- "Maintenance: formatting / dep tidying" (bucket of small commits)

Group internal/refactor commits (formatting, lint config) under a single "Maintenance" entry. The user will usually skip these.

Filter against what the user already has. For each candidate feature, do a cheap check using `scripts/classify_feature.sh` against the feature commit: if every file is `already-present`, the user has pulled this in already. Mark with `[!] Already present` and skip by default.

### Phase 3 — Present the catalog and get explicit selection

Show the user a checklist like this:

```
Available upstream features (vue-starter-kit, branch: main):

[ ] Toast notifications              — PR #142, 4 files, 1 lockfile
[ ] Password visibility toggle       — PR #131, 3 files
[ ] 2FA autofocus fix                — commit 78fda0c, 1 file
[ ] Teams support                    — PR #98, 23 files (LARGE)
[~] Inertia 3 upgrade                — PR #110, lockfile-heavy (review carefully)
[!] Already present: Vite font plugin

Which would you like to pull in?
```

Wait for the user's selection. Do not proceed silently. Recap the picks plus the affected file counts, and ask one final time before any side effects.

### Phase 4 — Preflight

Run `scripts/preflight.sh` against the user's repo. Refuse to proceed on any non-zero exit.

If it passes, fetch the upstream kit into a working cache:

```bash
scripts/fetch_kit.sh <kit> <branch> /tmp/starter-kit-<kit>
```

Create the upgrade branch on the user's repo:

```bash
git -C <user_repo> checkout -b "starter-kit-upgrade/$(date +%Y%m%d-%H%M)-<first-slug>"
```

From this point on, every write goes to this branch. The user's previous branch is untouched.

### Phase 5 — Apply each selected feature

For each selected feature, in order:

1. Run `scripts/classify_feature.sh <kit_dir> <sha> <user_repo>` to get per-file classification. Possible statuses (only four):
   - `new` — file does not exist in the user's repo, exists upstream. Safe to add.
   - `already-present` — user's file is byte-identical to upstream's current version (or both lack the file). Skip.
   - `differs` — user has the file and its content does not match upstream's current version. Always surface to the user — never auto-merge.
   - `lockfile` — `composer.json` / `package.json` / lock files. Always surface to the user — never auto-merge.

   The classifier compares only against upstream's current state of each file. It does NOT use the feature commit's parent as a baseline, because the user's git history is unrelated to the kit's history; "what was the file before the change" is not a meaningful concept on the user's side. The feature commit is used only to enumerate which files to consider.

2. Run `scripts/apply_feature.sh <kit_dir> <sha> <user_repo>` to apply the only auto-applicable category — `new` files. Everything else is skipped with a reason on stdout. Capture the output for the report.

3. For each `differs` and `lockfile` file, walk the user through it. Do them one at a time, in this order:
   - Show what upstream's current version looks like: `git -C <kit_dir> show HEAD:<path>`
   - Show their current file: read from `<user_repo>/<path>`
   - Show the diff between the two so the user can see what would change.
   - Ask the user to pick one of:
     - Take upstream wholesale. Overwrite their file with `git -C <kit_dir> show HEAD:<path> > <user_repo>/<path>`. Their customizations to that file are lost.
     - Keep theirs. Do nothing. Their file stays as is.
     - Merge by hand. Open the file in their editor; you can produce a 3-way reference with `git merge-file -p --diff3` if they want, but the merge is theirs to do — you do not write the result.
   - Default if they're unsure: keep theirs. That preserves application behavior.
   - Stage whatever they chose: `git -C <user_repo> add <path>` (or leave unstaged if they chose keep theirs).

4. Commit the feature as one revertable unit:
   ```bash
   git -C <user_repo> commit -m "starter-kit-upgrade: <feature name>

   Upstream: laravel/<kit>@<sha>
   Files added: <list>
   Files updated (took upstream): <list>
   Files updated (manual merge): <list>
   Files kept as-is: <list>"
   ```

If the user wants to bail out at any point, leave the upgrade branch as-is. They can drop it with `git branch -D` or keep it for review.

### Phase 6 — Reconcile manifests if needed

If any feature touched `composer.json` or `package.json`, the lockfiles are out of sync. Run the appropriate command only after the user agrees:

- `composer install` if `composer.lock` exists and `composer.json` was edited.
- `npm install` / `pnpm install` / `yarn install` / `bun install` (auto-detect from existing lock file in repo).

Commit lockfile updates as a separate `starter-kit-upgrade: dependency lockfiles` commit so they can be reverted independently.

### Phase 7 — Verify behavior preservation

This is the contract enforcement step. Run the user's tests:

```bash
scripts/run_tests.sh <user_repo>
```

Capture the result. If the test command exits non-zero, that's the signal of a behavior regression. Do not declare success.

- Show the user the failing test output.
- Recommend reverting the most recently applied feature first: `git revert HEAD`.
- If multiple features were applied and it's not obvious which broke things, suggest `git bisect` across the upgrade branch's commits.
- Do not attempt to "fix" the failing tests by editing code. That violates the behavior contract.

If tests pass, continue to the report. If the project has no test suite, say so explicitly in the report — don't pretend verification happened.

### Phase 8 — Write the report

Write `STARTER_KIT_UPGRADE.md` at the repo root with:

```markdown
# Starter Kit Upgrade Report

- Date: <date>
- Kit: laravel/<kit>
- Branch tracked: <branch>
- Upgrade branch: starter-kit-upgrade/<id>

## Features applied
- <feature name> — laravel/<kit>@<sha> — <N files>
  - Applied: <list>
  - Skipped: <list with reasons>
  - Manual decisions: <if any, with reasoning>

## Lockfile updates
<which lock files were regenerated and how>

## Verification
- Test command: <command>
- Result: <PASS / FAIL / NO-TESTS>
- Output: <relevant snippet>

## How to revert
- Drop a single feature: `git revert <commit-sha>`
- Discard everything: `git checkout <previous-branch> && git branch -D starter-kit-upgrade/<id>`
```

This file is for the user — it's their audit trail. They can choose to commit it or `.gitignore` it.

## Bail-out conditions

Stop and surface to the user when:

- The working tree is dirty.
- You can't determine which kit they're using and they can't confirm.
- They selected a feature whose commit can't be fetched (rare; network/permission).
- More than ~50 files would `differ` in a single feature — recommend manual upgrade for that feature instead; the per-file walkthrough is too tedious to be useful at that scale.
- The user's tests fail post-apply.
- Anything else you didn't expect. Tell the user what you saw.

## Worked examples and known failure modes

See `references/failure-modes.md` for cases like:

- User has an in-house toast helper; upstream is adding one.
- User renamed a controller; upstream modifies the original path.
- Lockfile drift — how to walk the user through merging `composer.json` constraints.
- Tests fail after applying — how to bisect.

## Things this skill does NOT do

- Detect which "version" the user started from. There is no reliable way; we don't pretend.
- Reconcile dep version constraints automatically. We show, the user decides.
- Handle forks of the starter kits. If the user's repo's structure isn't recognizable as one of the three official kits, refuse and explain.
- Migrate across kits (e.g., Vue → React). Out of scope.
- Run linters / formatters on applied files. The user runs their own tooling.

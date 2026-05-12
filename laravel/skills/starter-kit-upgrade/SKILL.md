---
name: starter-kit-upgrade
description: Selectively pull upstream improvements from a Laravel starter kit (laravel/vue-starter-kit, laravel/react-starter-kit, laravel/svelte-starter-kit, laravel/livewire-starter-kit) into a project bootstrapped from one. Use when the user wants to update, sync, or migrate features from their starter kit. Applies one feature at a time on a dedicated branch; never auto-merges customized files.
---

# Laravel Starter Kit Upgrade

- Users bootstrap from `laravel/vue-starter-kit`, `react-starter-kit`, `svelte-starter-kit`, or `livewire-starter-kit`, then customize. They own the code.
- We pick **specific features** from upstream (e.g. "toast notifications", "2FA autofocus fix"), not "version upgrades."
- The user's git history is unrelated to the kit's. There is no common ancestor. We compare user-now vs upstream-now, byte by byte.
- We never auto-merge a customized file. Customizations are surfaced; the user decides.
- Behavior preservation is the contract: the user's currently-passing tests/typecheck/build must still pass after.

## Safety contract: non-negotiable

Read these to the user before any side effects, and live by them throughout:

1. Working tree must be clean. If `git status --porcelain` is non-empty, refuse and tell the user to commit or stash. Do not "stash for them."
2. All work happens on a dedicated branch (`starter-kit-upgrade/<short-id>`). The user's current branch is never modified.
3. Each applied feature is its own commit. That is how revertability works.
4. Never auto-resolve conflicts. A change touching customized code is surfaced; default action is to skip the file.
5. Never silently overwrite manifests or lockfiles (`composer.json`, `package.json`, `*-lock.*`). Show diffs; let the user decide.
6. Verify behavior preservation. Re-run the user's tests/typecheck/build after applying. A previously-passing check that now fails is a regression. Stop, surface, recommend revert.
7. Detect from unambiguous signals; ask when ambiguous. Concrete evidence (e.g. `config/fortify.php` exists) is fine. Picking a likely answer when signals are mixed or absent is not.

If any of these is violated, abort with a clear message about what went wrong and how to recover.

## Required tools

- `git` (in the user's project)
- `gh` (authenticated; `gh auth status` returns OK)
- `jq` (used by `run_tests.sh`)
- `bash` (for the bundled scripts)

If any is missing, stop in Phase 4 and tell the user how to install.

## Gotchas

Environment-specific behavior the agent will get wrong without being told. Read these before starting the workflow and apply throughout.

- **Parallel implementations.** When a feature has `new` files plus `differs` to call sites, the user may already have an in-house equivalent (their own toast helper, validation rule, etc.). Surface as a whole; don't apply the `new` files in isolation as if they're "safe." Default action is to skip the entire feature; the user can opt to adopt upstream's version and remove theirs later.

- **Renamed paths.** If a `new` path's basename or class name already exists elsewhere in the user's repo, the user has likely renamed/moved it. Surface, don't auto-apply, or you'll create a duplicate. Show them the upstream change and let them apply it to their renamed file by hand or wait for user confirmation.

- **Later upstream edits.** Copying upstream HEAD pulls in _every_ commit since the feature, not just the feature's own changes. Always run the Phase 5 step 2 check before applying. When later edits exist, scope to `<sha>:<path>` instead of `HEAD:<path>`.

- **Transitive imports.** New files often `import` from helpers that are NOT in the same feature commit (Vue/React/Svelte: `@/lib/...`, `@/components/...`; Livewire: `@include`, `<x-...>`, `<livewire:...>`). Phase 5 step 4 covers the scan; never declare a feature applied without it. Uncovered imports show up as runtime/compile errors.

- **Lockfile drift.** Manifests are user-curated. Never overwrite. Walk the user through the upstream diff, let them merge, then regenerate lockfiles via the package manager (Phase 6).

- **Stale node_modules after major bumps.** After Vite v7 → v8, React 18 → 19, etc., `npm install` often fails with `ERESOLVE`. Clean and reinstall (Phase 6).

- **New migrations.** When upstream adds migrations (e.g. "Catch migrations up to Skeleton"), surface them separately. Recommend `php artisan migrate:status` first; applying a new migration on a populated DB can fail loudly.

- **Major framework bumps as features.** Things like Laravel 12 → 13, Livewire 3 → 4, or Inertia v2 → v3 are too large and too breaking for the feature-by-feature flow. Do not attempt them through this skill. Instead, prompt the user to run the corresponding [Laravel Boost](https://github.com/laravel/boost) MCP slash command first, then come back and re-run this skill against the resulting (clean-tree) repo. If Boost is not yet installed: `composer require laravel/boost --dev && php artisan boost:install` (requires Boost `^2.0`). Slash commands:
  - Laravel 12 → 13: `/upgrade-laravel-v13`
  - Livewire 3 → 4: `/upgrade-livewire-v4`
  - Inertia v2 → v3: `/upgrade-inertia-v3`

- **Already-present features.** If Phase 2's pre-filter missed it and Phase 5's classifier reports every file as `already-present`, skip the feature with a note: "every file matches upstream's current; moving on." Don't commit an empty commit.

- **More than ~50 `differs`.** The per-file walkthrough is too tedious to be useful at that scale. Stop, recommend manual upgrade for that feature.

## Workflow

Eight phases, in order. Each phase establishes invariants the next relies on.

### Phase 1: Identify the kit and branch variant

Inspect the user's project:

|                     | vue                                              | react                                            | svelte                                              | livewire                                  |
| ------------------- | ------------------------------------------------ | ------------------------------------------------ | --------------------------------------------------- | ----------------------------------------- |
| Cue                 | `.vue` files in `resources/js/components/ui/`    | `.tsx` files in `resources/js/components/ui/`    | `.svelte` files in `resources/js/components/ui/`    | no `resources/js/components/ui/` dir      |
| `package.json` has  | `"vue"` + `"@inertiajs/vue3"`                    | `"react"` + `"@inertiajs/react"`                 | `"svelte"` + `"@inertiajs/svelte"`                  | n/a                                       |
| `composer.json` has | n/a                                              | n/a                                              | n/a                                                 | `"livewire/livewire"` + `"livewire/flux"` |

State the detected kit out loud. If only one column matches, proceed. If two columns partially match (e.g. both `.vue` and `.tsx` present, or `package.json` lists `vue` and `react`), stop and ask.

Then determine the branch variant. There are four branches per kit, formed by two independent axes:

- **Auth axis** (read `composer.json`):
  - Fortify if `composer.json` has `laravel/fortify`, or `config/fortify.php` exists, or `app/Actions/Fortify/` exists, or `app/Providers/FortifyServiceProvider.php` exists.
  - WorkOS if `composer.json` has `laravel/workos` and none of the Fortify markers are present.
- **Teams axis** (check whether team scaffolding is present):
  - Teams if `app/Models/Team.php` exists (usually accompanied by `Membership.php`, `TeamInvitation.php`, and a `..._create_teams_table.php` migration).
  - Non-teams otherwise.

Combine the two axes to get the branch name:

| Auth    | Teams | Branch          |
| ------- | ----- | --------------- |
| Fortify | no    | `main`          |
| Fortify | yes   | `teams`         |
| WorkOS  | no    | `workos`        |
| WorkOS  | yes   | `workos-teams`  |

State the detected branch out loud. Only ask if signals are contradictory (e.g. Fortify markers present _and_ `laravel/workos` in composer, or a `Team.php` model with no teams migration); that means user customization you can't safely guess at.

### Phase 2: Enumerate available upstream features

The user can't tell you "what version they're on" reliably (and we don't try). Inspect upstream as it exists today and present a feature catalog.

Fetch raw data. The default window is the **last 100 commits / merged PRs**; tell the user that up front so they know features older than that won't appear in the catalog. If they bootstrapped well before that window, walk back with `&page=2`, `&page=3`, etc. or raise `--limit`.

```bash
gh api "repos/laravel/<kit>/commits?sha=<branch>&per_page=100" \
  -q '.[] | {sha: .sha[0:7], date: .commit.author.date[0:10], msg: .commit.message | split("\n")[0]}'

gh pr list --repo "laravel/<kit>" --state merged --base "<branch>" --limit 100 \
  --json number,title,mergeCommit,mergedAt
```

Cluster commits/PRs into user-facing features. Examples a user would recognize:

- "Toast notifications across all kits" (1 commit, several files)
- "Password visibility toggle in auth forms" (1 commit, 3 files)
- "2FA autofocus fix" (1 commit, 1 file)
- "Teams support" (1 PR, many files; flag as large)
- "Inertia 3 upgrade" (lockfile-heavy; flag as needing review)
- "Maintenance: formatting / lint config" (bucket of small commits)

Bucket internal/refactor commits as a single "Maintenance" entry. The user usually skips it.

Pre-filter: for each candidate feature, run `scripts/classify_feature.sh` against its commit. If every file is `already-present`, mark `[!] Already present` and skip by default.

### Phase 3: Present the catalog and get explicit selection

```
Available upstream features (vue-starter-kit, branch: main):

[ ] Toast notifications              · PR #142, 4 files, 1 lockfile
[ ] Password visibility toggle       · PR #131, 3 files
[ ] 2FA autofocus fix                · commit 78fda0c, 1 file
[ ] Teams support                    · PR #98, 23 files (LARGE)
[~] Inertia 3 upgrade                · PR #110, lockfile-heavy (review carefully)
[!] Already present: Vite font plugin

Which would you like to pull in?
```

Wait for the selection. Recap the picks and the affected file counts. Ask one final time before any side effects.

### Phase 4: Preflight, baseline, and workspace setup

Run preflight:

```bash
scripts/preflight.sh <user_repo>
```

It checks the repo is a git repo, the tree is clean, and that `gh` (authenticated) and `jq` are available. If it exits non-zero, surface the message verbatim and stop.

Record a verification baseline so Phase 7 can distinguish regressions from pre-existing failures. Use `mktemp` so concurrent runs don't clobber each other:

```bash
baseline=$(mktemp -t skup-baseline.XXXXXX.json)
scripts/run_tests.sh <user_repo> --baseline "$baseline"
```

Hold onto `$baseline`; Phase 7 needs it.

Fetch the upstream kit and capture its path:

```bash
kit_dir=$(scripts/fetch_kit.sh <kit> <branch>)
```

Hold onto `$kit_dir`; Phase 5 needs it. The script is idempotent: re-running with the same args fetches the latest branch tip rather than re-cloning.

Create the upgrade branch:

```bash
git -C <user_repo> checkout -b "starter-kit-upgrade/$(date +%Y%m%d-%H%M)-<first-slug>"
```

If the user is already on a `starter-kit-upgrade/...` branch (a previous run that didn't get cleaned up), `checkout -b` will refuse if the new name collides. Don't auto-resolve: ask whether they want to **resume on that branch** (skip the `checkout -b`, keep going from where they were), **start fresh** (the new timestamped name will already differ by minute, so just retry — or bump to `+%Y%m%d-%H%M%S` if it's the same minute), or **abort** so they can clean up manually. Never delete the existing branch on their behalf.

From this point on, every write goes to this branch.

### Phase 5: Apply each selected feature

For each selected feature, in order:

1. Classify. Run `scripts/classify_feature.sh <kit_dir> <sha> <user_repo>`. Statuses:

- `new`: file does not exist in user repo, exists at upstream HEAD. Safe to add.
- `already-present`: user's file is byte-identical to upstream HEAD. Skip.
- `differs`: user has the file and bytes differ from upstream HEAD. Surface.
- `deleted-upstream`: upstream HEAD lacks the file but the user has it. Surface; default is keep theirs.
- `lockfile`: manifest or lock file. Surface; never auto-merge.

The classifier compares only against upstream HEAD. The user's git history doesn't trace back to the kit's, so there's no "before-image" baseline to merge against; we don't try. The feature commit just enumerates which paths to look at.

2. Later-edits check. Find which feature paths _later_ upstream commits also modified:

```bash
scripts/later_edits.sh <kit_dir> <sha> <user_repo>
```

Each path the script prints is a path where copying upstream HEAD's content pulls _later_ changes in too. Diff `<sha>:<path>` against `HEAD:<path>`; if a non-whitespace hunk differs, scope to the feature commit (`git -C <kit_dir> show <sha>:<path>`) and note it in the report.

**3. Apply `new` files.** The script writes upstream HEAD's content for each `new` path and stages it; everything else is left for steps 4–5:

```bash
scripts/apply_new_files.sh <kit_dir> <sha> <user_repo>
```

It prints `applied <path>` for each file written so you can collect the list for the feature's commit message and the report.

Before letting the script run, check for the rename gotcha (see Gotchas → "Renamed paths"). If a `new` path's basename already exists at a different location in the user's repo, surface to the user before applying.

**4. Transitive-imports check.** New files often import helpers that aren't in the same feature commit. The script picks the right regex for the kit (Vue/React/Svelte handle TS/JS imports; Livewire handles Blade includes / `x-` components / `livewire:` tags):

```bash
scripts/scan_transitive_imports.sh <kit> <new_files...>
```

Output is `<file>:<line>:<match>` per import. For each match, verify the corresponding helper file exists in the user's repo. If not, the new files won't compile/render; flag the missing target as a follow-up dependency the user needs to fetch (same walkthrough as `differs`).

**5. Walk the user through `differs`, `deleted-upstream`, and `lockfile`.** One file at a time:

- Show what upstream has: `git -C <kit_dir> show HEAD:<path>` (or `<sha>:<path>` if `later_edits.sh` flagged this path).
- Show their current file.
- Show the diff between the two.
- Ask the user to pick: take upstream wholesale (lossy; confirm first), keep theirs, or merge by hand (you produce a unified diff for reference; they write the result).
- If they're unsure, ask once more with the diff in front of them. Still unsure → keep theirs and move on. Don't pick silently.
- Stage whatever they chose: `git -C <user_repo> add <path>`.

For `lockfile`: never overwrite the manifest. Show the upstream diff for `composer.json` / `package.json`, walk them through the relevant change, let them edit the manifest. Lockfile regeneration happens in Phase 6.

**6. Commit the feature as one revertable unit:**

```bash
git -C <user_repo> commit -m "starter-kit-upgrade: <feature name>

Upstream: laravel/<kit>@<sha>
Files added: <list>
Files updated (took upstream): <list>
Files updated (manual merge): <list>
Files kept as-is: <list>"
```

If the user wants to bail out at any point, leave the branch as-is. They can drop it with `git branch -D`.

### Phase 6: Reconcile manifests if needed

If any feature touched a manifest, lockfiles are out of sync. After the user agrees, run:

```bash
scripts/reconcile_manifests.sh <user_repo>
```

The script runs `composer install` (when `composer.json` + `composer.lock` are both present), auto-detects the JS package manager from the existing lockfile, runs `<pm> install`, and on failure (typically `ERESOLVE` after a major bump like Vite v7 → v8 or React 18 → 19) wipes `node_modules` + the lockfile and retries once.

Commit lockfile updates as a separate `starter-kit-upgrade: dependency lockfiles` commit so they can be reverted independently.

### Phase 7: Verify behavior preservation

Compare against the baseline:

```bash
scripts/run_tests.sh <user_repo> --compare "$baseline"
```

Compare mode runs PHP tests, JS typecheck, JS build (whichever exist) and reports only checks that were passing in the baseline and now fail. Pre-existing failures are not the upgrade's fault and don't block.

If a regression is reported:

- Show the failing output from the per-check log file the script points to.
- Recommend `git revert HEAD` first; if that doesn't fix it, revert again.
- For multi-feature uncertainty, suggest `git bisect start <upgrade-branch> <previous-branch>`.
- Do not edit code to make the failing check pass; that violates the behavior contract.

If the project has no discoverable verification commands, say so explicitly in the report. Don't pretend verification happened.

### Phase 8: Write the report

Write to `/tmp/starter-kit-upgrade-report-<id>.md` (where `<id>` matches the upgrade branch's `starter-kit-upgrade/<id>`) first; never silently into the user's repo. Stamping the id keeps concurrent runs and re-runs from clobbering each other. Show the path and ask whether they want it copied in as `STARTER_KIT_UPGRADE.md` or kept out of tree.

```markdown
# Starter Kit Upgrade Report

- Date: <date>
- Kit: laravel/<kit>
- Branch tracked: <branch>
- Upgrade branch: starter-kit-upgrade/<id>

## Features applied

- <feature name> · laravel/<kit>@<sha> · <N files>
  - Applied: <list>
  - Skipped: <list with reasons>
  - Manual decisions: <if any, with reasoning>
  - Later-edit drift avoided: <if any, with paths scoped manually>

## Lockfile updates

<which lock files were regenerated and how>

## Verification

- Baseline: <path or summary>
- Result: <PASS / REGRESSED:<list> / NO-CHECKS>
- Output: <relevant snippet>

## How to revert

- Drop a single feature: `git revert <commit-sha>`
- Discard everything: `git checkout <previous-branch> && git branch -D starter-kit-upgrade/<id>`
```

## Out of scope

- Detecting which kit "version" the user started from. There is no reliable way; we don't pretend.
- Reconciling dep version constraints automatically. We show; the user decides.
- Forks of the starter kits. If the repo's structure isn't recognizable as one of the three official kits, refuse and explain.
- Cross-kit migration (e.g. Vue → React).
- Running linters / formatters on applied files. The user runs their own tooling.

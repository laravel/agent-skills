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
6. Verify behavior preservation. After applying, re-run the user's existing test/typecheck/build commands. A previously-passing check that now fails is a regression — stop, surface it, recommend revert.
7. When uncertain, stop and ask. Best-effort guessing is forbidden. Guessing on someone's codebase is how trust dies.

If any of these fail, abort the skill with a clear message about what went wrong and how the user can recover.

## Required tools

- `git` (in the user's project)
- `gh` (GitHub CLI, authenticated — `gh auth status` returns OK)
- `bash` (for the bundled scripts)

## Workflow

The flow has eight phases. Do them in order. Don't skip ahead — each phase establishes invariants the next relies on.

### Phase 1 — Identify the kit and branch variant

Inspect the user's project:

|   | vue                         | react                       | livewire                          |
|---|-----------------------------|-----------------------------|-----------------------------------|
| Cue | `.vue` files in `resources/js/components/ui/` | `.tsx` files in `resources/js/components/ui/` | no `resources/js/components/ui/` dir |
| `package.json` has | `"vue"` + `"@inertiajs/vue3"` | `"react"` + `"@inertiajs/react"` | n/a |
| `composer.json` has | n/a | n/a | `"livewire/livewire"` + `"livewire/flux"` |

State the detected kit out loud and ask the user to confirm.

Then determine the branch variant — `main` (Fortify auth) or `workos` (WorkOS auth) — by inspecting the user's repo. Signals are unambiguous:

- `main` if `composer.json` has `laravel/fortify`, or `config/fortify.php` exists, or `app/Actions/Fortify/` exists, or `app/Providers/FortifyServiceProvider.php` exists.
- `workos` if `composer.json` has `laravel/workos` and none of the Fortify markers above are present.

State the detected branch out loud. Only ask explicitly if the signals are contradictory (some Fortify markers present *and* `laravel/workos` in composer) — that means the user has done something custom and you can't safely guess.

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

Then cluster commits/PRs into user-facing features. This is the part you reason about — the data is deterministic, but turning a list of commits into a coherent catalog requires judgment. Examples a user would recognize:

- "Toast notifications across all kits" (1 commit, several files)
- "Password visibility toggle in auth forms" (1 commit)
- "2FA autofocus fix" (1 commit, 1 file)
- "Teams support" (1 PR, many files — flag as large)
- "Inertia 3 upgrade" (lockfile-heavy — flag as needing review)
- "Maintenance: formatting / dep tidying" (bucket of small commits)

Group internal/refactor commits (formatting, lint config) under a single "Maintenance" entry.

Filter against what the user already has. For each candidate feature, run `scripts/classify_feature.sh` against the feature commit: if every file is `already-present`, mark with `[!] Already present` and skip by default.

### Phase 3 — Present the catalog and get explicit selection

Show the user a checklist:

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

Wait for the user's selection. Recap the picks plus affected file counts, and ask one final time before any side effects.

### Phase 4 — Preflight, baseline, and workspace setup

Verify the working tree is clean, `gh` is available and authenticated:

```bash
git -C <user_repo> rev-parse --is-inside-work-tree >/dev/null  # is a git repo
[[ -z "$(git -C <user_repo> status --porcelain)" ]]            # clean tree
gh auth status                                                  # gh authenticated
```

If any check fails, stop with a clear message about what's wrong and how to fix.

Record a verification baseline so Phase 7 can distinguish regressions from pre-existing failures:

```bash
scripts/run_tests.sh <user_repo> --baseline /tmp/skup-baseline.json
```

Fetch the upstream kit into a working cache:

```bash
git clone --quiet --depth 500 --branch <branch> \
  "https://github.com/laravel/<kit>.git" /tmp/starter-kit-<kit>
```

Create the upgrade branch:

```bash
git -C <user_repo> checkout -b "starter-kit-upgrade/$(date +%Y%m%d-%H%M)-<first-slug>"
```

From this point on, every write goes to this branch. The user's previous branch is untouched.

### Phase 5 — Apply each selected feature

For each selected feature, in order:

**1. Classify.** Run `scripts/classify_feature.sh <kit_dir> <sha> <user_repo>` for the feature's commit SHA. Statuses:

- `new` — file does not exist in the user's repo, exists upstream. Safe to add.
- `already-present` — user's file already matches upstream's current version. Skip.
- `differs` — user has the file and content differs from upstream's current. Surface to the user.
- `lockfile` — `composer.json` / `package.json` / lock files. Surface to the user.

The classifier compares only against upstream's current state of each file. The user's git history is unrelated to the kit's history; "what was the file before the change" is not meaningful on the user's side. The feature commit is used only to enumerate which files to consider.

**2. Cumulative-bleed check.** Before applying anything, for each file the feature touches, check whether later upstream commits also modified it:

```bash
git -C <kit_dir> log --oneline <sha>..HEAD -- <path>
```

If later commits show up, copying upstream's current content will pull *those* changes in too — not just this feature. Diff `<sha>:<path>` against `HEAD:<path>`; if the difference is material, manually scope to the feature commit's content (`git -C <kit_dir> show <sha>:<path>`) instead of HEAD's, and mention it in the report.

**3. Apply `new` files.** Loop over the classifier output and write upstream's content for each `new` path. Five-line snippet:

```bash
scripts/classify_feature.sh <kit_dir> <sha> <user_repo> \
  | awk -F'\t' '$1=="new"{print $2}' \
  | while IFS= read -r path; do
      mkdir -p "<user_repo>/$(dirname "$path")"
      git -C <kit_dir> show "HEAD:$path" > "<user_repo>/$path"
      git -C <user_repo> add -- "$path"
    done
```

**4. Transitive-imports check (for each new file you applied).** New files often import helpers that aren't in the same feature commit. Quick scan:

```bash
grep -E "from ['\"]@?/?(lib|components|utils)/" <user_repo>/<new_file>
```

For each import, verify the target exists in the user's repo. If not, the feature's `new` files will fail to compile. Flag these as `differs`-equivalent and walk the user through fetching the missing dependency from upstream.

**5. Walk the user through `differs` and `lockfile`.** One file at a time:

- Show what upstream has: `git -C <kit_dir> show HEAD:<path>` (or `<sha>:<path>` if cumulative bleed is a concern)
- Show their current file
- Show the diff
- Ask the user to pick:
  - Take upstream wholesale. Overwrite their file. Their customizations are lost — confirm before doing it.
  - Keep theirs. Do nothing. File stays as is.
  - Merge by hand. Open in their editor. You produce a unified diff for reference; they write the result.
- Default if they're unsure: keep theirs (preserves behavior).
- Stage whatever they chose: `git -C <user_repo> add <path>`.

**6. Watch for parallel implementations.** When a feature has `new` files plus `differs` to call sites, the user may already have an in-house equivalent (e.g. their own toast helper, their own validation rule). Surface as a whole — don't apply the `new` files in isolation as if they're "safe."

**7. Watch for renamed paths.** If a feature's path classifies as `new` but a file with the same basename or class name already exists elsewhere in the user's repo, surface — don't auto-apply, or you'll create a duplicate.

**8. Commit the feature as one revertable unit:**

```bash
git -C <user_repo> commit -m "starter-kit-upgrade: <feature name>

Upstream: laravel/<kit>@<sha>
Files added: <list>
Files updated (took upstream): <list>
Files updated (manual merge): <list>
Files kept as-is: <list>"
```

If the user wants to bail out at any point, leave the upgrade branch as-is.

### Phase 6 — Reconcile manifests if needed

If any feature touched `composer.json` or `package.json`, the lockfiles are out of sync. Run only after the user agrees:

- `composer install` if `composer.lock` exists and `composer.json` was edited.
- `pnpm install` / `npm install` / `bun install` / `yarn install` (auto-detect from existing lockfile in the repo).

If `npm install` fails with `ERESOLVE` after a major-version manifest bump (e.g. Vite v7 → v8, React 18 → 19), stale `node_modules` is the usual cause. Clean and reinstall:

```bash
rm -rf node_modules package-lock.json   # or pnpm-lock.yaml, etc.
<package-manager> install
```

Commit lockfile updates as a separate `starter-kit-upgrade: dependency lockfiles` commit so they can be reverted independently.

### Phase 7 — Verify behavior preservation

Run the verification suite and compare against the baseline recorded in Phase 4:

```bash
scripts/run_tests.sh <user_repo> --compare /tmp/skup-baseline.json
```

The compare mode runs PHP tests, JS typecheck, and JS build (whichever exist), and reports only checks that were *passing* in the baseline and now fail. That's the regression set — pre-existing failures are not the upgrade's fault and should not block.

If any regression is reported:

- Show the user the failing output.
- Recommend `git revert HEAD` to drop the most recently applied feature first; if that doesn't fix it, revert the previous one too.
- For multiple-feature uncertainty, suggest `git bisect start <upgrade-branch> <previous-branch>`.
- Do not attempt to "fix" the failing checks by editing code. That violates the behavior contract.

If the project has no discoverable verification commands at all, say so explicitly in the report — don't pretend verification happened.

### Phase 8 — Write the report

Write `STARTER_KIT_UPGRADE.md` at the repo root:

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
  - Cumulative bleed avoided: <if any, with the path(s) you scoped manually>

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

This file is the user's audit trail. They can commit it or `.gitignore` it.

## Cross-kit watch list

Patterns that need special handling regardless of which kit:

| # | Pattern | What to do |
|---|---|---|
| 1 | Lockfile change (`composer.json`, `package.json`, `*-lock.*`) | Never auto-merge. Show diff, user edits manifest, re-run pkg manager. |
| 2 | New migration (e.g. "Catch migrations up to Skeleton") | Surface separately. Recommend `php artisan migrate:status` before applying. New migrations on populated DBs can fail. |
| 3 | Major framework bump (Inertia v2→v3, Laravel major) | Too large for feature-by-feature application. Flag and recommend manual upgrade pass. |
| 4 | WorkOS vs main mismatch | The `gh api ?sha=<branch>` call already restricts enumeration to the chosen branch — double-check before applying. |
| 5 | Renamed paths (user moved a file) | Classifier returns `new` for the original path. Scan for basename match elsewhere; surface if found. |
| 6 | Cumulative bleed (later commits also touch the feature's files) | `git log <sha>..HEAD -- <path>`. If non-empty, scope to `<sha>:<path>` instead of `HEAD:<path>`. |
| 7 | Transitive imports in new files | Grep imports of new files; verify each target exists in the user repo before declaring success. |

## Bail-out conditions

Stop and surface to the user when:

- The working tree is dirty.
- You can't determine which kit they're using and they can't confirm.
- They selected a feature whose commit can't be fetched.
- More than ~50 files would `differ` in a single feature — recommend manual upgrade for that feature.
- A regression appears in Phase 7 verification.
- Anything else you didn't expect. Tell the user what you saw.

## Things this skill does NOT do

- Detect which "version" the user started from. There is no reliable way; we don't pretend.
- Reconcile dep version constraints automatically. We show, the user decides.
- Handle forks of the starter kits. If the user's repo's structure isn't recognizable as one of the three official kits, refuse and explain.
- Migrate across kits (e.g., Vue → React). Out of scope.
- Run linters / formatters on applied files. The user runs their own tooling.

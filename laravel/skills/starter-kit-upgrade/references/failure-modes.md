# Failure modes — worked examples

Mental model: user history is unrelated to kit history. We compare user-now vs upstream-now. There is no common ancestor, and we never auto-merge.

## 1. User has parallel implementation of what upstream is adding

User has their own `resources/js/utils/notify.ts` toast helper. Upstream adds `flashToast.ts` plus `differs` edits to the same Pages.

- Wrong: apply the `new` files and the Page edits — now both systems run in parallel, redundant code, possibly double-fired.
- Right: surface as a whole. Ask: "Upstream's adding its own toast helper; you appear to have one. (a) skip, (b) adopt upstream and remove yours later, (c) take only the new file and leave Pages alone." Default if unsure: (a).

When a feature has `new` files plus `differs` to call sites, surface the bundle — don't apply the `new` files in isolation as "safe."

## 2. User renamed a file; upstream modifies the original path

User moved `app/Http/Controllers/Settings/ProfileController.php` → `app/Domain/Profile/ProfileController.php`. Classifier reports the original path as `new`.

- Wrong: apply as `new`, creating two profile controllers.
- Right: before applying any `new` file, scan the user's repo for matching basename or class name. If found, surface: "Upstream is creating X, but you appear to have moved it to Y. Want me to show the upstream change so you can apply it to your renamed file?"

`new` is safe by default, not always. Check for a basename match first.

## 3. Lockfile drift (`composer.json` / `package.json`)

Classifier returns `lockfile`.

- Wrong: overwrite with upstream's manifest — blows away every dep the user added.
- Right: show diffs side by side, walk them through the relevant additions, they edit the file, then re-run the package manager (`pnpm install` / `npm install` / `bun install` — auto-detect) to regenerate the lockfile. Commit manifest + lockfile together.

```bash
git -C <kit_dir> show HEAD:package.json > /tmp/upstream-package.json
diff -u <user_repo>/package.json /tmp/upstream-package.json
```

Manifests are user-curated. Never overwrite.

## 4. Tests fail after applying

A previously-passing test now fails on the upgrade branch.

- Wrong: edit the test to make it pass — that violates the behavior contract.
- Right: report the failure, list applied features, recommend `git revert HEAD` (drop the most recent first). If multiple features applied and blame is unclear, suggest `git bisect start <upgrade-branch> <previous-branch>`. Stop the skill — do not declare success.

Per-feature commits exist precisely so reverts are surgical.

## 5. User says "take upstream" on a `differs` file

- Wrong: try to merge their edits with upstream — defeats the point of dropping 3-way merge.
- Right: confirm the loss explicitly ("This will discard your edits to <path>. Confirm?"), then overwrite: `git -C <kit_dir> show HEAD:<path> > <user_repo>/<path>`. Stage. Continue.

"Take upstream" is precise and lossy. Be explicit about the loss.

## 6. User says "merge by hand"

- Wrong: run `git merge-file --diff3` against the feature's parent commit — that parent isn't a meaningful baseline for the user.
- Right: show both files (theirs + upstream HEAD). Optionally drop a unified diff in `/tmp/` they can paste into their editor:
  ```bash
  diff -u <user_repo>/<path> <(git -C <kit_dir> show HEAD:<path>) > /tmp/<basename>.diff
  ```
  They merge. When done, stage: `git -C <user_repo> add <path>`. You do not write the result.

The skill produces references; the human types the merge.

## 7. Kit detection is ambiguous

Project has both `.tsx` and `.vue` files; `package.json` lists both `vue` and `react`.

- Wrong: pick one and proceed.
- Right: show the evidence ("I see 12 .vue files and 47 .tsx files; package.json lists both vue and react") and ask. If they can't say, refuse to proceed.

When input is ambiguous, ask. Don't guess.

## 8. Every file in a feature is `already-present`

- Wrong: reapply it — `apply_feature.sh` produces zero `applied` lines and you'd commit an empty commit.
- Right: skip the feature with a note: "Every file already matches upstream's current version — moving on." If the user explicitly asked for this feature, tell them so they know nothing happened.

Phase 2's `[!] Already present` pre-filter prevents this most of the time; this is the fallback.

# Per-kit notes

Quick reference. Read the section for the kit the user is on.

## Shared facts (all three kits)

- Branches: every kit has `main` (Fortify auth) and `workos` (WorkOS auth). Auto-detect from the user's `composer.json` — `laravel/fortify` ⇒ main, `laravel/workos` (and no Fortify markers) ⇒ workos. Sanity-check via the presence of `config/fortify.php`, `app/Actions/Fortify/`, or `app/Providers/FortifyServiceProvider.php`.
- Versioning: tagged `v1.0.x` but most users follow branch tip — don't rely on tags.
- Sync cadence: coordinated updates land via Maestro every 2-4 weeks, often in batches across all three.
- Backend overlap: PHP, configs, auth scaffolding are ~75-80% identical across kits. Frontend differs.

## At-a-glance comparison

|             | vue-starter-kit       | react-starter-kit     | livewire-starter-kit  |
| ----------- | --------------------- | --------------------- | --------------------- |
| Stack       | Inertia + Vue 3       | Inertia + React 19    | Livewire 4 + Flux     |
| UI library  | shadcn-vue (`.vue`)   | shadcn/ui (`.tsx`)    | Flux in Blade         |
| Pkg manager | pnpm (workspace)      | pnpm (workspace)      | npm                   |
| Lockfile    | `pnpm-lock.yaml`      | `pnpm-lock.yaml`      | `package-lock.json`   |
| Build       | Vite + `plugin-vue`   | Vite + `plugin-react` | Vite (no JS plugin)   |

## vue-starter-kit

Detection cues:
- `.vue` files under `resources/js/components/ui/`
- `package.json` has `"vue"` and `"@inertiajs/vue3"`

Where the frontend lives:
- `resources/js/Pages/` — Inertia pages (`.vue`)
- `resources/js/components/ui/` — shadcn-vue primitives
- `resources/js/lib/` — utilities (e.g. `flashToast.ts`)

Common upstream themes: shadcn-vue additions, Inertia bumps, auth UX polish.

## react-starter-kit

Detection cues:
- `.tsx` files under `resources/js/components/ui/`
- `package.json` has `"react"` and `"@inertiajs/react"`

Where the frontend lives:
- `resources/js/Pages/` — Inertia pages (`.tsx`)
- `resources/js/components/ui/` — shadcn/ui primitives
- `resources/js/lib/` — utilities

Common upstream themes: same as Vue, plus React perf cleanups (`useCallback` / `useMemo` removals).

## livewire-starter-kit

Detection cues:
- No `resources/js/components/ui/` directory
- `composer.json` has `"livewire/livewire"` and `"livewire/flux"`

Where the frontend lives:
- `resources/views/livewire/` — Livewire component views
- `resources/views/components/` — shared Blade components
- `app/Livewire/` — Livewire component PHP classes

Common upstream themes: Livewire syntax updates, Flux bumps, Blaze additions.

## Cross-kit watch list

Patterns that need special handling regardless of which kit the user is on:

1. **Lockfile change** (`composer.json`, `package.json`, `*-lock.*`)
   Never auto-merge. Show the diff, let the user edit the manifest, then re-run their package manager.

2. **New migration** (e.g. "Catch migrations up to Skeleton")
   Surface separately. Recommend `php artisan migrate:status` before applying — new migrations on populated DBs can fail.

3. **Major framework bump** (Inertia v2 → v3, Laravel major)
   Too large for feature-by-feature application. Flag and recommend a dedicated manual upgrade pass.

4. **WorkOS vs main mismatch**
   Restrict feature enumeration to the user's chosen branch. The `gh api ?sha=<branch>` call already does this — double-check.

5. **Renamed paths** (user moved a file)
   Classifier returns `new` for the original path. Before auto-applying, scan for a basename match elsewhere; surface if found. See `failure-modes.md` Case 2.

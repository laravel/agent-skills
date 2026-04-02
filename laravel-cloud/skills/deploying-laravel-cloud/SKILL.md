---
name: deploying-laravel-cloud
description: "Deploys and manages Laravel applications on Laravel Cloud using the `cloud` CLI. Use when the user wants to deploy an app, ship to cloud, create/manage environments, databases, caches, domains, instances, background processes, or any Laravel Cloud infrastructure. Triggers on deploy, ship, cloud management, environment setup, database provisioning, and similar cloud operations."
---
# Deploying with Laravel Cloud CLI

## Setup

```sh
composer global require laravel/cloud-cli
cloud auth -n
```

## Commands

Commands follow a CRUD pattern: `resource:list`, `resource:get`, `resource:create`, `resource:update`, `resource:delete`.

Available resources: `application`, `environment`, `instance`, `database-cluster`, `database`, `cache`, `bucket`, `domain`, `websocket-cluster`, `background-process`, `command`, `deployment`.

Some resources have additional commands (e.g., `domain:verify`, `database:open`, `instance:sizes`, `cache:types`). Discover these via `cloud -h`.

Never hardcode command signatures. Always run `cloud <command> -h` to discover options at runtime.

## CLI Flags

Always add `-n` to every command — prevents the CLI from hanging.
Never use `-q` or `--silent` — they suppress all output.

Flag combos per operation:
- Read (`:list`, `:get`) → `--json -n`
- Create (`:create`) → `--json -n`
- Update (`:update`) → `--json -n --force`
- Delete (`:delete`) → `-n --force` (no `--json`)
- Environment variables → `-n --force`
- Deploy/ship → `-n` with all options passed explicitly (no `--json`)

## Deployment Workflow

Determine the task and follow the matching path:

First deploy? → `cloud ship -n` (discover options via `cloud ship -h`)

Existing app? →
```sh
cloud repo:config
cloud deploy {app_name} {environment} -n --open
cloud deploy:monitor -n
```

Environment variables? → `cloud environment:variables -n --force`

Provision infrastructure? → `cloud <resource>:create --json -n`

Custom domain? → `cloud domain:create --json -n` then `cloud domain:verify -n`

For multi-step operations, see [reference/checklists.md](reference/checklists.md).

Not sure what the user needs? → ask them before running anything.

## When a Command Fails

1. Read the error output
2. Check resource status with `:list --json -n` or `:get --json -n`
3. Auth error? → `cloud auth -n`
4. Fix the issue, re-run the command
5. If the same error repeats after one fix, stop and ask the user

Always run `cloud deploy:monitor -n` after every deploy. If it fails, show the user what went wrong before attempting a fix.

## Subagent Delegation

Delegate high-output operations to subagents (using the Task tool) to keep the main context window small. Only the summary comes back — verbose output stays in the subagent's context.

Delegate these to a subagent:
- `cloud deploy:monitor -n` — deployment logs can be very long
- `cloud deployment:get --json -n` — full deployment details
- `cloud <resource>:list --json -n` — listing many resources produces large JSON
- Fetching docs from https://cloud.laravel.com/docs/llms.txt via `WebFetch`

Keep in the main context:
- Short commands like `:create`, `:delete`, `:update` — output is small
- `cloud deploy -n` — you need the deployment ID immediately
- Any command where you need the result for the next step right away

## Rules

Follow exact steps:
- Flag selection — always use the documented combos above
- Deploy sequence — deploy then monitor, never skip monitoring
- Destructive commands — always confirm with user first, show the command and wait for approval
- Error loop — diagnose, fix once, ask user if it fails again

Use your judgment:
- Instance sizes, regions, cluster types — ask the user if not specified
- Which resources to provision — based on what the user describes
- Order of provisioning — no strict sequence required
- How to present output — summarize, show raw, or extract fields based on context

## Config

1. Global: `~/.config/cloud/config.json` — auth tokens and preferences
2. Repo-local: `.cloud/config.json` — app and environment defaults (set by `cloud repo:config`)
3. CLI arguments override both

## Documentation

Laravel Cloud Docs: https://cloud.laravel.com/docs/llms.txt

When the user asks how something works or needs an explanation of a Laravel Cloud feature, fetch the docs from the URL above using `WebFetch` and use it to provide accurate answers.

## When Stuck

- Fetch https://cloud.laravel.com/docs/llms.txt for official documentation
- Run `cloud <command> -h` for any command's options
- Run `cloud -h` to discover commands

# Laravel Agents & Skills

Laravel's official collection of agent skills, available as plugins for [Claude Code](https://code.claude.com/docs/en/plugins) and [Cursor](https://cursor.com/docs/plugins).

## Installation

### Claude Code

```
/plugin marketplace add laravel/agent-skills
/plugin install laravel-simplifier@laravel
/plugin install laravel-cloud@laravel
/plugin install laravel-nightwatch@laravel
```

### Cursor

Search for **Laravel** in the [Cursor plugin marketplace](https://cursor.com/docs/plugins) panel and install the plugins you need.

## Usage

**Laravel** invoke the agent after a coding session:

```
> Review recent changes using the laravel-simplifier agent
```

**Laravel Cloud** triggers automatically when you ask about deploying or managing Laravel Cloud resources:

```
> Deploy my app to Laravel Cloud
> Set up a database and cache for the staging environment
```

**Laravel Nightwatch** triggers when you ask about configuring Nightwatch:

```
> Configure Nightwatch sampling rates for production
> Set up PII redaction for Nightwatch
```

## Plugins

### Laravel

An agent that reviews recently modified PHP / Laravel code and refines it for clarity, consistency, and maintainability without changing functionality.

- Applies Laravel conventions and PSR-12 standards
- Reduces unnecessary complexity and nesting
- Improves naming and readability
- Focuses on recently modified code by default

### Laravel Cloud

A skill for deploying and managing applications on [Laravel Cloud](https://cloud.laravel.com) using the `cloud` CLI.

- Guides deployment workflows (first deploy, existing apps, environment setup)
- Manages infrastructure resources (databases, caches, domains, buckets)
- Includes operational checklists for multi-step tasks
- Follows the CRUD command patterns of the Cloud CLI

### Laravel Nightwatch

A skill for configuring [Laravel Nightwatch](https://nightwatch.laravel.com) data collection, sampling rates, filtering rules, and redaction policies. Bundles the [Nightwatch MCP server](https://nightwatch.laravel.com/docs/mcp-server) for browsing issues, viewing stack traces, updating statuses, and adding comments.

| Capability | Description |
|---|---|
| Setup & configuration | Guides Nightwatch setup in your application |
| Sampling & filtering | Manages data volume through sampling and filtering rules |
| PII redaction | Protects sensitive data with redaction policies |
| Event optimization | Optimizes event collection for production workloads |

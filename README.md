# Laravel Agents & Skills

A collection of agents and skills for PHP / Laravel development, available as plugins for [Claude Code](https://code.claude.com/docs/en/plugins) and [Cursor](https://cursor.com/docs/plugins).

## Plugins

### Laravel

An agent that reviews recently modified PHP / Laravel code and refines it for clarity, consistency, and maintainability — without changing functionality.

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

- Guides setup and configuration of Nightwatch in your application
- Manages data volume through sampling and filtering
- Protects sensitive data (PII) with redaction policies
- Optimizes event collection for production workloads

## Installation

### Claude Code

```
/install laravel/agent-skills
```

### Cursor

Search for **Laravel** in the [Cursor plugin marketplace](https://cursor.com/docs/plugins) panel and install the plugins you need. Each plugin can be scoped to a project or installed at the user level.

For local development, clone the repo and symlink into Cursor's local plugins directory:

```bash
git clone https://github.com/laravel/agent-skills.git
ln -s "$(pwd)/agent-skills/laravel" ~/.cursor/plugins/local/laravel
ln -s "$(pwd)/agent-skills/laravel-cloud" ~/.cursor/plugins/local/laravel-cloud
ln -s "$(pwd)/agent-skills/laravel-nightwatch" ~/.cursor/plugins/local/laravel-nightwatch
```

**Team marketplace (Cursor Teams / Enterprise):**

1. Go to **Dashboard → Settings → Plugins**
2. In **Team Marketplaces**, click **Import**
3. Paste the GitHub repository URL (`https://github.com/laravel/agent-skills`) and continue
4. Review the parsed plugins — optionally set Team Access groups, then continue
5. Set the marketplace name and description, then save

See the [Cursor plugin reference](https://cursor.com/docs/reference/plugins) for full details on plugin structure and publishing.

## Usage

**Laravel** — invoke the agent after a coding session:

```
> Review recent changes using the laravel-simplifier agent
```

**Laravel Cloud** — triggers automatically when you ask about deploying or managing Laravel Cloud resources:

```
> Deploy my app to Laravel Cloud
> Set up a database and cache for the staging environment
```

**Laravel Nightwatch** — triggers when you ask about configuring Nightwatch:

```
> Configure Nightwatch sampling rates for production
> Set up PII redaction for Nightwatch
```

## Development

After cloning, initialize the submodule to pull the Laravel Cloud skill:

```bash
git clone --recurse-submodules https://github.com/laravel/agent-skills.git
```

Or if already cloned:

```bash
git submodule update --init
```

The submodule uses sparse checkout — only the `skills/deploying-laravel-cloud` directory is checked out from `laravel/cloud-cli`.

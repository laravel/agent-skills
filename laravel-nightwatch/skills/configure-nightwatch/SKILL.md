---
name: configure-nightwatch
description: "Configures Laravel Nightwatch data collection, sampling rates, filtering rules, and redaction policies. Use when setting up Nightwatch, managing data volume, protecting sensitive data (PII), or optimizing event collection for production workloads."
license: MIT
metadata:
  author: laravel
---

# Nightwatch Configuration Guide

Configure Nightwatch data collection to balance observability, performance, and privacy. See the [official docs](https://nightwatch.laravel.com/docs) for full API details and [reference.md](reference.md) for a quick-lookup table by event type, production presets, and verification checklist.

## Data Collection Flow

Events pass through three stages:

1. **Sampling** - Which entry points are captured (requests, commands, scheduled tasks)
2. **Filtering** - Excludes specific events after sampling (queries, cache, mail, etc.)
3. **Redaction** - Modifies captured data to remove/obfuscate sensitive information

```
Request/Command/Scheduled Task
       |
       v
   [Sampling?] ----NO----> Drop entire trace
       | YES
       v
   Events generated
       |
       v
   [Filtering?] ----YES---> Drop specific event
       | NO
       v
   [Redaction] ----------> Store modified data
```

---

## Sampling Configuration

### Global Sample Rates

```bash
NIGHTWATCH_REQUEST_SAMPLE_RATE=0.1      # 10% of requests (recommended production start)
NIGHTWATCH_COMMAND_SAMPLE_RATE=1.0      # Capture all commands
NIGHTWATCH_EXCEPTION_SAMPLE_RATE=1.0    # Always capture exceptions
```

### Route-Based Sampling

Apply different rates to specific routes using the `Sample` middleware:

```php routes/web.php
use Illuminate\Support\Facades\Route;
use Laravel\Nightwatch\Http\Middleware\Sample;

// Sample admin routes at 100%
Route::middleware(Sample::rate(1.0))->prefix('admin')->group(function () {
    // All admin routes sampled fully
});

// Sample API routes at 5%
Route::middleware(Sample::rate(0.05))->prefix('api')->group(function () {
    // API routes sampled sparingly
});

// Always sample critical endpoints
Route::post('/checkout', [CheckoutController::class, 'process'])
    ->middleware(Sample::always());

// Never sample health checks
Route::get('/health', [HealthController::class, 'check'])
    ->middleware(Sample::never());
```

### Unmatched Route Sampling

Handle 404/bot traffic with reduced sampling:

```php routes/web.php
Route::fallback(fn () => abort(404))
    ->middleware(Sample::rate(0.01));  // 1% sampling for unmatched routes
```

### Dynamic Sampling

Sample based on runtime conditions (user role, request attributes):

```php app/Http/Middleware/SampleAdminRequests.php
use Closure;
use Illuminate\Http\Request;
use Laravel\Nightwatch\Facades\Nightwatch;

class SampleAdminRequests
{
    public function handle(Request $request, Closure $next)
    {
        if ($request->user()?->isAdmin()) {
            Nightwatch::sample();  // Always sample admin requests
        }
        return $next($request);
    }
}
```

### Command Sampling

Exclude specific commands from sampling:

```php AppServiceProvider.php
use Illuminate\Console\Events\CommandStarting;
use Illuminate\Support\Facades\Event;
use Laravel\Nightwatch\Facades\Nightwatch;

public function boot(): void
{
    Event::listen(function (CommandStarting $event) {
        if (in_array($event->command, ['schedule:finish', 'horizon:snapshot'])) {
            Nightwatch::dontSample();
        }
    });
}
```

### Vendor Commands

Nightwatch automatically ignores framework/internal commands. Opt-in to capture them:

```php
Nightwatch::captureDefaultVendorCommands();
```

---

## Filtering Configuration

Exclude specific events after sampling to reduce noise and quota usage. See [reference.md](reference.md) for the full per-event-type filtering API.

### Database Queries

**Filter all queries** (disable query collection):

```bash
NIGHTWATCH_IGNORE_QUERIES=true
```

**Filter specific queries** by SQL pattern:

```php AppServiceProvider.php
use Laravel\Nightwatch\Facades\Nightwatch;
use Laravel\Nightwatch\Records\Query;

public function boot(): void
{
    // Filter job table queries (PostgreSQL)
    Nightwatch::rejectQueries(function (Query $query) {
        return str_contains($query->sql, 'into "jobs"');
    });

    // Filter cache table queries (MySQL)
    Nightwatch::rejectQueries(function (Query $query) {
        return str_contains($query->sql, 'from `cache`')
            || str_contains($query->sql, 'into `cache`');
    });
}
```

### Cache Events

**Filter all cache events**:

```bash
NIGHTWATCH_IGNORE_CACHE_EVENTS=true
```

**Filter by cache key patterns**:

```php
Nightwatch::rejectCacheKeys([
    'my-app:users',                    // Exact match
    '/^my-app:posts:/',                // Regex: starts with my-app:posts:
    '/^[a-zA-Z0-9]{40}$/',             // Regex: session IDs
]);
```

**Filter with callback**:

```php
use Laravel\Nightwatch\Records\CacheEvent;

Nightwatch::rejectCacheEvents(function (CacheEvent $cacheEvent) {
    return str_starts_with($cacheEvent->key, 'temp:');
});
```

### Other Event Types

All other event types follow the same pattern — environment variable to disable entirely, or a `reject*` callback for fine-grained control:

| Event Type | Env Var | Callback |
|---|---|---|
| Mail | `NIGHTWATCH_IGNORE_MAIL` | `Nightwatch::rejectMail(fn (Mail $mail) => ...)` |
| Notifications | `NIGHTWATCH_IGNORE_NOTIFICATIONS` | `Nightwatch::rejectNotifications(fn (Notification $n) => ...)` |
| Outgoing Requests | `NIGHTWATCH_IGNORE_OUTGOING_REQUESTS` | `Nightwatch::rejectOutgoingRequests(fn (OutgoingRequest $r) => ...)` |
| Jobs | — | `Nightwatch::rejectQueuedJobs(fn (QueuedJob $job) => ...)` |

See [reference.md](reference.md) for full code examples for each event type.

### Decoupling Job Sampling

Sample jobs independently from parent contexts:

```php
use Illuminate\Support\Facades\Queue;

public function boot(): void
{
    Queue::before(fn () => Nightwatch::sample(rate: 0.5));
}
```

---

## Redaction Configuration

### Request Redaction

**Redact sensitive headers** (Authorization, Cookie, X-XSRF-TOKEN redacted by default):

```bash
# Customize redacted headers
NIGHTWATCH_REDACT_HEADERS=Authorization,Cookie,Proxy-Authorization,X-API-Key
```

**Redact request payloads** (disabled by default):

```bash
# Enable payload capture
NIGHTWATCH_CAPTURE_REQUEST_PAYLOAD=true

# Customize redacted fields
NIGHTWATCH_REDACT_PAYLOAD_FIELDS=password,password_confirmation,ssn,credit_card
```

**Programmatic redaction**:

```php
use Laravel\Nightwatch\Facades\Nightwatch;
use Laravel\Nightwatch\Records\Request;

Nightwatch::redactRequests(function (Request $request) {
    $request->url = str_replace('secret', '***', $request->url);
    $request->ip = preg_replace('/\d+$/', '***', $request->ip);
});
```

### Other Event Types

All event types support programmatic redaction via `Nightwatch::redact*()` callbacks:

| Event Type | Method | Redactable Fields |
|---|---|---|
| Queries | `redactQueries(fn (Query $q) => ...)` | `$q->sql` |
| Cache | `redactCacheEvents(fn (CacheEvent $e) => ...)` | `$e->key` |
| Commands | `redactCommands(fn (Command $c) => ...)` | `$c->command` |
| Exceptions | `redactExceptions(fn (Exception $e) => ...)` | `$e->message` |
| Mail | `redactMail(fn (Mail $m) => ...)` | `$m->subject` |
| Outgoing Requests | `redactOutgoingRequests(fn (OutgoingRequest $r) => ...)` | `$r->url` |

See [reference.md](reference.md) for full code examples for each redaction type.

---

## Verifying Configuration

### Check Sampling

Set `NIGHTWATCH_REQUEST_SAMPLE_RATE=1.0` in development, trigger requests, and confirm events appear in the Nightwatch dashboard. Lower to your production target and verify volume drops proportionally.

### Test Filtering

Add temporary logging inside a reject callback to confirm the right events match, then remove the logging:

```php
Nightwatch::rejectQueries(function (Query $query) {
    $shouldReject = str_contains($query->sql, 'into "jobs"');
    if ($shouldReject) {
        logger()->debug('Nightwatch filtered query', ['sql' => $query->sql]);
    }
    return $shouldReject;
});
```

### Validate Redaction

Trigger a request containing sensitive data. Inspect the event in the Nightwatch dashboard and confirm fields show `***` instead of real values.

### Production Checklist

- [ ] Sampling rates appropriate for traffic volume
- [ ] Noisy events filtered (cache, certain queries)
- [ ] Sensitive data redacted (PII, tokens, credentials)
- [ ] Exceptions always captured (`NIGHTWATCH_EXCEPTION_SAMPLE_RATE=1.0`)
- [ ] Tested in development with full sampling before deploying
- [ ] Monitoring event quota usage in Nightwatch dashboard

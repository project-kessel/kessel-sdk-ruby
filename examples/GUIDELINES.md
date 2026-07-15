# Examples Directory Guidelines

## Purpose

This directory contains runnable example scripts demonstrating SDK features against a live Kessel server. Examples are not run in CI, not covered by RSpec, and excluded from RuboCop linting. They exist for developer reference and manual testing.

## File Header -- Required

Every example must start with these two lines, in this order:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
```

## Naming

- Use `snake_case.rb` named after the operation or feature: `check.rb`, `report_resource.rb`, `list_workspaces.rb`.
- Name should match the gRPC RPC method or SDK feature being demonstrated.

## Two Styles Exist -- Use the Newer One

### Older style (do not use for new examples)

Top-level `include`, `begin/rescue Exception => e`, no re-raise. Found in `check.rb`, `auth.rb`, `delete_resource.rb`, `check_for_update.rb`, `streamed_list_objects.rb`, `report_resource.rb`, `fetch_workspaces.rb`, `list_workspaces.rb`.

### Newer style (required for all new examples)

Wrap in a class with `class << self`, rescue `StandardError` (not `Exception`), and re-raise with bare `raise`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'kessel-sdk'

class FeatureExample
  class << self
    include Kessel::Inventory::V1beta2

    def run
      client = KesselInventoryService::ClientBuilder.new(ENV.fetch('KESSEL_ENDPOINT', nil))
                                                    .insecure
                                                    .build

      # ... demonstrate the feature ...
    rescue StandardError => e
      p "Error: #{e}"
      raise
    end
  end
end

FeatureExample.run
```

Key differences from older style:
- Class wrapper with `class << self` instead of top-level `include`
- `rescue StandardError => e` instead of `rescue Exception => e`
- Bare `raise` after logging instead of swallowing the error
- `raise` not `raise e` (bare form preserves the original backtrace)

The file `check_for_update_bulk.rb` demonstrates this pattern. The file `check_bulk.rb` uses a class wrapper but still has `rescue Exception => e` and `raise e` -- when updating it or similar files, switch to `StandardError` and bare `raise`.

## Environment Variables

- Use `ENV.fetch('VAR_NAME', nil)` -- never `ENV['VAR_NAME']`.
- Load env via `require 'dotenv/load'` as the first require after the header.
- The `.env.sample` defines the available variables:
  - `KESSEL_ENDPOINT` -- gRPC target (e.g., `localhost:9000`)
  - `AUTH_CLIENT_ID` / `AUTH_CLIENT_SECRET` -- OIDC credentials
  - `AUTH_DISCOVERY_ISSUER_URL` -- OIDC issuer for discovery
  - `RBAC_BASE_ENDPOINT` -- HTTP base URL for RBAC API
- Never commit `.env` files. The `.gitignore` covers them.

## Require Order

1. `dotenv/load` (loads `.env` before any other code runs)
2. `kessel-sdk` (the SDK entrypoint)
3. Any additional stdlib or gems needed (e.g., `net/http`, `json`, `base64`)

Exception: `console_principal.rb` does not use `dotenv/load` because it does not need environment variables.

## Dependencies

- Examples have their own `Gemfile` at `examples/Gemfile` with `dotenv`, `kessel-sdk` (path reference to `..`), and `openid_connect`.
- Run `bundle install` inside `examples/` before running any example.
- Do not add the examples `Gemfile` dependencies to the root `Gemfile` or gemspec.

## ClientBuilder Usage

- Show the fluent `ClientBuilder` pattern -- `.insecure.build` for local dev, `.oauth2_client_authenticated(...).build` for auth flows.
- Optionally include a commented-out `Stub.new` alternative to show the non-builder approach.
- Build the client once, not per-request.

## Output

- Print results to stdout using `p` (not `puts`) for inspect-style output. This is the established convention across all existing examples.
- Include descriptive string labels before printing response objects (e.g., `p 'check response received successfully:'`).

## RBAC Helpers in Examples

When demonstrating RBAC operations, `include Kessel::RBAC::V2` alongside `Kessel::Inventory::V1beta2` to use factory helpers (`principal_subject`, `workspace_resource`, etc.) instead of constructing protobuf objects manually. See `check_bulk.rb` and `list_workspaces.rb`.

## Rakefile

- Every example should have a corresponding Rake task in `examples/Rakefile`.
- Task name matches the filename without `.rb` extension.
- Task description starts with `run` and names the example.

```ruby
desc 'run feature_name sample'
task :feature_name do
  ruby 'feature_name.rb'
end
```

- The Rakefile auto-copies `.env.sample` to `.env` if `.env` does not exist.

## README Table

When adding a new example, add a row to the examples table in the root `README.md` under `## Examples`. Format:

```markdown
| `filename.rb` | Short description of what it demonstrates |
```

## What Examples Are Not

- Examples are not tests -- do not add assertions or RSpec expectations.
- Examples are not run in CI -- they require a live Kessel server.
- Examples are excluded from RuboCop -- style rules are relaxed, but follow the newer class-based pattern for consistency.
- Examples are excluded from SimpleCov coverage.

## Checklist for Adding a New Example

1. Create `examples/feature_name.rb` using the newer class-based style.
2. Add a Rake task in `examples/Rakefile`.
3. Add the example to the `## Examples` table in `README.md`.
4. If new env vars are needed, add them to `examples/.env.sample`.
5. Verify it runs against a local Kessel instance.

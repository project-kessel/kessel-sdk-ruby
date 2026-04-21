# Security Guidelines

## Authentication Architecture

### OAuth 2.0 Client Credentials Flow
- Authentication is implemented in `lib/kessel/auth.rb` using the `openid_connect` gem as a lazy-loaded optional dependency.
- The `openid_connect` gem is NOT a runtime dependency in the gemspec -- it is only required in examples via `examples/Gemfile`. The SDK uses `require 'openid_connect'` inside `check_dependencies!` and raises `OAuthDependencyError` if missing.
- Avoid adding `openid_connect` as a hard runtime dependency; it should remain optional so consumers who do not need OAuth are not forced to install it.

### Token Caching and Thread Safety
- `OAuth2ClientCredentials` uses a `Mutex` (`@token_mutex`) to synchronize token refresh across threads. Maintain this pattern -- token operations should remain thread-safe.
- The `get_token` method uses a double-check pattern: it checks `token_valid?` before acquiring the lock, then checks again inside the synchronized block to prevent redundant refreshes.
- Cached tokens are frozen with `.freeze` after creation in the `refresh` method. Preserve the freeze call -- it prevents accidental mutation of shared token state.

### Token Expiration Window
- `EXPIRATION_WINDOW = 300` (5 minutes) is applied before the actual `expires_at` to proactively refresh tokens. Do not reduce this window below a reasonable threshold to avoid edge-case expiration during in-flight requests.
- `DEFAULT_EXPIRES_IN = 3600` is used as a fallback when the token response does not include `expires_in`. If changing this, ensure it remains conservative.

### Credential Error Handling
- Authentication errors are wrapped in `OAuthAuthenticationError` with the original error message. Avoid exposing raw token data, client secrets, or full stack traces in error messages passed to `OAuthAuthenticationError`.
- OIDC discovery failures also raise `OAuthAuthenticationError` with the provider URL. This is acceptable since the provider URL is not a secret.

## gRPC Channel Security

### ClientBuilder Credential Validation
- `ClientBuilder#validate_credentials` enforces that call credentials (authentication tokens) cannot be composed with insecure channels. This prevents sending bearer tokens over plaintext connections.
- The `insecure` method explicitly sets `@call_credentials = nil` and `@channel_credentials = :this_channel_is_insecure`. The insecure mode should not be used in production.
- When no channel credentials are provided, `build` defaults to `GRPC::Core::ChannelCredentials.new` (TLS). This secure-by-default behavior should be preserved.

### Builder Authentication Methods
- Use `oauth2_client_authenticated` for the standard OAuth2 flow with automatic token injection via `oauth2_call_credentials`.
- Use `authenticated` for custom call/channel credential pairs.
- Use `unauthenticated` only when the service does not require authentication but still needs a TLS channel.
- Use `insecure` only for local development. The builder pattern enforces that `insecure` + call credentials raises an error at configuration time, not at request time.

### Bearer Token Injection
- `Kessel::GRPC#oauth2_call_credentials` creates a `GRPC::Core::CallCredentials` proc that calls `auth.get_token` on every RPC invocation. This ensures tokens are refreshed automatically per-call.
- The `OAuth2AuthRequest` class (for HTTP requests) similarly calls `get_token` on each `configure_request` invocation. Both paths use the same cached/thread-safe token mechanism.

## HTTP Client Security (RBAC V2)

### Host/Port Validation
- `check_http_client` in `lib/kessel/rbac/v2_http.rb` validates that a user-supplied `Net::HTTP` client matches the target URI's host and port. This prevents request smuggling where a pre-configured HTTP client could be directed to an unintended host.
- Avoid removing or weakening this validation.

### Organization ID Header
- RBAC workspace requests inject `x-rh-rbac-org-id` as a request header. This header is a tenant identifier, not a secret, but should be included for proper multi-tenant isolation.

### Auth Optional Pattern
- The `auth` parameter in `fetch_workspace` is optional (`auth&.configure_request`). When auth is `nil`, the request proceeds unauthenticated. Tests verify both authenticated and unauthenticated code paths -- maintain this coverage.

## Secrets and Credential Management

### Environment Variables
- Examples use `dotenv` to load credentials from `.env` files. The `.gitignore` correctly excludes `.env`, `.env.local`, and `.env.*.local`.
- Credential-bearing environment variables follow the pattern: `AUTH_CLIENT_ID`, `AUTH_CLIENT_SECRET`, `AUTH_DISCOVERY_ISSUER_URL`, `KESSEL_ENDPOINT`, `RBAC_BASE_ENDPOINT`.
- Avoid committing `.env` files or hardcoding credentials in examples.

### Gitignore Coverage
- `.gitignore` excludes `credentials.yml`, `secrets.yml`, and all `.env` variants. When adding new configuration files that may contain secrets, update `.gitignore` accordingly.

### Gemspec MFA Requirement
- The gemspec sets `metadata['rubygems_mfa_required'] = 'true'`, enforcing multi-factor authentication for gem publishing. Preserve this setting.

## Dependency Security

### Bundler-Audit
- `bundler-audit` is included as a dev dependency and run in CI (`bundle exec bundle-audit check --update`). The release process explicitly includes this step.
- CI runs `bundle-audit` with `continue-on-error: true`. Consider making this a blocking check for stricter enforcement.

### Dependabot
- Dependabot is configured in `.github/dependabot.yml` for both `bundler` and `github-actions` ecosystems on a daily schedule. Avoid reducing this frequency.

### Minimum Ruby Version
- The gemspec requires `ruby >= 3.3`. The CI matrix tests against Ruby 3.3 and 3.4. Do not lower the minimum Ruby version without reviewing security implications of older Ruby releases.

### gRPC Version Floor
- The gemspec pins `grpc >= 1.73.0`. This is a security-relevant dependency -- gRPC versions below this may have known vulnerabilities. Only raise this floor, never lower it.

## Code Generation Security

### Protobuf Files Are Generated -- Do Not Hand-Edit
- All files under `lib/kessel/inventory/v*/**/*`, `lib/google/**/*`, and `lib/buf/**/*` are generated by `buf generate` from `buf.build/project-kessel/inventory-api`. Manual edits will be overwritten.
- The `buf-generate` GitHub Action runs on a schedule (every 6 hours) and creates PRs automatically. Review these PRs for unexpected schema changes that could affect authorization semantics (e.g., changes to `CheckRequest`, `SubjectReference`, `ResourceReference`).
- RuboCop is configured to exclude all generated files. Security-sensitive linting rules only apply to hand-written code.

## Testing Conventions for Security Code

### Mock External Dependencies
- Tests for `OAuth2ClientCredentials` mock the `openid_connect` gem via `stub_const` and `allow_any_instance_of`. When writing new auth tests, follow this pattern rather than making real OIDC calls.
- The `create_oidc_client` method is the seam for mocking token acquisition. Mock at this level, not deeper into the OpenIDConnect library.

### Credential Validation Tests
- `inventory_spec.rb` tests all credential configurations including the insecure+auth rejection. When adding new builder methods, add corresponding `validate_credentials` test cases.
- Test both the positive path (valid config builds successfully) and negative path (invalid config raises at configuration time, not at request time).

## Interface Contracts

### AuthRequest Interface
- Any new authentication mechanism should implement the `AuthRequest` module and its `configure_request` method. The base module raises `NotImplementedError` to enforce this contract.
- RBS type signatures in `sig/kessel/auth.rbs` define the expected types. Keep type signatures in sync when modifying authentication classes.

### Frozen String Literals
- All source files use `# frozen_string_literal: true`. This prevents accidental string mutation that could lead to injection vulnerabilities in header values or token strings. Maintain this pragma on all new files.

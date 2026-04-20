# Error Handling Guidelines

## Custom Exception Hierarchy

All SDK-specific exceptions inherit from `StandardError`. There are exactly two custom exception classes, both defined in `Kessel::Auth`:

- **`OAuthDependencyError`** -- Raised when the optional `openid_connect` gem is not installed. Has a default message; accepts a custom one.
- **`OAuthAuthenticationError`** -- Raised when any OAuth operation fails (token acquisition, OIDC discovery). Has a default message; accepts a custom one.

Do not create additional exception classes without placing them under an appropriate `Kessel::` module and inheriting from `StandardError`.

## Error Wrapping Convention

The SDK wraps lower-level exceptions into domain-specific exceptions by catching `StandardError` and re-raising with a contextual message that preserves the original error text:

```ruby
rescue StandardError => e
  raise OAuthAuthenticationError, "Failed to obtain client credentials token: #{e.message}"
end
```

Follow this pattern for all domain-boundary error translation:
1. Rescue `StandardError` (never `Exception`).
2. Raise the appropriate custom exception class.
3. Include a human-readable prefix describing the operation that failed.
4. Append the original `e.message` after a colon.

## Dependency Checking Pattern

Optional gem dependencies are validated at the point of use via `check_dependencies!`:

```ruby
def check_dependencies!
  require 'openid_connect'
rescue LoadError
  raise OAuthDependencyError,
        'OAuth functionality requires the openid_connect gem. Add "gem \'openid_connect\'" to your Gemfile.'
end
```

Rules:
- Call `check_dependencies!` in the constructor so failures surface immediately at initialization, not at first use.
- Rescue `LoadError` specifically (not `StandardError`).
- Raise `OAuthDependencyError` with a message that names the missing gem and tells the user how to install it.

## Validation Errors in ClientBuilder

`ClientBuilder` raises plain `RuntimeError` (bare `raise 'message'`) for configuration validation, not custom exception classes. There are two validation points:

1. **Constructor** -- Rejects `nil` or non-String targets: `raise 'Invalid target type'`
2. **`validate_credentials`** -- Rejects call credentials on insecure channels: `raise 'Invalid credential configuration: can not authenticate with insecure channel'`

`validate_credentials` is called from every authentication method (`authenticated`, `unauthenticated`, `oauth2_client_authenticated`, `insecure`) so invalid configurations fail fast before `build` is called.

## RBAC HTTP Response Errors

The `RBAC::V2` module raises `RuntimeError` for HTTP-layer problems with descriptive messages:

- Non-success HTTP responses: `"Error while fetching the workspace of type #{workspace_type}. Call returned status code #{response.code}"`
- Unexpected result count: `"Unexpected number of #{workspace_type} workspaces: #{count}"`
- Host/port mismatch on user-supplied `http_client`: `'http client host and port do not match rbac_base_endpoint'`

These use `raise "message"` (RuntimeError), not custom exception classes.

## AuthRequest Interface Contract

The `AuthRequest` module defines an interface method that raises `NotImplementedError`:

```ruby
def configure_request(request)
  raise NotImplementedError, "#{self.class} must implement #configure_request"
end
```

Any class including `AuthRequest` must override `configure_request` or callers will get `NotImplementedError`. The message dynamically includes the offending class name.

## Silent Failure in token_valid?

`token_valid?` rescues all `StandardError` and returns `false` instead of propagating. This is intentional -- a corrupted or unreadable cached token should trigger a refresh, not crash:

```ruby
def token_valid?
  # ...check logic...
rescue StandardError
  false
end
```

This is the only place in the SDK where errors are silently swallowed. Do not replicate this pattern elsewhere without explicit justification.

## Example-Level Error Handling

- **Older examples** (`check.rb`, `auth.rb`, `delete_resource.rb`, etc.): `rescue Exception => e` without re-raise. Log and swallow.
- **Newer examples** (`check_bulk.rb`): `rescue Exception => e` with `raise e` to re-raise after logging.
- **Newest example** (`check_for_update_bulk.rb`): Uses `rescue StandardError => e` with bare `raise` (preferred).

For new examples and application code, always rescue `StandardError` (not `Exception`) and re-raise with bare `raise` after logging.

## Thread Safety in Error Paths

`OAuth2ClientCredentials#get_token` uses a `Mutex` around token refresh. The `rescue` block is inside `@token_mutex.synchronize`, ensuring that:
- Only one thread attempts refresh at a time.
- A failed refresh raises `OAuthAuthenticationError` to the calling thread while the mutex is released.
- Other threads waiting on the mutex will attempt their own refresh after the failure.

Do not move the rescue block outside the synchronize block.

## gRPC Errors Are Not Wrapped

The SDK does not catch or wrap `GRPC::BadStatus` or its subclasses. gRPC call errors propagate directly to the caller as native gRPC exceptions. This is by design -- the SDK is a thin client layer.

Do not add blanket gRPC error wrapping in the SDK library code. Callers handle gRPC errors in their own rescue blocks.

## Error Handling in Tests

Tests verify error behavior using RSpec's `raise_error` matcher with both exception class and message pattern:

```ruby
expect { ... }.to raise_error(Kessel::Auth::OAuthDependencyError, /OAuth functionality requires/)
expect { ... }.to raise_error(Kessel::Auth::OAuthAuthenticationError, /Failed to obtain.*Token request failed/)
```

Rules for testing errors:
- Always assert both the exception class and a message regex.
- Use regex patterns (not exact strings) to match the dynamic portion of composed error messages.
- Test the error path for every public method that can raise.

## Summary of Exception Types by Layer

| Layer | Exception Type | When |
|-------|---------------|------|
| `Auth` (dependency) | `OAuthDependencyError` | `openid_connect` gem missing |
| `Auth` (runtime) | `OAuthAuthenticationError` | Token acquisition or OIDC discovery fails |
| `Auth` (interface) | `NotImplementedError` | `AuthRequest#configure_request` not implemented |
| `ClientBuilder` | `RuntimeError` | Invalid target or credential configuration |
| `RBAC::V2` | `RuntimeError` | HTTP errors, unexpected response data, client mismatch |
| gRPC calls | `GRPC::BadStatus` subclasses | Server errors, network failures (not wrapped) |

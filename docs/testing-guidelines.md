# Testing Guidelines

## Frameworks and Tools

- **Test framework**: RSpec with constraint `~> 3.12` (currently 3.13.x), using `rspec-mocks` and `rspec-expectations`
- **Coverage**: SimpleCov 0.22, activated only via `COVERAGE=true` env var (not always-on)
- **Linting**: RuboCop with constraint `~> 1.57` (currently 1.81.x), runs in CI alongside tests (with `continue-on-error: true`)
- **CI matrix**: Ruby 3.3 and 3.4 on ubuntu-latest via GitHub Actions

## Running Tests

- `bundle exec rspec` -- run all specs
- `rake spec` -- equivalent rake task
- `rake test_coverage` -- runs specs with `COVERAGE=true`
- `rake` (default) -- runs both `spec` and `rubocop`
- CI runs `bundle exec rspec` (no coverage flag), then `rubocop --parallel`

## RSpec Configuration

- `.rspec` flags: `--color --require spec_helper --format documentation`
- `verify_partial_doubles` is **enabled** -- all `allow(obj).to receive(:method)` calls are verified against the real interface
- Specs run in **random order** (`config.order = :random`) -- tests must be independent
- The `grpc` gem is filtered from backtraces (`config.filter_gems_from_backtrace 'grpc'`)
- Slowest 10 examples are profiled on every run (`config.profile_examples = 10`)
- `Metrics/BlockLength` RuboCop cop is **excluded** for `spec/**/*` -- no block length limits in tests

## File and Directory Structure

- All specs live under `spec/` mirroring `lib/kessel/` structure:
  - `spec/kessel_spec.rb` -- top-level SDK structure and module loading
  - `spec/kessel/auth_spec.rb` -- authentication classes
  - `spec/kessel/inventory_spec.rb` -- inventory client builder
  - `spec/kessel/rbac/v2_spec.rb` -- RBAC v2 helpers and HTTP calls
- `spec/spec_helper.rb` loads the entire SDK via `require_relative '../lib/kessel-sdk'`
- Each spec file starts with `# frozen_string_literal: true` and `require 'spec_helper'`

## Coverage Configuration

SimpleCov groups when enabled:
- `Core` -- `lib/kessel`
- `Generated` -- `lib/kessel/inventory`
- `Google` -- `lib/google`
- `Buf` -- `lib/buf`
- Filters out `spec/` and `examples/` directories

## Test Patterns and Conventions

### Describe/Context Structure

Tests use a consistent hierarchy: `RSpec.describe <Module>` at the top, `describe '#method_name'` for instance methods, and `context 'when ...'` for conditional branches. String-described top-level groups (e.g., `RSpec.describe 'Kessel SDK'`) are used for structural/integration-style checks.

### Module Inclusion for Testing Module Methods

When testing a Ruby module's methods, `include` the module in the test context rather than instantiating a class:

```ruby
RSpec.describe Kessel::RBAC::V2 do
  include Kessel::RBAC::V2
  # now call module methods directly: fetch_default_workspace(...)
end
```

### Mocking External Dependencies

**gRPC stubs and credentials** -- Mock `GRPC::Core::ChannelCredentials`, `GRPC::Core::CallCredentials`, and service stub classes using `double` and `allow`:

```ruby
let(:mock_stub_class) { double('ServiceClass') }
let(:channel_credentials) { double('ChannelCredentials') }
allow(GRPC::Core::ChannelCredentials).to receive(:new).and_return(channel_credentials)
allow(mock_stub_class).to receive(:new).and_return(mock_stub_instance)
```

**Optional gem dependencies** -- Use `stub_const` to define modules that may not be installed (e.g., `OpenIDConnect`), and stub `require` to control `LoadError` paths:

```ruby
stub_const('OpenIDConnect', Module.new)
stub_const('OpenIDConnect::Client', Class.new { ... })
allow_any_instance_of(Kessel::Auth::OAuth2ClientCredentials)
  .to receive(:require).with('openid_connect').and_return(true)
```

**HTTP calls** -- Mock `Net::HTTP`, `Net::HTTP::Get`, and URI parsing. Build the full mock chain:

```ruby
allow(Net::HTTP).to receive(:new).with('localhost', 8888).and_return(mock_http)
allow(Net::HTTP::Get).to receive(:new).with(mock_uri).and_return(mock_request)
allow(mock_http).to receive(:request).and_return(mock_response)
allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
```

### Testing Private Methods

Use `obj.send(:method_name)` to invoke private methods under test (e.g., `oauth.send(:refresh)`, `oauth.send(:token_valid?)`, `builder.send(:validate_credentials)`).

### Testing Instance Variables

Use `instance_variable_get` to assert internal state and `instance_variable_set` to set up preconditions:

```ruby
expect(builder.instance_variable_get(:@call_credentials)).to eq(call_credentials)
oauth.instance_variable_set(:@cached_token, expired_token)
```

### Method Chaining / Builder Pattern

Assert builder methods return `self` for chaining:

```ruby
result = builder.insecure
expect(result).to eq(builder)
```

### Error Testing

Use `raise_error` with class and message regex:

```ruby
expect { ... }.to raise_error(Kessel::Auth::OAuthDependencyError, /requires the openid_connect gem/)
```

### let Declarations

Use `let` for all test fixtures and doubles. Use `let` blocks (lazy evaluation) not `let!`. Group related `let` declarations at the top of their `describe`/`context` block.

### Enumerator Testing

For methods returning `Enumerator`, call `.to_a` to materialize results and assert on length/content. Use dynamic `allow(...).to receive(...) do |request|` blocks to simulate paginated responses.

## What NOT to Test

- Do not test auto-generated protobuf files (`lib/kessel/inventory/v*/`) directly -- only verify they load without error
- Do not add integration tests that make real gRPC or HTTP calls -- all external I/O is mocked
- Example files (`examples/`) are excluded from both specs and coverage

## CI Expectations

- All specs must pass on both Ruby 3.3 and 3.4
- RuboCop violations do not block CI (`continue-on-error: true`) but should be fixed
- `bundle-audit` runs for security checks (also non-blocking)
- No coverage threshold is enforced in CI

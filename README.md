# Kessel SDK for Ruby

[![CI](https://github.com/project-kessel/kessel-sdk-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/project-kessel/kessel-sdk-ruby/actions/workflows/ci.yml)

The official Ruby gRPC client SDK for [Project Kessel](https://github.com/project-kessel) services. It provides generated protobuf/gRPC bindings for the Kessel Inventory API, a fluent client builder with credential validation, OAuth 2.0 Client Credentials authentication (via OIDC), and RBAC convenience helpers for workspace operations.

Published on RubyGems as [`kessel-sdk`](https://rubygems.org/gems/kessel-sdk).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'kessel-sdk'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install kessel-sdk
```

### Authentication (Optional)

The SDK supports OAuth 2.0 Client Credentials flow. To use authentication features, add the OpenID Connect gem:

```ruby
gem 'kessel-sdk'
gem 'openid_connect', '~> 2.0'  # Optional - only for authentication
```

The `openid_connect` gem is intentionally not a hard runtime dependency. Consumers who do not need OAuth are not forced to install it or its transitive dependencies.

## Project Structure

```
lib/
  kessel-sdk.rb              # Single entrypoint (require 'kessel-sdk')
  kessel/
    auth.rb                  # OAuth2 Client Credentials, OIDC discovery
    grpc.rb                  # gRPC credential helpers
    inventory.rb             # ClientBuilder base class, client_builder_for_stub
    version.rb               # Kessel::Inventory::VERSION
    inventory/
      v1/                    # Health check service (stable)
      v1beta1/               # Legacy typed K8s resources/relationships
      v1beta2/               # Current unified inventory service (primary API)
    rbac/
      v2.rb                  # Workspace fetch, list_workspaces enumerator
      v2_helpers.rb          # Factory methods for protobuf references
      v2_http.rb             # HTTP request helpers for RBAC API
sig/                         # RBS type signatures for hand-written code
spec/                        # RSpec test suite
examples/                    # Working examples with dotenv configuration
docs/                        # Domain-specific guidelines (see Documentation below)
```

Files under `lib/kessel/inventory/v*/`, `lib/google/`, and `lib/buf/` are **generated** by `buf generate` and must never be hand-edited. They are automatically regenerated every 6 hours via CI.

## Usage

Load the complete SDK via the single entrypoint:

```ruby
require 'kessel-sdk'
```

### Building a Client

The recommended way to create gRPC clients is with the **`ClientBuilder` fluent API**, which enforces credential validation at configuration time. Every gRPC service module exposes a `ClientBuilder` constant.

#### Insecure (Development Only)

```ruby
include Kessel::Inventory::V1beta2

client = KesselInventoryService::ClientBuilder.new('localhost:9000')
                                              .insecure
                                              .build
```

#### OAuth2 Client Credentials (Production)

```ruby
include Kessel::Inventory::V1beta2
include Kessel::Auth

# Discover the token endpoint via OIDC
discovery = fetch_oidc_discovery('https://sso.example.com/auth/realms/my-realm')

# Create OAuth2 credentials
oauth = OAuth2ClientCredentials.new(
  client_id: 'my-app',
  client_secret: 'my-secret',
  token_endpoint: discovery.token_endpoint
)

# Build the client -- tokens are cached and refreshed automatically
client = KesselInventoryService::ClientBuilder.new('kessel.example.com:443')
                                              .oauth2_client_authenticated(oauth2_client_credentials: oauth)
                                              .build
```

#### Custom or No Credentials

```ruby
# Custom call/channel credentials
client = KesselInventoryService::ClientBuilder.new(target)
                                              .authenticated(call_credentials: creds, channel_credentials: ch_creds)
                                              .build

# No call credentials (TLS channel only)
client = KesselInventoryService::ClientBuilder.new(target)
                                              .unauthenticated
                                              .build
```

Build the client **once at application startup and reuse it**. The underlying gRPC channel manages its own HTTP/2 connection pool.

### Check Permissions

```ruby
include Kessel::Inventory::V1beta2

client = KesselInventoryService::ClientBuilder.new('localhost:9000')
                                              .insecure
                                              .build

subject_reference = SubjectReference.new(
  resource: ResourceReference.new(
    reporter: ReporterReference.new(type: 'rbac'),
    resource_id: 'user123',
    resource_type: 'principal'
  )
)

resource = ResourceReference.new(
  reporter: ReporterReference.new(type: 'rbac'),
  resource_id: 'workspace456',
  resource_type: 'workspace'
)

begin
  response = client.check(
    CheckRequest.new(
      object: resource,
      relation: 'inventory_host_view',
      subject: subject_reference
    )
  )
  puts "Permission check result: #{response.allowed}"
rescue GRPC::BadStatus => e
  puts "gRPC error: #{e.message}"
end
```

### Bulk Permission Checks

```ruby
include Kessel::Inventory::V1beta2
include Kessel::RBAC::V2

client = KesselInventoryService::ClientBuilder.new('localhost:9000')
                                              .insecure
                                              .build

response = client.check_bulk(
  CheckBulkRequest.new(items: [
    CheckBulkRequestItem.new(
      object: workspace_resource('workspace_123'),
      relation: 'view_widget',
      subject: principal_subject('bob', 'redhat')
    ),
    CheckBulkRequestItem.new(
      object: workspace_resource('workspace_456'),
      relation: 'use_widget',
      subject: principal_subject('alice', 'redhat')
    )
  ])
)

response.pairs.each do |pair|
  if pair.item
    puts "Allowed: #{pair.item.allowed}"
  elsif pair.error
    puts "Error: #{pair.error.message}"
  end
end
```

### List Workspaces (Streaming with Auto-Pagination)

```ruby
include Kessel::Inventory::V1beta2
include Kessel::RBAC::V2

client = KesselInventoryService::ClientBuilder.new('localhost:9000')
                                              .insecure
                                              .build

list_workspaces(client, principal_subject('alice', 'redhat'), 'view_document').each do |response|
  puts response
end
```

### Available Services (V1beta2)

The primary service is **`KesselInventoryService`** with these RPCs:

| RPC | Description |
|-----|-------------|
| `check` | Check if a subject has a relation on a resource |
| `check_self` | Check using the caller's identity from auth context |
| `check_for_update` | Strongly consistent check (use before writes) |
| `check_bulk` | Batch permission checks (up to 1000 items) |
| `check_self_bulk` | Batch self-checks |
| `check_for_update_bulk` | Batch strongly consistent checks |
| `report_resource` | Report resource state to inventory |
| `delete_resource` | Delete a resource from inventory |
| `streamed_list_objects` | Stream objects a subject has a relation to |
| `streamed_list_subjects` | Stream subjects that have a relation to a resource |

### RBAC Helper Methods

The `Kessel::RBAC::V2` module provides factory methods for common protobuf references (all use `reporter_type: 'rbac'`):

- `workspace_resource(id)` / `role_resource(id)` -- `ResourceReference` factories
- `principal_resource(id, domain)` -- `ResourceReference` with ID formatted as `"domain/id"`
- `principal_subject(id, domain)` -- `SubjectReference` wrapping a principal resource
- `subject(resource_ref, relation)` -- generic `SubjectReference` factory
- `fetch_default_workspace(endpoint, org_id, auth:, http_client:)` -- fetch default workspace via RBAC HTTP API
- `fetch_root_workspace(endpoint, org_id, auth:, http_client:)` -- fetch root workspace via RBAC HTTP API
- `list_workspaces(inventory, subject, relation)` -- lazy `Enumerator` with auto-pagination

## Type Safety

This library includes RBS type signatures for enhanced type safety in Ruby. The type definitions are located in the `sig/` directory and cover:

- Core library interfaces
- Configuration structures
- OAuth authentication classes
- gRPC client builders

To use with type checkers like Steep or Sorbet, ensure the `sig/` directory is in your type checking configuration.

## Development

### Prerequisites

- Ruby 3.3 or higher
- [buf](https://buf.build) for protobuf/gRPC code generation

Install buf:
```bash
# On macOS
brew install bufbuild/buf/buf

# On Linux
curl -sSL "https://github.com/bufbuild/buf/releases/latest/download/buf-$(uname -s)-$(uname -m)" -o "/usr/local/bin/buf" && chmod +x "/usr/local/bin/buf"

# Or see https://docs.buf.build/installation for other options
```

### Setup

```bash
# Install dependencies
bundle install

# Generate gRPC code from Kessel Inventory API
buf generate
```

### Testing

```bash
# Run tests
bundle exec rspec

# Run with coverage
COVERAGE=1 bundle exec rspec

# Run linting
bundle exec rubocop

# Security audit
bundle exec bundler-audit
```

### Code Generation

This library uses [buf](https://buf.build) to generate Ruby gRPC code from the official Kessel Inventory API protobuf definitions hosted at `buf.build/project-kessel/inventory-api`.

The generation is configured in `buf.gen.yaml`.

To regenerate the code:

```bash
buf generate
```

This will download the latest protobuf definitions and generate fresh Ruby classes in the `lib/` directory.

### Building and Installing Locally

```bash
# Build and install the gem locally
rake install_local
```

## Examples

The `examples/` directory contains working examples. Set up environment variables in `examples/.env` before running.

| Example | Description |
|---------|-------------|
| `auth.rb` | OAuth 2.0 authentication with ClientBuilder |
| `check.rb` | Permission checking |
| `check_bulk.rb` | Bulk permission checks |
| `check_for_update.rb` | Strongly consistent update checks |
| `check_for_update_bulk.rb` | Bulk strongly consistent update checks |
| `delete_resource.rb` | Deleting resources |
| `fetch_workspaces.rb` | Fetching workspaces via RBAC HTTP API |
| `list_workspaces.rb` | Listing workspaces with auto-pagination |
| `report_resource.rb` | Reporting resource state |
| `console_principal.rb` | Building principals from `x-rh-identity` headers |
| `streamed_list_objects.rb` | Streaming resource lists |

Run examples:

```bash
cd examples
bundle install
ruby check.rb
```

## Documentation

Detailed domain-specific guidelines are maintained in the `docs/` directory:

- **[API Contracts](docs/api-contracts-guidelines.md)** -- Protobuf code generation, module/namespace mapping, ClientBuilder API, request/response patterns, and RBS type signatures
- **[Integration](docs/integration-guidelines.md)** -- gRPC client construction, authentication flows, RBAC helpers, streaming/pagination, and environment configuration
- **[Security](docs/security-guidelines.md)** -- Token caching thread safety, gRPC channel security, credential validation, and secrets management
- **[Performance](docs/performance-guidelines.md)** -- Token caching, gRPC client reuse, bulk vs. individual operations, consistency controls, and streaming pagination
- **[Error Handling](docs/error-handling-guidelines.md)** -- Custom exception hierarchy, error wrapping conventions, and gRPC error passthrough policy
- **[Testing](docs/testing-guidelines.md)** -- RSpec configuration, mocking conventions, coverage setup, and CI expectations

For AI-assisted development context, see [AGENTS.md](AGENTS.md).

## Release Instructions

This section provides step-by-step instructions for maintainers to release a new version of the Kessel SDK for Ruby.

### Version Management

This project follows [Semantic Versioning 2.0.0](https://semver.org/). Version numbers use the format `MAJOR.MINOR.PATCH`:

- **MAJOR**: Increment for incompatible API changes
- **MINOR**: Increment for backward-compatible functionality additions
- **PATCH**: Increment for backward-compatible bug fixes

**Note**: SDK versions across different languages (Ruby, Python, Go, etc.) do not need to be synchronized. Each language SDK can evolve independently based on its specific requirements and release schedule.

### Prerequisites for Release

- Write access to the GitHub repository
- RubyGems account with push access to the `kessel-sdk` gem
- Ensure CI/CD tests are passing
- Review and update CHANGELOG or release notes as needed
- Ruby 3.3 or higher
- [buf](https://github.com/bufbuild/buf) for protobuf/gRPC code generation:

### Release Process

1. **Update the Version**
   ```bash
   # Edit lib/kessel/version.rb and update the VERSION constant
   vim lib/kessel/version.rb
   ```

2. **Set the VERSION environment variable**
   ```bash
   export VERSION=$(ruby -e "require_relative './lib/kessel/version.rb'; puts Kessel::Inventory::VERSION")
   echo "Releasing version: v${VERSION}"
   ```

3. **Update Dependencies**
   ```bash
   # Generate gRPC code from Kessel Inventory API
   buf generate
   # Update Gemfile.lock with any dependency changes
   bundle install
   ```

4. **Run Quality Checks**
   ```bash
   # Run the full test suite
   bundle exec rspec
   
   # Run linting
   bundle exec rubocop
   
   # Run security audit
   bundle exec bundler-audit check --update
   
   # Build and test the gem locally
   rake install_local
   ```

5. **Commit Changes**
   ```bash
   git add lib/kessel/version.rb Gemfile.lock
   git commit -m "Release version ${VERSION}"
   git push origin main # or git push upstream main
   ```

6. **Build and Release the Gem**
   ```bash
   # Build the gem
   gem build kessel-sdk.gemspec
   
   # Push to RubyGems (requires RubyGems account and gem ownership)
   gem push kessel-sdk-${VERSION}.gem
   ```

7. **Tag the Release**
   ```bash
   # Create and push a git tag
   git tag -a v${VERSION} -m "Release version ${VERSION}"
   git push origin v${VERSION} # or git push upstream v${VERSION} 
   ```

8. **Create GitHub Release**
   ```bash
   gh release create v${VERSION} --title "v${VERSION}" --generate-notes
   ```

   Or manually:

   - Go to the [GitHub Releases page](https://github.com/project-kessel/kessel-sdk-ruby/releases)
   - Click "Create a new release"
   - Select the tag you just created
   - Add release notes describing the changes
   - Publish the release

9. **Clean Up**
   ```bash
   # Remove the built gem file
   rake clean
   ```

### Using Bundler Gem Tasks

This project includes `bundler/gem_tasks` which provides additional rake tasks:

```bash
# Show available bundler gem tasks
rake -T

# Build gem
rake build

# Install gem locally  
rake install

# Release gem (builds, tags, and pushes to RubyGems)
rake release
```

**Note**: The `rake release` command automates steps 6-7 above but requires proper git and RubyGems credentials to be configured.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please review the [domain-specific guidelines](docs/) before contributing. All specs must pass on Ruby 3.3 and 3.4. Fix RuboCop violations before merging, and update RBS type signatures in `sig/kessel/` when modifying hand-written code.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

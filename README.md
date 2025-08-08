# Kessel SDK for Ruby

[![CI](https://github.com/project-kessel/kessel-sdk-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/project-kessel/kessel-sdk-ruby/actions/workflows/ci.yml)

A Ruby gRPC library for connecting to [Project Kessel](https://github.com/project-kessel) services. This provides the foundational gRPC client library for Kessel Inventory API, with plans for a higher-level SDK with fluent APIs, OAuth support, and advanced features in future releases.

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

## Authentication (Optional)

The SDK supports OAuth 2.0 Client Credentials flow. To use authentication features, add the OpenID Connect gem:

```ruby
gem 'kessel-sdk'
gem 'openid_connect', '~> 2.0'  # Optional - only for authentication
```

## Usage

This library provides direct access to Kessel Inventory API gRPC services. All generated classes are available under the `Kessel::Inventory` module.

### Basic Example - Check Permissions

```ruby
require 'kessel/inventory/v1beta2/inventory_service_services_pb'

include Kessel::Inventory::V1beta2

# Create gRPC client (insecure for development)
client = KesselInventoryService::Stub.new('localhost:9000', :this_channel_is_insecure)

# Create subject reference
subject_reference = SubjectReference.new(
  resource: ResourceReference.new(
    reporter: ReporterReference.new(type: 'rbac'),
    resource_id: 'user123',
    resource_type: 'principal'
  )
)

# Create resource reference
resource = ResourceReference.new(
  reporter: ReporterReference.new(type: 'rbac'),
  resource_id: 'workspace456',
  resource_type: 'workspace'
)

# Check permissions
begin
  response = client.check(
    CheckRequest.new(
      object: resource,
      relation: 'inventory_host_view',
      subject: subject_reference
    )
  )
  puts "Permission check result: #{response.allowed}"
rescue => e
  puts "Error: #{e.message}"
end
```

### Report Resource Example

```ruby
require 'kessel/inventory/v1beta2/inventory_service_services_pb'

include Kessel::Inventory::V1beta2

client = KesselInventoryService::Stub.new('localhost:9000', :this_channel_is_insecure)

# Report a new resource
resource_data = {
  'apiVersion' => 'v1',
  'kind' => 'Namespace', 
  'metadata' => {
    'name' => 'my-namespace',
    'uid' => '12345'
  }
}

request = ReportResourceRequest.new(
  resource: ResourceRepresentations.new(
    kessel_inventory: {
      metadata: RepresentationMetadata.new(
        resource_type: 'k8s-namespace',
        resource_id: resource_data['metadata']['uid'],
        workspace: 'default'
      )
    },
    k8s_manifest: resource_data.to_json
  )
)

begin
  response = client.report_resource(request)
  puts "Resource reported successfully"
rescue => e
  puts "Error reporting resource: #{e.message}"
end
```

### Available Services

The library includes the following gRPC services:

- **KesselInventoryService**: Main inventory service
  - `check(CheckRequest)` - Check permissions
  - `check_for_update(CheckForUpdateRequest)` - Check for resource updates  
  - `report_resource(ReportResourceRequest)` - Report resource state
  - `delete_resource(DeleteResourceRequest)` - Delete a resource
  - `streamed_list_objects(StreamedListObjectsRequest)` - Stream resource listings

### Generated Classes

All protobuf message classes are generated and available. Key classes include:

- `CheckRequest`, `CheckResponse`
- `ReportResourceRequest`, `ReportResourceResponse` 
- `DeleteResourceRequest`, `DeleteResourceResponse`
- `ResourceReference`, `SubjectReference`
- `ResourceRepresentations`, `RepresentationMetadata`

See the `examples/` directory for complete working examples.

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
bundle exec bundle-audit
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

The `examples/` directory contains working examples:

- `check.rb` - Permission checking
- `report_resource.rb` - Reporting resource state
- `delete_resource.rb` - Deleting resources
- `check_for_update.rb` - Checking for updates
- `streamed_list_objects.rb` - Streaming resource lists

Run examples:

```bash
cd examples
ruby check.rb
```

## Roadmap

This is the foundational gRPC library. Future releases will include:

- **High-level SDK**: Fluent client builder API
- **Authentication**: OAuth 2.0 Client Credentials flow
- **Convenience Methods**: Simplified APIs for common operations*
*
## Release Instructions

This section provides step-by-step instructions for maintainers to release a new version of the Kessel SDK for Ruby.

### Version Management

This project follows [Semantic Versioning 2.0.0](https://semver.org/). Version numbers use the format `MAJOR.MINOR.PATCH`:

- **MAJOR**: Increment for incompatible API changes
- **MINOR**: Increment for backward-compatible functionality additions  
- **PATCH**: Increment for backward-compatible bug fixes

**Note**: SDK versions across different languages (Ruby, Python, Go, etc.) do not need to be synchronized. Each language SDK can evolve independently based on its specific requirements and release schedule.

### Release Process

1. **Update the Version**
   ```bash
   # Edit lib/kessel/version.rb
   # Update the VERSION constant to the new version number
   vim lib/kessel/version.rb
   ```

2. **Update Dependencies**
   ```bash
   # Update Gemfile.lock with any dependency changes
   bundle install
   ```

3. **Run Quality Checks**
   ```bash
   # Run the full test suite
   bundle exec rspec
   
   # Run linting
   bundle exec rubocop
   
   # Run security audit
   bundle exec bundle-audit check --update
   
   # Build and test the gem locally
   rake install_local
   ```

4. **Commit Changes**
   ```bash
   git add lib/kessel/version.rb Gemfile.lock
   git commit -m "Release version X.Y.Z"
   git push origin main # or git push upstream main
   ```

5. **Build and Release the Gem**
   ```bash
   # Build the gem
   gem build kessel-sdk.gemspec
   
   # Push to RubyGems (requires RubyGems account and gem ownership)
   gem push kessel-sdk-X.Y.Z.gem
   ```

6. **Tag the Release**
   ```bash
   # Create and push a git tag
   git tag -a vX.Y.Z -m "Release version X.Y.Z"
   git push origin vX.Y.Z
   ```

7. **Clean Up**
   ```bash
   # Remove the built gem file
   rake clean
   ```

### Prerequisites for Release

- Write access to the GitHub repository
- RubyGems account with push access to the `kessel-sdk` gem
- Ensure CI/CD tests are passing
- Review and update CHANGELOG or release notes as needed

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

**Note**: The `rake release` command automates steps 5-6 above but requires proper git and RubyGems credentials to be configured.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

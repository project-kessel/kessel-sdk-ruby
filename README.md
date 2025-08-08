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
## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

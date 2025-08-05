# Kessel SDK for Ruby

A Ruby gRPC library for connecting to [Project Kessel](https://github.com/project-kessel) services. This provides the 
foundational gRPC client library for Kessel API, with plans for a higher-level SDK with fluent APIs, 
OAuth support, and advanced features in future releases.

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

## Usage

This library provides direct access to Kessel API gRPC services. 
All generated classes are available under the `Kessel::Inventory` module.

### Authentication

The SDK supports OpenID Connect (OIDC) Client Credentials flow with automatic discovery. Works seamlessly with 
OIDC-compliant providers. Authentication is **completely optional** - install only if you need it.

#### OIDC Setup (Optional)

**Step 1:** Add OIDC dependency to your Gemfile (only if you need authentication):

```ruby
gem 'kessel-sdk'
gem 'openid_connect', '~> 2.0'  # Optional - only for OIDC authentication
```

**Step 2:** Configure OIDC authentication:

```ruby
require 'kessel-sdk'

include Kessel::Inventory::V1beta2
include Kessel::Auth

discovery = fetch_oidc_discovery('https://my-domain/auth/realms/my-realm')

# Configure OIDC authentication with discovery
auth = Kessel::Inventory::Client::Config::Auth.new(
  client_id: 'your-client-id',
  client_secret: 'your-client-secret',
  # or the token endpoint e.g. 'https://my-domain/auth/realms/my-realm/protocol/openid-connect/token'
  token_endpoint: discovery.token_endpoint
)

# Create authenticated client
client = KesselInventoryService::ClientBuilder.builder
  .with_target('localhost:9000')
  .with_secure_credentials
  .with_auth(auth)
  .build

# The client will automatically handle OIDC discovery, token acquisition and refresh
response = client.check(CheckRequest.new(...))
```

For a complete OIDC example, see [`examples/auth.rb`](examples/auth.rb).

#### Error Handling

OIDC functionality will only fail at runtime if the openid_connect gem is missing or authentication fails:

```ruby
begin
  client = builder.with_auth(auth).build
rescue Kessel::Auth::OAuthDependencyError => e
  puts "OIDC gem not installed: #{e.message}"
  # Add gem 'openid_connect', '~> 2.0' to your Gemfile and run bundle install
rescue Kessel::Auth::OAuthAuthenticationError => e
  puts "OIDC authentication failed: #{e.message}"
  # Check credentials, discovery URL, and server configuration
end
```

**Without OAuth:** You can use the SDK without OAuth by omitting the `.with_auth()` configuration:

```ruby
# No OAuth dependency required for basic usage
client = KesselInventoryService::ClientBuilder.builder
  .with_target('localhost:9000')
  .with_insecure_credentials  # or .with_secure_credentials
  .build
```

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

# Generate gRPC code from Kessel API
buf generate
```

### Code Generation

This library uses [buf](https://buf.build) to generate Ruby gRPC code from the official Kessel API protobuf definitions hosted at `buf.build/project-kessel/inventory-api`.

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
bundle install
rake check
```

## Roadmap

This is the foundational gRPC library. Future releases will include:

- **High-level SDK**: Fluent client builder API
- **Authentication**: OpenID Connect Client Credentials flow with discovery
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

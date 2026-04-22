# Integration Guidelines

## Module Organization and Namespace Conventions

- The SDK's public API is organized under the `Kessel` top-level module with three primary subsystems: `Kessel::Inventory` (gRPC services), `Kessel::Auth` (OIDC authentication), and `Kessel::RBAC::V2` (HTTP-based workspace operations).
- Protobuf message classes and gRPC stubs live under versioned namespaces: `Kessel::Inventory::V1`, `Kessel::Inventory::V1beta1`, and `Kessel::Inventory::V1beta2`. The primary service API is `V1beta2`; `V1` is health-check only; `V1beta1` contains legacy K8s-specific resource/relationship services.
- All modules are loaded via the single entrypoint `require 'kessel-sdk'` (`lib/kessel-sdk.rb`). Prefer loading the complete SDK via this entrypoint rather than requiring individual protobuf files directly in application code, unless you need only a specific subset.

## gRPC Client Construction

- Every gRPC service module (e.g., `KesselInventoryService`) exposes a `ClientBuilder` constant created by `Kessel::Inventory.client_builder_for_stub(Stub)`. The `ClientBuilder` fluent API is recommended over constructing `Stub.new` directly, as it enforces credential validation.
- The `ClientBuilder` supports four mutually exclusive modes via method chaining. Each returns `self` and must end with `.build`:

```ruby
# Insecure (dev only)
KesselInventoryService::ClientBuilder.new(target).insecure.build

# OAuth2 with auto-composed credentials
KesselInventoryService::ClientBuilder.new(target)
  .oauth2_client_authenticated(oauth2_client_credentials: oauth)
  .build

# Custom call/channel credentials
KesselInventoryService::ClientBuilder.new(target)
  .authenticated(call_credentials: creds, channel_credentials: ch_creds)
  .build

# No call credentials, optional channel credentials
KesselInventoryService::ClientBuilder.new(target)
  .unauthenticated(channel_credentials: ch_creds)
  .build
```

- The `target` parameter to `ClientBuilder.new` must be a non-nil `String` (e.g., `"localhost:9000"` or `"kessel.example.com:443"`). A nil or non-string value raises `'Invalid target type'`.
- When no `channel_credentials` are explicitly provided, `build` defaults to `GRPC::Core::ChannelCredentials.new` (TLS). Call credentials are composed onto channel credentials via `.compose`.

## Authentication (OIDC / OAuth2)

- Authentication is optional. The `openid_connect` gem is a soft dependency loaded at runtime via `require 'openid_connect'`. If missing when auth features are used, `Kessel::Auth::OAuthDependencyError` is raised with an actionable message.
- To perform OIDC discovery, include `Kessel::Auth` and call `fetch_oidc_discovery(issuer_url)`, which returns an `OIDCDiscoveryMetadata` struct with a `token_endpoint` field.
- Create an `OAuth2ClientCredentials` instance with keyword arguments `client_id:`, `client_secret:`, and `token_endpoint:`. Calling `get_token` returns a frozen `RefreshTokenResponse` struct with `access_token` and `expires_at` fields.
- Token caching is built in and thread-safe (uses `Mutex`). Tokens are refreshed automatically when expired (with a 5-minute `EXPIRATION_WINDOW` buffer). Pass `force_refresh: true` to `get_token` to bypass the cache.
- For gRPC: convert an `OAuth2ClientCredentials` into gRPC call credentials using `Kessel::GRPC#oauth2_call_credentials(auth)`.
- For HTTP (RBAC): convert credentials into an HTTP auth object using `Kessel::Auth#oauth2_auth_request(oauth)`, which returns an `OAuth2AuthRequest` implementing the `AuthRequest` interface.

## RBAC HTTP Integration

- The `Kessel::RBAC::V2` module provides HTTP-based workspace operations that talk to the RBAC API (not gRPC). Include this module to access `fetch_default_workspace`, `fetch_root_workspace`, and `list_workspaces`.
- `fetch_default_workspace` and `fetch_root_workspace` accept `(rbac_base_endpoint, org_id, auth:, http_client:)`. The endpoint is an HTTP base URL (e.g., `http://localhost:8000`). Trailing slashes are stripped before appending `WORKSPACE_ENDPOINT` (`/api/rbac/v2/workspaces/`).
- The `x-rh-rbac-org-id` header is required on all RBAC HTTP requests and is set automatically from the `org_id` parameter.
- When providing a custom `http_client` (a `Net::HTTP` instance), its host and port must exactly match the `rbac_base_endpoint` URI, or a runtime error is raised.
- The `auth` parameter is optional (`nil` skips authentication). When provided, it must implement the `AuthRequest` interface (i.e., respond to `configure_request`).

## RBAC Helper Methods

`Kessel::RBAC::V2` provides factory methods for constructing protobuf references used across both gRPC and HTTP operations. All RBAC resources use `reporter_type: 'rbac'`:
- `workspace_resource(resource_id)` / `role_resource(resource_id)` -- return `ResourceReference`
- `principal_resource(id, domain)` -- returns `ResourceReference` with `resource_id` formatted as `"#{domain}/#{id}"`
- `principal_subject(id, domain)` -- returns `SubjectReference` wrapping a principal resource
- `subject(resource_ref, relation = nil)` -- generic subject factory
- `workspace_type` / `role_type` -- return `RepresentationType` structs

## Streaming and Pagination

- `list_workspaces(inventory, subject, relation, continuation_token = nil)` returns a lazy `Enumerator` that automatically paginates through `streamed_list_objects` responses with a page limit of 1000 (`DEFAULT_PAGE_LIMIT`). Iteration stops when there are no responses or the `continuation_token` becomes `nil`/falsey.
- For direct streaming calls, `streamed_list_objects` and `streamed_list_subjects` return server-streaming enumerables. Iterate with `.each` to process responses incrementally.

## Environment Configuration

- Examples use `dotenv` to load environment variables from a `.env` file. The required variables are:
  - `KESSEL_ENDPOINT` -- gRPC target (e.g., `localhost:9000` or `your-endpoint.com:443`)
  - `AUTH_CLIENT_ID`, `AUTH_CLIENT_SECRET` -- OIDC client credentials
  - `AUTH_DISCOVERY_ISSUER_URL` -- OIDC issuer URL for discovery
  - `RBAC_BASE_ENDPOINT` -- HTTP base URL for RBAC API (e.g., `http://localhost:8000`)
- For local TLS testing, set the `GRPC_DEFAULT_SSL_ROOTS_FILE_PATH` environment variable to point to your CA root certificate (e.g., from `mkcert`).

## Protobuf Code Generation

- Protobuf and gRPC stubs are generated from `buf.build/project-kessel/inventory-api` using `buf generate`. The `buf.gen.yaml` generates both Ruby message classes and gRPC service stubs into `lib/`. Generated files under `lib/kessel/inventory/*/` and `lib/google/` must never be edited manually.
- When adding a new service version, create a version module file (e.g., `lib/kessel/inventory/v1beta2.rb`) that requires the generated `*_services_pb.rb`, includes `Kessel::Inventory`, and defines a `ClientBuilder` constant via `::Kessel::Inventory.client_builder_for_stub(Stub)` inside the service module.

## Bulk Operations

- Use `CheckBulkRequest` / `CheckForUpdateBulkRequest` with arrays of `CheckBulkRequestItem` for batch permission checks. The response `pairs` maintain request order. Each pair contains either an `item` (with `allowed` result) or an `error` (with `code` and `message`).
- `check_for_update` and `check_for_update_bulk` provide strongly consistent checks intended for use immediately before write operations. Use regular `check` / `check_bulk` for read-path authorization where eventual consistency is acceptable.

## Resource Reporting

- When reporting resources via `ReportResourceRequest`, use `Google::Protobuf::Struct.decode_json(hash.to_json)` to convert Ruby hashes into protobuf `Struct` fields for `common` and `reporter` representation data.
- `RepresentationMetadata` fields include `local_resource_id`, `api_href`, `console_href`, and `reporter_version`. The `type`, `reporter_type`, and `reporter_instance_id` are set on the `ReportResourceRequest` itself, not inside the representations.

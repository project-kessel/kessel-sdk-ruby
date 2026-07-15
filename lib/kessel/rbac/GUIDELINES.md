# RBAC V2 Module Guidelines

## Directory Purpose

This directory contains the hand-written RBAC convenience layer (`Kessel::RBAC::V2`) built on top of V1beta2 protobuf types. It provides workspace operations over both HTTP and gRPC, plus factory helpers for constructing protobuf resource/subject references.

## File Organization

The module is split across three files reopening the same `Kessel::RBAC::V2` module:

- `v2.rb` -- Public API: `fetch_default_workspace`, `fetch_root_workspace`, `list_workspaces`, plus private response processing. Defines the `Workspace` struct and constants.
- `v2_helpers.rb` -- Factory methods for protobuf references: `workspace_type`, `role_type`, `principal_resource`, `role_resource`, `workspace_resource`, `principal_subject`, `subject`.
- `v2_http.rb` -- Private HTTP helpers: `run_request` (sets headers, calls auth), `check_http_client` (validates host/port match).

All three files must be required together -- `lib/kessel-sdk.rb` handles this. Do not require individual files in isolation.

## Module Design

- `V2` is a Ruby module meant to be `include`d, not instantiated. Tests use `include Kessel::RBAC::V2` directly in the RSpec context.
- `V2` includes `Kessel::Inventory::V1beta2` to access protobuf types (`SubjectReference`, `ResourceReference`, `RepresentationType`, etc.) without full qualification.
- The `include V1beta2` appears in both `v2.rb` and `v2_helpers.rb` -- this is intentional for load-order independence.

## Constants and Structs

- `WORKSPACE_ENDPOINT = '/api/rbac/v2/workspaces/'` -- the REST path appended to `rbac_base_endpoint`.
- `DEFAULT_PAGE_LIMIT = 1000` -- page size for `list_workspaces` auto-pagination.
- `Workspace = Struct.new(:id, :name, :type, :description)` -- keyword-argument struct returned by HTTP workspace fetches.

## Factory Helper Conventions

All factory methods in `v2_helpers.rb` follow these rules:

- Every RBAC resource uses `reporter_type: 'rbac'` (hardcoded, not configurable).
- `principal_resource(id, domain)` formats `resource_id` as `"#{domain}/#{id}"` -- the domain comes first.
- `principal_subject(id, domain)` wraps `principal_resource` in a `SubjectReference`.
- `subject(resource_ref, relation = nil)` is a generic factory -- pass `nil` for relation to omit it.
- `workspace_type` and `role_type` return `RepresentationType` structs, not `ResourceReference`.
- Factory methods return frozen protobuf objects (protobuf default). Do not `.dup` or mutate them.

## HTTP Workspace Operations

### Request Pattern

- `fetch_workspace` (private) strips trailing slashes from `rbac_base_endpoint`, appends `WORKSPACE_ENDPOINT`, sets a `type` query parameter, and issues a `GET` request.
- The `x-rh-rbac-org-id` header is required on every request -- set from the `org_id` parameter in `run_request`.
- Authentication is optional: when `auth` is non-nil, `auth.configure_request(request)` is called. The `auth` object must implement the `AuthRequest` interface (i.e., `Kessel::Auth#oauth2_auth_request(oauth)` return value).

### HTTP Client Handling

- When `http_client` is `nil`, a new `Net::HTTP` is created per call (one TCP connection per fetch).
- When `http_client` is provided, `check_http_client` validates that its `address` and `port` match the endpoint URI. Mismatches raise `RuntimeError`.
- For multiple workspace fetches, pass a pre-started `Net::HTTP` to avoid repeated TCP handshakes.

### Response Processing

- `process_response` raises `RuntimeError` for non-success HTTP status codes.
- It expects exactly one workspace in `data[]` -- any other count raises `RuntimeError`.
- `extract_workspace` maps JSON keys to the `Workspace` struct.

## gRPC Workspace Listing

`list_workspaces(inventory, subject, relation, continuation_token = nil, consistency: nil)` returns a lazy `Enumerator`:

- Internally calls `inventory.streamed_list_objects` with a `StreamedListObjectsRequest`.
- Auto-paginates: extracts `continuation_token` from each response's `pagination` field.
- Stops when the server returns no responses or `continuation_token` is nil/falsy.
- The `consistency` parameter is forwarded to every paginated request -- it is not modified between pages.
- Consume with `.each` for constant memory, or `.to_a` to materialize all results (use with caution on large datasets).

## Error Handling

- All errors from this module are bare `RuntimeError` (via `raise "message"`), not custom exception classes.
- gRPC errors from `streamed_list_objects` propagate directly -- do not wrap `GRPC::BadStatus`.

## RBS Type Signatures

- Signatures live in `sig/kessel/rbac.rbs`. Update this file when adding or changing public method signatures.
- The `Workspace` struct, all public methods, and `list_workspaces` return type (`Enumerator`) are declared.
- Run `steep check` after changes to verify type correctness.

## Testing

- Tests are in `spec/kessel/rbac/v2_spec.rb`.
- The spec includes `Kessel::RBAC::V2` in the test context and calls module methods directly.
- HTTP calls are fully mocked -- `Net::HTTP`, `Net::HTTP::Get`, `URI`, and response objects.
- gRPC streaming is mocked by stubbing `inventory.streamed_list_objects` with arrays or dynamic blocks.
- Test pagination by returning different continuation tokens across multiple mock invocations.
- Assert both the exception class and a message regex for error paths.

## RuboCop

This directory is subject to RuboCop rules (unlike generated code). Limits: method length 25, class length 150, cyclomatic complexity 10, line length 120.

## Relationship to Kessel::Console

`lib/kessel/console.rb` depends on `v2_helpers.rb` (via `require_relative 'rbac/v2_helpers'`) and uses `principal_subject` to convert Red Hat identity headers into `SubjectReference` objects. Changes to factory helper signatures affect `Console`.

## Adding New RBAC Operations

1. Determine whether the operation is HTTP-based (REST) or gRPC-based (protobuf service call).
2. Add public methods to `v2.rb`. Add factory helpers to `v2_helpers.rb`. Add HTTP plumbing to `v2_http.rb`.
3. Update `sig/kessel/rbac.rbs` with the new method signature.
4. Add tests in `spec/kessel/rbac/v2_spec.rb` following the existing mock patterns.
5. Run `bundle exec rspec` and `steep check`.

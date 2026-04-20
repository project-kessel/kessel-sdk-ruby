# Performance Guidelines

## Token Caching and Thread-Safe Authentication

### Reuse a single `OAuth2ClientCredentials` instance across threads

`OAuth2ClientCredentials` caches the access token in `@cached_token` and protects refresh with `@token_mutex`. Creating multiple instances defeats caching and causes redundant token requests.

### Token refresh uses double-checked locking -- do not bypass it

`get_token` checks `token_valid?` outside the mutex for the fast path, then re-checks inside `@token_mutex.synchronize` to prevent thundering herd. When adding new auth flows, follow this exact pattern:

```ruby
return @cached_token if !force_refresh && token_valid?
@token_mutex.synchronize do
  return @cached_token if token_valid?
  @cached_token = refresh
end
```

### Frozen token response objects prevent accidental mutation

`refresh` calls `.freeze` on the `RefreshTokenResponse` before storing it. Any new cacheable response types must also be frozen to remain safe for concurrent reads outside the mutex.

### Respect the `EXPIRATION_WINDOW` (300 seconds) for proactive renewal

`token_valid?` considers a token expired 5 minutes before its actual `expires_at`. Do not reduce this window -- it prevents using tokens that expire mid-request. The `DEFAULT_EXPIRES_IN` (3600s) is a fallback when the OIDC provider omits `expires_in`.

### Use `force_refresh: true` sparingly

`get_token(force_refresh: true)` clears the cache inside the mutex and forces a network call. Only use it after receiving an explicit 401/UNAUTHENTICATED error, never preemptively.

## gRPC Client Lifecycle

### Build gRPC clients once and reuse them

`ClientBuilder.build` creates a new `Stub` instance each time. The underlying gRPC channel manages its own HTTP/2 connection pool, so one stub per target is sufficient. Do not call `.build` per request.

```ruby
# Good: build once at startup
@client = KesselInventoryService::ClientBuilder.new(endpoint)
                                               .oauth2_client_authenticated(oauth2_client_credentials: oauth)
                                               .build

# Bad: building per request wastes connections
def check(request)
  client = KesselInventoryService::ClientBuilder.new(endpoint).insecure.build
  client.check(request)
end
```

### The `oauth2_call_credentials` proc runs on every gRPC call

In `Kessel::GRPC#oauth2_call_credentials`, the proc passed to `CallCredentials.new` is invoked by gRPC for each RPC. This proc calls `auth.get_token`, which hits the fast-path cache when the token is valid. Do not add blocking operations (logging, metrics, I/O) inside this proc.

### Channel credentials are composed once at build time

`build` calls `credentials.compose(@call_credentials)` to produce a single composite credential. This composition is not repeated per-call. If you need to rotate channel-level credentials, you must rebuild the client.

## Bulk Operations vs. Individual Calls

### Use `check_bulk` / `check_for_update_bulk` instead of looping over `check` / `check_for_update`

Bulk endpoints accept up to 1000 items in a single RPC. Each individual `check` call incurs a full gRPC round-trip. Bulk calls amortize connection overhead and enable server-side parallelism.

```ruby
# Good
response = client.check_bulk(CheckBulkRequest.new(items: [item1, item2, item3]))

# Bad: 3 round-trips
[item1, item2, item3].each { |item| client.check(CheckRequest.new(...)) }
```

### `check_for_update` variants are strongly consistent -- use only when needed

These endpoints bypass caches on the server for full consistency. Use `check` / `check_bulk` for read-heavy UI rendering and permission filtering; reserve `check_for_update` variants for pre-mutation authorization gates.

## Consistency Controls

### Choose the right `Consistency` setting per use case

The `Consistency` message supports three modes:
- `minimize_latency: true` -- fastest, may return stale data (default for reads)
- `at_least_as_fresh: ConsistencyToken` -- ensures freshness relative to a prior write
- `at_least_as_acknowledged: true` -- waits for all acknowledged writes

For dashboard/list UIs, use `minimize_latency`. For post-write verification, pass the consistency token from the write response via `at_least_as_fresh`.

### Set `write_visibility` on `ReportResourceRequest` appropriately

The `WriteVisibility` enum defaults to `WRITE_VISIBILITY_UNSPECIFIED` (0) when not explicitly set. The protobuf schema defines three values:
- `WRITE_VISIBILITY_UNSPECIFIED` (0) -- default behavior, defers to server configuration
- `MINIMIZE_LATENCY` (1) -- allows the server to batch and optimize writes
- `IMMEDIATE` (2) -- forces synchronous visibility

Explicitly set `write_visibility: :IMMEDIATE` only when the caller will immediately perform a `Check` on the newly reported resource, as it adds latency to the write path.

## Streaming and Pagination

### Use `streamed_list_objects` / `streamed_list_subjects` for large result sets

These are server-streaming RPCs. The SDK yields responses incrementally via `each`, avoiding buffering the entire result set in memory.

```ruby
client.streamed_list_objects(request).each do |response|
  process(response)
end
```

### Use the `list_workspaces` Enumerator for automatic pagination

`RBAC::V2#list_workspaces` returns a lazy `Enumerator` that handles continuation tokens automatically with a page size of `DEFAULT_PAGE_LIMIT` (1000). Consume with `.each` or `.take(n)` for bounded iteration. Avoid calling `.to_a` on unbounded datasets -- it forces all pages into memory.

### Forward `continuation_token` from the last response when resuming pagination manually

When paginating `StreamedListObjectsRequest` directly (without `list_workspaces`), extract `response.pagination.continuation_token` from the final response in each streamed batch and pass it in the next request's `RequestPagination`. Stop when the token is `nil` or the batch is empty.

## HTTP Client Reuse (RBAC V2 REST Calls)

### Pass a pre-started `Net::HTTP` client to `fetch_default_workspace` / `fetch_root_workspace`

Without an `http_client` argument, each call creates a new `Net::HTTP` instance and opens a new TCP connection. For multiple workspace fetches, create one client, call `.start`, and pass it to all calls:

```ruby
http_client = Net::HTTP.new(uri.host, uri.port)
http_client.start
fetch_default_workspace(endpoint, org_id, auth: auth, http_client: http_client)
fetch_root_workspace(endpoint, org_id, auth: auth, http_client: http_client)
http_client.finish
```

### The SDK validates `http_client` host/port matches the endpoint

`check_http_client` raises if the `http_client.address` or `http_client.port` differs from the URI. Do not reuse an HTTP client across different base endpoints.

## Protobuf and Code Generation

### Never modify generated `_pb.rb` or `_services_pb.rb` files

All files under `lib/kessel/inventory/v1*/` are generated by `buf generate` and will be overwritten. Performance optimizations to protobuf serialization or service definitions must go upstream into the `.proto` files.

### RuboCop excludes generated files -- keep hand-written code under the same lint rules

`.rubocop.yml` excludes `lib/kessel/inventory/v*/**/*`. All hand-written SDK code (under `lib/kessel/auth.rb`, `lib/kessel/grpc.rb`, `lib/kessel/rbac/`, `lib/kessel/inventory.rb`) is subject to method length (25), class length (150), and cyclomatic complexity (10) limits.

## Builder Pattern and Object Allocation

### `client_builder_for_stub` creates a new Class object per call -- cache the result

`Kessel::Inventory.client_builder_for_stub(stub_class)` allocates a new `Class` via `Class.new(ClientBuilder)` each time. The SDK caches these as constants (e.g., `KesselInventoryService::ClientBuilder`). When creating custom builders, assign the result to a constant rather than calling `client_builder_for_stub` repeatedly.

@AGENTS.md

# Claude Code-Specific Instructions

## Development Commands

When working in this repository, use these commands:

### Testing
- `bundle exec rspec` -- Run all specs (default test command)
- `rake spec` -- Run tests via Rake
- `rake test_coverage` -- Run tests with SimpleCov coverage enabled
- `rake` -- Run both specs and RuboCop (default task)

### Linting & Code Quality
- `bundle exec rubocop --parallel` -- Run RuboCop linter
- `bundle exec rubocop --autocorrect` or `rake rubocop:autocorrect` -- Auto-fix RuboCop violations
- `bundle exec bundle-audit check --update` -- Check for security vulnerabilities

### Type Checking
- `steep check` -- Run Steep type checker against hand-written code in `lib/` using RBS signatures in `sig/`
- `rbs collection install` -- Install RBS type definitions for dependencies (creates `.gem_rbs_collection/`)

### Documentation
- `rake docs` -- Generate YARD API documentation to `doc/api/`
- `rake docs_serve` -- Serve documentation locally at http://localhost:8808

### Build & Installation
- `gem build kessel-sdk.gemspec` -- Build the gem
- `rake install_local` -- Build and install gem locally for testing
- `rake clean` -- Remove built gem files
- `rake clean_all` -- Clean both gems and generated documentation

### Protobuf Code Generation
- `buf generate` -- Regenerate protobuf/gRPC code from `buf.build/project-kessel/inventory-api`
  - **WARNING**: This overwrites all files under `lib/kessel/inventory/v*/`, `lib/google/`, and `lib/buf/`
  - CI runs this automatically every 6 hours via `.github/workflows/buf-generate.yml`
  - Only run manually when preparing for a release or testing upstream API changes

### Examples
Examples in `examples/` require environment variables. They use `dotenv` to load `.env` files:
- `cd examples && bundle install` -- Install example dependencies
- `cd examples && ruby check.rb` -- Run an example (requires `.env` with `KESSEL_ENDPOINT`, etc.)

## Claude Code Behavioral Preferences

### When Making Code Changes
1. **Run tests before committing**: Use `bundle exec rspec` to verify changes
2. **Fix RuboCop violations**: Run `bundle exec rubocop --autocorrect` after code changes (violations don't block CI but should be addressed)
3. **Update RBS signatures**: When modifying hand-written code in `lib/kessel/`, update corresponding `.rbs` files in `sig/kessel/` and run `steep check`
4. **Never edit generated files**: Files under `lib/kessel/inventory/v*/`, `lib/google/`, `lib/buf/` are auto-generated and will be overwritten

### When Creating Tests
- Follow patterns in existing specs under `spec/`
- Use mocks for all external dependencies (gRPC stubs, HTTP calls, OIDC discovery)
- Verify code coverage with `rake test_coverage` (SimpleCov reports to `coverage/`)

### When Adding Dependencies
- Runtime dependencies must be justified (current policy: only `grpc` is required)
- `openid_connect` must remain optional (lazy-loaded)
- Development dependencies go in `kessel-sdk.gemspec` under `add_development_dependency`

### Before Releasing
1. Update `lib/kessel/version.rb` with new `Kessel::Inventory::VERSION`
2. Run `buf generate` to pick up latest upstream protobuf changes
3. Run full test suite on Ruby 3.3 and 3.4
4. Create release branch: `release/${VERSION}`
5. Build and verify gem: `gem build kessel-sdk.gemspec`

### Security Notes
- Never commit `.env` files or credentials (already in `.gitignore`)
- RBS collection directory `.gem_rbs_collection/` is git-ignored and recreated via `rbs collection install`
- Built gems (`*.gem`) should not be committed (clean with `rake clean`)

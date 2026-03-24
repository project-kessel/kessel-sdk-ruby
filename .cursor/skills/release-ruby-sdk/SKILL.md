---
name: release-ruby-sdk
description: Release a new version of the Kessel Ruby SDK (kessel-sdk gem). Guides through version bump, code generation, quality checks, RubyGems publish, git tagging, and GitHub release creation. Use when the user wants to release, publish, bump version, or cut a new release of the Ruby SDK.
---

# Release Kessel Ruby SDK

## Prerequisites

- Write access to the GitHub repository
- RubyGems account with push access to the `kessel-sdk` gem
- Ruby 3.3+, `buf`, and `bundler` installed
- RubyGems auth configured via `~/.gem/credentials` or `GEM_HOST_API_KEY` env var. Note: Cursor's shell may not inherit exported tokens -- if auth is not available, the `gem push` step must be run manually in your own terminal.

```bash
bundle install
```

## Release Process

### Step 0: Preflight -- Clean Working Tree

Run `git status --porcelain` to check for uncommitted changes. If the working tree is dirty, present the list of changed files and ask the user whether to:
1. Abort the release (recommended if unsure)
2. Stash changes for later: `git stash --include-untracked`

### Step 1: Update the Version and Create Release Branch

Check existing tags to find the current version:

```bash
git fetch --tags
git tag --sort=-v:refname | head -5
```

Or via GitHub:

```bash
gh release list --limit 5
```

Choose the new version following [Semantic Versioning](https://semver.org/) and edit `lib/kessel/version.rb` to update the `VERSION` constant:
- **MAJOR**: incompatible API changes
- **MINOR**: backward-compatible new functionality
- **PATCH**: backward-compatible bug fixes

Then set the `VERSION` env var from the source file and create a release branch:

```bash
export VERSION=$(ruby -e "require_relative './lib/kessel/version.rb'; puts Kessel::Inventory::VERSION")
echo "Releasing version: ${VERSION}"
git checkout -b release/${VERSION}
```

### Step 2: Update Dependencies (if needed)

```bash
buf generate
bundle install
```

### Step 3: Run Quality Checks

```bash
bundle exec rspec
bundle exec rubocop
bundle exec bundler-audit check --update
rake install_local
```

### Step 4: Documentation Audit (optional)

Check if the README is up to date with the current codebase:

1. **Examples:** Compare the files in `examples/*.rb` against the "Examples" section in the README. Flag any examples that exist on disk but are not listed in the README.
2. **Available Services:** If a local Kessel instance is running, list endpoints with `grpcurl -plaintext localhost:9081 list kessel.inventory.v1beta2.KesselInventoryService` and compare against the "Available Services" section in the README. Flag any undocumented endpoints.

Present any gaps to the user and ask if they'd like to update the README before releasing. Skip the grpcurl check if no local instance is available.

### Step 5: Review Changes

Before committing, summarize the release for the user and ask for confirmation.

1. Run `git diff --stat` and `git status` to gather all pending changes.
2. Compare `$VERSION` against the latest git tag (`git describe --tags --abbrev=0`) to determine the bump type (major/minor/patch).
3. Present a summary to the user including:
   - The version being released and the bump type
   - List of files that will be committed
   - Quality check results
4. **Wait for user confirmation before proceeding.**

### Step 6: Commit, Push Branch, and Create PR

```bash
git add lib/kessel/version.rb Gemfile.lock
git commit -m "chore: bump version to ${VERSION}"
git push -u origin release/${VERSION}
gh pr create --title "Release v${VERSION}" --body "Release version ${VERSION}"
```

Include any other changed files (generated code, lock files) in the commit.

**The remaining steps (publish, tag, GitHub release) should be performed after the PR is merged to main.**

### Step 7: Build and Publish to RubyGems

After the PR is merged, switch back to main and pull:

```bash
git checkout main && git pull origin main
gem build kessel-sdk.gemspec
```

Before publishing, show the built artifact (`ls -lh kessel-sdk-${VERSION}.gem`) and **ask the user to confirm** before running `gem push`, since RubyGems publishes are effectively irreversible.

Check if RubyGems auth is available (look for `~/.gem/credentials` or `GEM_HOST_API_KEY` env var). If auth is not configured, instruct the user to run the push manually in their own terminal:

```bash
gem push kessel-sdk-${VERSION}.gem
```

### Step 8: Tag the Release

```bash
git tag -a v${VERSION} -m "Release version ${VERSION}"
git push origin v${VERSION}
```

### Step 9: Create GitHub Release

```bash
gh release create v${VERSION} --title "v${VERSION}" --generate-notes
```

Or manually:
- Go to the [GitHub Releases page](https://github.com/project-kessel/kessel-sdk-ruby/releases)
- Click "Create a new release"
- Select the tag you just created
- Add release notes describing the changes
- Publish the release

## Quick Reference Checklist

```
Release v${VERSION}:
- [ ] Preflight: clean working tree
- [ ] Check existing tags and determine new version
- [ ] Update version in lib/kessel/version.rb and derive VERSION from it
- [ ] Create release/${VERSION} branch
- [ ] Regenerate gRPC code if needed (buf generate)
- [ ] Run bundle exec rspec, rubocop, bundler-audit
- [ ] Build and test locally (rake install_local)
- [ ] Documentation audit (optional, check examples + services in README)
- [ ] Review changes and get user confirmation
- [ ] Commit, push branch, create PR
- [ ] Merge PR to main
- [ ] Clean build, confirm with user, publish to RubyGems
- [ ] Create and push git tag (v${VERSION})
- [ ] Create GitHub release
```

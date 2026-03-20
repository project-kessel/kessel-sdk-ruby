---
name: release-ruby-sdk
description: Release a new version of the Kessel Ruby SDK (kessel-sdk gem). Guides through version bump, code generation, quality checks, RubyGems publish, git tagging, and GitHub release creation. Use when the user wants to release, publish, bump version, or cut a new release of the Ruby SDK.
---

# Release Kessel Ruby SDK

## Prerequisites

- Write access to the GitHub repository
- RubyGems account with push access to the `kessel-sdk` gem
- Ruby 3.3+
- [buf](https://github.com/bufbuild/buf) for protobuf/gRPC code generation

## Release Process

### Step 1: Determine the Version

Check existing tags to find the current version:

```bash
git fetch --tags
git tag --sort=-v:refname | head -5
```

Or via GitHub:

```bash
gh release list --limit 5
```

Choose the new version following [Semantic Versioning](https://semver.org/):
- **MAJOR**: incompatible API changes
- **MINOR**: backward-compatible new functionality
- **PATCH**: backward-compatible bug fixes

### Step 2: Update the Version

Edit `lib/kessel/version.rb` and update the `VERSION` constant to the new version number.

Then set the `VERSION` env var for use in subsequent steps:

```bash
export VERSION=$(ruby -e "require_relative './lib/kessel/version.rb'; puts Kessel::Inventory::VERSION")
echo "Releasing version: v${VERSION}"
```

### Step 3: Update Dependencies (if needed)

```bash
buf generate
bundle install
```

### Step 4: Run Quality Checks

```bash
bundle exec rspec
bundle exec rubocop
bundle exec bundler-audit check --update
rake install_local
```

### Step 5: Commit and Push

```bash
git add lib/kessel/version.rb Gemfile.lock
git commit -m "Release version ${VERSION}"
git push origin main
```

Include any other changed files (generated code, etc.) in the commit.

### Step 6: Build and Publish to RubyGems

```bash
gem build kessel-sdk.gemspec
gem push kessel-sdk-${VERSION}.gem
```

### Step 7: Tag the Release

```bash
git tag -a v${VERSION} -m "Release version ${VERSION}"
git push origin v${VERSION}
```

### Step 8: Create GitHub Release

```bash
gh release create v${VERSION} --title "v${VERSION}" --generate-notes
```

Or manually:

- Go to the [GitHub Releases page](https://github.com/project-kessel/kessel-sdk-ruby/releases)
- Click "Create a new release"
- Select the tag you just created
- Add release notes describing the changes
- Publish the release

### Step 9: Clean Up

```bash
rake clean
```

## Quick Reference Checklist

```
Release v${VERSION}:
- [ ] Check existing tags and determine new version
- [ ] Update lib/kessel/version.rb
- [ ] Set VERSION env var
- [ ] Regenerate gRPC code if needed (buf generate)
- [ ] Run bundle exec rspec, rubocop, bundler-audit
- [ ] Build and test locally (rake install_local)
- [ ] Commit and push version bump
- [ ] Build and publish gem (gem push)
- [ ] Create and push git tag (v${VERSION})
- [ ] Create GitHub release
- [ ] Clean up (rake clean)
```

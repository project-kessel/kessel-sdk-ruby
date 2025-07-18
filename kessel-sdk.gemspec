# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'kessel/version'

Gem::Specification.new do |spec|
  spec.name        = 'kessel-sdk'
  spec.version     = Kessel::Inventory::VERSION
  spec.authors     = ['Project Kessel']
  spec.summary     = 'Ruby SDK for Project Kessel'
  spec.description = 'This is the official Ruby SDK for [Project Kessel](https://github.com/project-kessel), a ' \
                     'system for unifying APIs and experiences with fine-grained authorization, common inventory, ' \
                     'and CloudEvents.'
  spec.homepage    = 'https://github.com/project-kessel/kessel-sdk-ruby'
  spec.license     = 'Apache-2.0'

  spec.required_ruby_version = '>= 3.3'

  spec.files = Dir.glob('{lib}/**/*') + Dir.glob('{sig}/**/*') + ['README.md', 'LICENSE']
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'grpc', '~> 1.73.0'

  # Development dependencies - Testing
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rspec-expectations', '~> 3.12'
  spec.add_development_dependency 'rspec-mocks', '~> 3.12'
  spec.add_development_dependency 'simplecov', '~> 0.22'

  # Development dependencies - Code quality
  spec.add_development_dependency 'rubocop', '~> 1.57'

  # Development dependencies - Type checking
  spec.add_development_dependency 'steep', '~> 1.10.0'
  spec.add_development_dependency 'typeprof', '~> 0.30.1'

  if spec.respond_to? :metadata
    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['bug_tracker_uri'] = 'https://github.com/project-kessel/kessel-sdk-ruby/issues'
    spec.metadata['rubygems_mfa_required'] = 'true'
  end
end

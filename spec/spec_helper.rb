# frozen_string_literal: true

require 'rspec'

# Load the main library
require_relative '../lib/kessel-sdk'

# Configure RSpec
RSpec.configure do |config|
  # Use the recommended rspec defaults
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  # Configure shared context metadata behavior
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Filter lines from Rails gems in backtraces
  config.filter_gems_from_backtrace 'grpc'

  # Allow more verbose output when running a single spec file
  config.default_formatter = 'doc' if config.files_to_run.one?

  # Print the slowest examples and example groups
  config.profile_examples = 10

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Configure coverage if requested
  if ENV['COVERAGE']
    begin
      require 'simplecov'
      SimpleCov.start do
        add_filter '/spec/'
        add_filter '/examples/'

        add_group 'Core', 'lib/kessel'
        add_group 'Generated', 'lib/kessel/inventory'
        add_group 'Google', 'lib/google'
        add_group 'Buf', 'lib/buf'
      end
    rescue LoadError
      puts 'SimpleCov not available. Install it for coverage reports.'
    end
  end
end

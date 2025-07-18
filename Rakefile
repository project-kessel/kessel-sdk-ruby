# frozen_string_literal: true

require 'bundler/gem_tasks'

# Load RSpec and RuboCop tasks if available
begin
  require 'rspec/core/rake_task'
  require 'rubocop/rake_task'

  # RSpec test task
  RSpec::Core::RakeTask.new(:spec) do |task|
    task.rspec_opts = ['--color', '--format', 'documentation']
  end

  # RuboCop linting task
  RuboCop::RakeTask.new(:rubocop) do |task|
    task.options = ['--display-cop-names']
  end

  # RuboCop auto-correct task
  RuboCop::RakeTask.new('rubocop:autocorrect') do |task|
    task.options = ['--autocorrect']
  end
rescue LoadError
  puts "RSpec or RuboCop not available. Run 'bundle install' to install development dependencies."
end

# Default task - run tests and linting
desc 'Run tests and linting'
task default: %i[spec rubocop]

# Run tests with coverage
desc 'Run tests with coverage'
task :test_coverage do
  ENV['COVERAGE'] = 'true'
  Rake::Task[:spec].invoke
end

# Development setup
desc 'Setup development environment'
task :setup do
  puts 'Setting up development environment...'
  system('bundle install') or raise 'Bundle install failed'
  puts 'Installing development dependencies...'
  puts 'Development environment setup completed!'
  puts ''
  puts 'Available tasks:'
  puts '  rake spec           - Run tests'
  puts '  rake rubocop        - Run linting'
  puts '  rake test_coverage  - Run tests with coverage'
  puts '  rake install_local  - Build and install gem locally'
end

# Build and install gem locally
desc 'Build and install gem locally'
task :install_local do
  puts 'Building and installing gem locally...'
  system('gem build kessel-sdk.gemspec') or raise 'Gem build failed'

  gem_file = Dir.glob('kessel-sdk-*.gem').first
  system("gem install #{gem_file}") or raise 'Gem install failed'

  puts 'Gem installed locally!'
end

# Clean built gems
desc 'Clean built gems'
task :clean do
  FileUtils.rm_rf(Dir.glob('kessel-sdk-*.gem'))
  puts 'Cleaned built gems!'
end

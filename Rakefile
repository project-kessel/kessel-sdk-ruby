# frozen_string_literal: true

# Build and install gem locally
desc 'Build and install gem locally'
task :install_local do
  puts 'Building and installing gem locally...'
  system('gem build kessel-sdk.gemspec') or raise 'Gem build failed'

  gem_file = Dir.glob('kessel-sdk-*.gem').first
  system("gem install #{gem_file}") or raise 'Gem install failed'

  puts 'Gem installed locally!'
end

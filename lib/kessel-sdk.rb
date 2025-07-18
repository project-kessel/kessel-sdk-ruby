# frozen_string_literal: true

# Require core modules first
require_relative 'kessel/inventory'
require_relative 'kessel/grpc'

# Load all generated service classes
Dir.glob(File.join(__dir__, '**', '*_services_pb.rb')).each do |file|
  require file.sub(__dir__ + File::SEPARATOR, '')
end

# Load version-specific modules
Dir.glob(File.join(__dir__, 'kessel', 'inventory', 'v*.rb')).each do |file|
  require file.sub(__dir__ + File::SEPARATOR, '')
end

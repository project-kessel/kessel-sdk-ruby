# frozen_string_literal: true

require 'kessel/version'
require 'kessel/grpc'
require 'kessel/auth'

Dir.glob(File.join(__dir__, '**', '*_services_pb.rb')).each do |file|
  require file.sub(__dir__ + File::SEPARATOR, '')
end

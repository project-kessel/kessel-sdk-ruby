# frozen_string_literal: true

Dir.glob(File.join(__dir__, '**', '*_services_pb.rb')).each do |file|
  require file.sub(__dir__ + File::SEPARATOR, '')
end

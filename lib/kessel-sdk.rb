Dir.glob(File.join(__dir__, '**', '*_services_pb.rb')).sort.each do |file|
  require file.sub(__dir__ + File::SEPARATOR, '')
end

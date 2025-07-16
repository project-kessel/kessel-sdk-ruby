#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'kessel-sdk'

include Kessel::Inventory::V1beta2

client = KesselInventoryService::Stub.new('localhost:9000', :this_channel_is_insecure)

representation_type = RepresentationType.new(
  resource_type: 'workspace',
  reporter_type: 'rbac'
)

subject_reference = SubjectReference.new(
  resource: ResourceReference.new(
    reporter: ReporterReference.new(
      type: 'rbac'
    ),
    resource_id: 'foobar',
    resource_type: 'principal'
  )
)

begin
  streamed_response = client.streamed_list_objects(
    StreamedListObjectsRequest.new(
      object_type: representation_type,
      relation: 'inventory_host_view',
      subject: subject_reference
    )
  )
  p 'streamed_list_objects response received successfully:'
  streamed_response.each do |response|
    p response
  end
rescue Exception => e
  p 'gRPC error occurred during streamed_list_objects:'
  p "Exception #{e}"
end

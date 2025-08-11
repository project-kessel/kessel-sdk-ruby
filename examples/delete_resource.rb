#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'kessel-sdk'

include Kessel::Inventory::V1beta2

# Using the client builder
client = KesselInventoryService::ClientBuilder.new(ENV.fetch('KESSEL_ENDPOINT', nil))
                                              .insecure
                                              .build

# Or without the client builder
# client = KesselInventoryService::Stub.new(ENV.fetch('KESSEL_ENDPOINT', nil), :this_channel_is_insecure)

begin
  response = client.delete_resource(
    DeleteResourceRequest.new(
      reference: ResourceReference.new(
        resource_type: 'host',
        resource_id: '854589f0-3be7-4cad-8bcd-45e18f33cb81',
        reporter: ReporterReference.new(
          type: 'HBI'
        )
      )
    )
  )
  p 'delete_resource response received successfully:'
  p response
rescue Exception => e
  p 'gRPC error occurred during delete_resource:'
  p "Exception #{e}"
end

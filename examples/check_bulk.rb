#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'kessel-sdk'

class CheckBulkExample

  class << self
    include Kessel::Inventory::V1beta2
    include Kessel::RBAC::V2

    def run
      # Using the client builder
      client = KesselInventoryService::ClientBuilder.new(ENV.fetch('KESSEL_ENDPOINT', nil))
                                                    .insecure
                                                    .build

      # Or without the client builder
      # client = KesselInventoryService::Stub.new(ENV.fetch('KESSEL_ENDPOINT', nil), :this_channel_is_insecure)

      begin
        # Item 1: Check if bob can view widgets in workspace_123
        item1 = CheckBulkRequestItem.new(
          object: workspace_resource('workspace_123'),
          relation: 'view_widget',
          subject: principal_subject('bob', 'redhat')
        )

        # Item 2: Check if bob can use widgets in workspace_456
        item2 = CheckBulkRequestItem.new(
          object: workspace_resource('workspace_456'),
          relation: 'use_widget',
          subject: principal_subject('bob', 'redhat')
        )

        # Item 3: Check with invalid resource type to demonstrate error handling
        item3 = CheckBulkRequestItem.new(
          object: ResourceReference.new(
            reporter: ReporterReference.new(
              type: 'rbac'
            ),
            resource_id: 'invalid_resource',
            resource_type: 'not_a_valid_type'
          ),
          relation: 'view_widget',
          subject: principal_subject('alice', 'redhat')
        )


        response = client.check_bulk(
          CheckBulkRequest.new(items: [item1, item2, item3])
        )

        p 'CheckBulk response received successfully'
        p "Total pairs in response: #{response.pairs.length}"

        response.pairs.each_with_index do |pair, index|
          p "-- Result #{index + 1} --"

          req = pair.request
          p "Request: subject=#{req.subject.resource.resource_id}"
          p "relation=#{req.relation}"
          p "object=#{req.object.resource_id}"

          if pair.item
            p pair.item.allowed
          elsif pair.error
            p "Error: Code=#{pair.error.code}, Message=#{pair.error.message}"
          end

        end

      rescue Exception => e
        p 'gRPC error occurred during check:'
        p "Exception #{e}"
        raise e
      end
    end
  end
end

CheckBulkExample.run

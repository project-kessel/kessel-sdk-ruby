#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'kessel-sdk'

class CheckForUpdateBulkExample

  class << self
    include Kessel::Inventory::V1beta2
    include Kessel::RBAC::V2

    def run
      client = KesselInventoryService::ClientBuilder.new(ENV.fetch('KESSEL_ENDPOINT', nil))
                                                    .insecure
                                                    .build

      begin
        item1 = CheckBulkRequestItem.new(
          object: workspace_resource('workspace_123'),
          relation: 'edit_widget',
          subject: principal_subject('bob', 'redhat')
        )

        item2 = CheckBulkRequestItem.new(
          object: workspace_resource('workspace_456'),
          relation: 'delete_widget',
          subject: principal_subject('bob', 'redhat')
        )

        response = client.check_for_update_bulk(
          CheckForUpdateBulkRequest.new(items: [item1, item2])
        )

        p 'CheckForUpdateBulk response received successfully'
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
        p 'gRPC error occurred during check_for_update_bulk:'
        p "Exception #{e}"
        raise e
      end
    end
  end
end

CheckForUpdateBulkExample.run

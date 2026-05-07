#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'kessel-sdk'

include Kessel::RBAC::V2
include Kessel::Inventory::V1beta2

begin
  client = KesselInventoryService::ClientBuilder.new(ENV.fetch('KESSEL_ENDPOINT', nil))
                                                .insecure
                                                .build

  # Iterate one-by-one (lazy, constant memory)
  p "Listing workspaces"
  list_workspaces(client, principal_subject("alice", "redhat"), "view_document").each do |response|
    p response
  end

  # Materialise all workspaces into an Array
  all_workspaces = list_workspaces(client, principal_subject("alice", "redhat"), "view_document").to_a
  p "Total workspaces: #{all_workspaces.length}"
rescue Exception => e
  p 'Error occurred while listing workspaces'
  p "Exception: #{e}"
end

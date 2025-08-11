# frozen_string_literal: true

require 'kessel/inventory'
require 'kessel/inventory/v1beta2/inventory_service_services_pb'

include Kessel::Inventory

module Kessel
  module Inventory
    module V1beta2
      module KesselInventoryService
        ClientBuilder = ::Kessel::Inventory.service_builder(Stub)
      end
    end
  end
end

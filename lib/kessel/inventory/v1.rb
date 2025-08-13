# frozen_string_literal: true

require 'kessel/inventory'
require 'kessel/inventory/v1/health_services_pb'

include Kessel::Inventory

module Kessel
  module Inventory
    module V1
      module KesselInventoryHealthService
        ClientBuilder = ::Kessel::Inventory.client_builder_for_stub(Stub)
      end
    end
  end
end

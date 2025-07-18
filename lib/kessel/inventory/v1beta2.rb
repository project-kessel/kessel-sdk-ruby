require 'kessel/grpc'
require 'kessel/inventory/v1beta2/inventory_service_services_pb'

module Kessel
  module Inventory
    module V1beta2
      module KesselInventoryService
        ClientBuilder = GRPC::ClientBuilder.create(Stub)
      end
    end
  end
end

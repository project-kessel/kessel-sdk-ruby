require 'kessel/grpc'
require 'kessel/inventory/v1/health_services_pb'

module Kessel
  module Inventory
    module V1
      module KesselInventoryHealthService
        ClientBuilder = ::Kessel::GRPC::ClientBuilder.create(Stub)
      end
    end
  end
end

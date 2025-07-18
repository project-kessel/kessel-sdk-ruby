require 'kessel/grpc'
require 'kessel/inventory/v1beta1/relationships/k8spolicy_ispropagatedto_k8scluster_service_services_pb'
require 'kessel/inventory/v1beta1/resources/k8s_clusters_service_services_pb'
require 'kessel/inventory/v1beta1/resources/k8s_policies_service_services_pb'

module Kessel
  module Inventory
    module V1beta1
      module Relationships
        module KesselK8SPolicyIsPropagatedToK8SClusterService
          ClientBuilder = GRPC::ClientBuilder.create(Stub)
        end
      end

      module Resources
        module KesselK8sClusterService
          ClientBuilder = GRPC::ClientBuilder.create(Stub)
        end

        module KesselK8sPolicyService
          ClientBuilder = GRPC::ClientBuilder.create(Stub)
        end
      end
    end
  end
end

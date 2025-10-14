# frozen_string_literal: true

module Kessel
  module RBAC
    module V2
      private

      def run_request(uri, org_id, auth, http_client)
        request = Net::HTTP::Get.new uri
        request['x-rh-rbac-org-id'] = org_id

        auth&.configure_request(request)

        http_client.request(request)
      end

      def check_http_client(http_client, uri)
        return if uri.host == http_client.address && uri.port == http_client.port

        raise 'http client host and port do not match rbac_base_endpoint'
      end
    end
  end
end

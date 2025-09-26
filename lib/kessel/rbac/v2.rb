# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Kessel
  module RBAC
    module V2
      WORKSPACE_ENDPOINT = '/api/rbac/v2/workspaces/'
      Workspace = Struct.new(:id, :name, :type, :description)

      def fetch_default_workspace(rbac_base_endpoint, org_id, auth: nil)
        fetch_workspace(rbac_base_endpoint, org_id, 'default', auth: auth)
      end

      def fetch_root_workspace(rbac_base_endpoint, org_id, auth: nil)
        fetch_workspace(rbac_base_endpoint, org_id, 'root', auth: auth)
      end

      private

      def run_request(uri, org_id, auth)
        Net::HTTP.start(uri.host, uri.port) do |http|
          request = Net::HTTP::Get.new uri
          request['x-rh-rbac-org-id'] = org_id

          auth&.configure_request(request)

          http.request(request)
        end
      end

      def process_response(response, workspace_type)
        unless response.is_a?(Net::HTTPSuccess)
          raise "Error while fetching the workspace of type #{workspace_type}. " \
                "Call returned status code #{response.code}"
        end

        workspace_response = JSON.parse(response.body)
        if workspace_response['data'].length != 1
          raise "Unexpected number of #{workspace_type} workspaces: #{workspace_response['data'].length}"
        end

        extract_workspace workspace_response
      end

      def extract_workspace(workspace_response)
        workspace = workspace_response['data'][0]

        Workspace.new(
          id: workspace['id'],
          name: workspace['name'],
          type: workspace['type'],
          description: workspace['description']
        )
      end

      def fetch_workspace(rbac_base_endpoint, org_id, workspace_type, auth: nil)
        rbac_base_endpoint = rbac_base_endpoint.delete_prefix('/')
        uri = URI(rbac_base_endpoint + WORKSPACE_ENDPOINT)
        query = {
          type: workspace_type
        }
        uri.query = URI.encode_www_form(query)

        response = run_request(uri, org_id, auth)
        process_response(response, workspace_type)
      end
    end
  end
end

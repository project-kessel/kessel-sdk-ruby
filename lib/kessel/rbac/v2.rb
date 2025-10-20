# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require_relative 'v2_helpers'
require_relative 'v2_http'
require_relative '../inventory/v1beta2'

module Kessel
  module RBAC
    module V2
      include Kessel::Inventory::V1beta2

      WORKSPACE_ENDPOINT = '/api/rbac/v2/workspaces/'
      DEFAULT_PAGE_LIMIT = 1000
      Workspace = Struct.new(:id, :name, :type, :description)

      def fetch_default_workspace(rbac_base_endpoint, org_id, auth: nil, http_client: nil)
        fetch_workspace(rbac_base_endpoint, org_id, 'default', auth: auth, http_client: http_client)
      end

      def fetch_root_workspace(rbac_base_endpoint, org_id, auth: nil, http_client: nil)
        fetch_workspace(rbac_base_endpoint, org_id, 'root', auth: auth, http_client: http_client)
      end

      def list_workspaces(inventory, subject, relation, continuation_token = nil)
        Enumerator.new do |yielder|
          loop do
            request = StreamedListObjectsRequest.new(
              object_type: workspace_type,
              relation: relation,
              subject: subject,
              pagination: RequestPagination.new(
                limit: DEFAULT_PAGE_LIMIT,
                continuation_token: continuation_token
              )
            )

            has_responses = false
            streamed_response = inventory.streamed_list_objects(request)
            streamed_response.each do |response|
              has_responses = true
              yielder << response

              continuation_token = response&.pagination&.continuation_token
            end

            break if !has_responses || !continuation_token
          end
        end
      end

      private

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

      def fetch_workspace(rbac_base_endpoint, org_id, workspace_type, auth: nil, http_client: nil)
        rbac_base_endpoint = rbac_base_endpoint.delete_suffix('/')
        uri = URI(rbac_base_endpoint + WORKSPACE_ENDPOINT)
        query = {
          type: workspace_type
        }
        uri.query = URI.encode_www_form(query)
        if http_client.nil?
          http_client = Net::HTTP.new(uri.host, uri.port)
        else
          check_http_client(http_client, uri)
        end

        response = run_request(uri, org_id, auth, http_client)
        process_response(response, workspace_type)
      end
    end
  end
end

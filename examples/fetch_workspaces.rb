#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'kessel-sdk'
require 'net/http'
require 'uri'

include Kessel::Auth
include Kessel::RBAC::V2

begin
  rbac_base_endpoint = ENV.fetch('RBAC_BASE_ENDPOINT', nil)
  discovery = fetch_oidc_discovery(ENV.fetch('AUTH_DISCOVERY_ISSUER_URL', nil))
  oauth = OAuth2ClientCredentials.new(
    client_id: ENV.fetch('AUTH_CLIENT_ID', nil),
    client_secret: ENV.fetch('AUTH_CLIENT_SECRET', nil),
    token_endpoint: discovery.token_endpoint,
    )

  # Set GRPC_DEFAULT_SSL_ROOTS_FILE_PATH if testing locally
  # e.g. GRPC_DEFAULT_SSL_ROOTS_FILE_PATH="$(mkcert -CAROOT)/rootCA.pem"
  auth = oauth2_auth_request(oauth)

  uri = URI(rbac_base_endpoint)
  # The http client has to be created with the same host / port combination
  http_client = Net::HTTP.new(uri.host, uri.port)
  http_client.start

  default_workspace = fetch_default_workspace(rbac_base_endpoint, '12345', auth: auth, http_client: http_client)
  p "Found default workspace: #{default_workspace.name} with id: #{default_workspace.id}"

  root_workspace = fetch_root_workspace(rbac_base_endpoint, '12345', auth: auth, http_client: http_client)
  p "Found root workspace: #{root_workspace.name} with id: #{root_workspace.id}"
rescue Exception => e
  p 'Error occurred while fetching workspaces:'
  p "Exception: #{e}"
ensure
  http_client.finish unless http_client.nil?
end

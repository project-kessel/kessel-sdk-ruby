#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'kessel-sdk'

include Kessel::Auth
include Kessel::RBAC::V2

begin
  discovery = fetch_oidc_discovery(ENV.fetch('AUTH_DISCOVERY_ISSUER_URL', nil))
  oauth = OAuth2ClientCredentials.new(
    client_id: ENV.fetch('AUTH_CLIENT_ID', nil),
    client_secret: ENV.fetch('AUTH_CLIENT_SECRET', nil),
    token_endpoint: discovery.token_endpoint,
    )

  # Set GRPC_DEFAULT_SSL_ROOTS_FILE_PATH if testing locally
  # e.g. GRPC_DEFAULT_SSL_ROOTS_FILE_PATH="$(mkcert -CAROOT)/rootCA.pem"
  auth = oauth2_auth_request(oauth)

  default_workspace = fetch_default_workspace('http://localhost:8888', '12345', auth: auth)
  p "Found default workspace: #{default_workspace.name} with id: #{default_workspace.id}"

  root_workspace = fetch_root_workspace('http://localhost:8888', '12345', auth: auth)
  p "Found root workspace: #{root_workspace.name} with id: #{root_workspace.id}"
rescue Exception => e
  p 'Error occurred while fetching workspaces:'
  p "Exception: #{e}"
end

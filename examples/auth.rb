#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'kessel-sdk'

include Kessel::Inventory::V1beta2
include Kessel::GRPC
include Kessel::Auth


subject_reference = SubjectReference.new(
  resource: ResourceReference.new(
    reporter: ReporterReference.new(
      type: 'rbac'
    ),
    resource_id: 'foobar',
    resource_type: 'principal'
  )
)

resource = ResourceReference.new(
  reporter: ReporterReference.new(
    type: 'rbac'
  ),
  resource_id: '1234',
  resource_type: 'workspace'
)

begin
  discovery = fetch_oidc_discovery(ENV.fetch('AUTH_DISCOVERY_ISSUER_URL', nil))
  oauth = OAuth2ClientCredentials.new(
    client_id: ENV.fetch('AUTH_CLIENT_ID', nil),
    client_secret: ENV.fetch('AUTH_CLIENT_SECRET', nil),
    token_endpoint: discovery.token_endpoint,
  )

  # Set GRPC_DEFAULT_SSL_ROOTS_FILE_PATH if testing locally
  # e.g. GRPC_DEFAULT_SSL_ROOTS_FILE_PATH="$(mkcert -CAROOT)/rootCA.pem"

  # Using the client builder
  client = KesselInventoryService::ClientBuilder.new(ENV.fetch('KESSEL_ENDPOINT', nil))
                                                .oauth2_client_authenticated(oauth2_client_credentials: oauth)
                                                .build

  # Or without a ClientBuilder
  # credentials = GRPC::Core::ChannelCredentials.new
  # credentials = credentials.compose(oauth2_call_credentials(oauth))
  #
  # client = KesselInventoryService::Stub.new(ENV.fetch('KESSEL_ENDPOINT', nil), credentials)

  response = client.check(
    CheckRequest.new(
      object: resource,
      relation: 'inventory_host_view',
      subject: subject_reference
    )
  )
  p 'check response received successfully:'
  p response
rescue Exception => e
  p 'gRPC error occurred during check:'
  p "Exception #{e}"
end

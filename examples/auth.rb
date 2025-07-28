#!/usr/bin/env ruby
# frozen_string_literal: true

# OIDC functionality requires the openid_connect gem to be installed:
# Add to your Gemfile: gem 'openid_connect', '~> 2.0'
# Then run: bundle install

require 'dotenv/load'
require 'kessel-sdk'

include Kessel::Inventory::V1beta2
include Kessel::Inventory::Client::Config

# Create client with OAuth authentication
begin
  client = KesselInventoryService::ClientBuilder.builder
                                                .with_target(ENV.fetch('KESSEL_ENDPOINT', nil))
                                                .with_insecure_credentials
                                                .with_auth(Auth.new(
                                                             client_id: ENV.fetch('AUTH_CLIENT_ID', nil),
                                                             client_secret: ENV.fetch('AUTH_CLIENT_SECRET', nil),
                                                             # OIDC discovery endpoint
                                                             issuer_url: ENV.fetch('AUTH_DISCOVERY_ISSUER_URL', nil)
                                                           ))
                                                .build

  # Create a subject reference for checking permissions
  subject_reference = SubjectReference.new(
    resource: ResourceReference.new(
      reporter: ReporterReference.new(
        type: 'rbac'
      ),
      resource_id: 'user123',
      resource_type: 'principal'
    )
  )

  # Create a resource reference
  resource = ResourceReference.new(
    reporter: ReporterReference.new(
      type: 'rbac'
    ),
    resource_id: 'workspace456',
    resource_type: 'workspace'
  )

  # Make a gRPC call with automatic OAuth authentication
  response = client.check(
    CheckRequest.new(
      object: resource,
      relation: 'inventory_host_view',
      subject: subject_reference
    )
  )

  puts 'OIDC-authenticated check response received successfully:'
  puts response
rescue Kessel::Auth::OAuthAuthenticationError => e
  puts 'OIDC authentication failed:'
  puts e.message
  puts ''
  puts 'Please check:'
  puts '- Client ID and secret are correct'
  puts '- Issuer URL supports OIDC discovery and is reachable'
  puts '- Your OIDC provider is configured for Client Credentials flow'
rescue Kessel::Inventory::IncompleteKesselConfiguration => e
  puts 'Configuration error:'
  puts e.message
rescue GRPC::Unauthenticated => e
  puts 'gRPC authentication failed:'
  puts e.message
  puts ''
  puts 'This usually means the OIDC token was rejected by the server.'
  puts 'Check your OIDC configuration and server setup.'
rescue GRPC::Unavailable => e
  puts 'gRPC connection failed:'
  puts e.message
  puts ''
  puts 'Please check that the server is running and reachable.'
rescue StandardError => e
  puts 'Unexpected error occurred:'
  puts "#{e.class}: #{e.message}"
end

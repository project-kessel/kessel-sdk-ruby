#!/usr/bin/env ruby
# frozen_string_literal: true

require 'kessel-sdk'
require 'kessel/console'
require 'json'
require 'base64'

include Kessel::Console

# --- From a parsed User identity hash ---
user_identity = {
  'type' => 'User',
  'org_id' => '12345',
  'user' => { 'user_id' => '7393748', 'username' => 'jdoe' }
}

subject = principal_from_rh_identity(user_identity)
puts "User principal:            #{subject.resource.resource_id}"

# --- From a parsed ServiceAccount identity hash ---
sa_identity = {
  'type' => 'ServiceAccount',
  'org_id' => '456',
  'service_account' => {
    'user_id' => '12345',
    'client_id' => 'b69eaf9e-e6a6-4f9e-805e-02987daddfbd',
    'username' => 'service-account-b69eaf9e'
  }
}

subject = principal_from_rh_identity(sa_identity)
puts "ServiceAccount principal:  #{subject.resource.resource_id}"

# --- From a raw base64-encoded x-rh-identity header ---
header_payload = {
  'identity' => {
    'type' => 'User',
    'org_id' => '12345',
    'user' => { 'user_id' => '7393748', 'username' => 'jdoe' }
  }
}

header = Base64.strict_encode64(JSON.generate(header_payload))
subject = principal_from_rh_identity_header(header)
puts "From header principal:     #{subject.resource.resource_id}"

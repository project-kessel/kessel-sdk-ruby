# frozen_string_literal: true

require 'json'
require 'base64'
require_relative 'rbac/v2_helpers'

module Kessel
  module Console
    include Kessel::RBAC::V2
    extend self

    DEFAULT_DOMAIN = 'redhat'

    IDENTITY_TYPE_FIELDS = {
      'User' => 'user',
      'ServiceAccount' => 'service_account'
    }.freeze

    def principal_from_rh_identity(identity, domain: DEFAULT_DOMAIN)
      user_id = extract_user_id(identity)
      principal_subject(user_id, domain)
    end

    def principal_from_rh_identity_header(header, domain: DEFAULT_DOMAIN)
      decoded = JSON.parse(Base64.decode64(header))
    rescue StandardError => e
      raise ArgumentError, "Failed to decode identity header: #{e.message}"
    else
      raise ArgumentError, 'Identity header did not decode to a JSON object' unless decoded.is_a?(Hash)

      identity = decoded['identity']
      raise ArgumentError, "Identity header is missing the 'identity' envelope key" if identity.nil?

      principal_from_rh_identity(identity, domain: domain)
    end

    private

    def extract_user_id(identity)
      raise ArgumentError, 'identity must be a Hash' unless identity.is_a?(Hash)

      identity_type = identity['type']
      field = identity_field_for(identity_type)
      details = identity_details_for(identity, field, identity_type)
      resolve_user_id(details, identity_type)
    end

    def identity_field_for(identity_type)
      IDENTITY_TYPE_FIELDS.fetch(identity_type) do
        supported = IDENTITY_TYPE_FIELDS.keys.sort.join(', ')
        raise ArgumentError, "Unsupported identity type: #{identity_type.inspect} (supported: #{supported})"
      end
    end

    def identity_details_for(identity, field, identity_type)
      details = identity[field]
      unless details.is_a?(Hash)
        raise ArgumentError, "Identity type #{identity_type.inspect} is missing the '#{field}' field"
      end

      details
    end

    def resolve_user_id(details, identity_type)
      user_id = details['user_id'].to_s
      raise ArgumentError, "Unable to resolve user ID from #{identity_type} identity (tried: user_id)" if user_id.empty?

      user_id
    end
  end
end

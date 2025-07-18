# frozen_string_literal: true

module Kessel
  module Inventory
    class IncompleteKesselConfiguration < StandardError
      def initialize(fields)
        fields.is_a? Array
        super("IncompleteKesselConfigurationError: Missing the following fields to build: #{fields.join(', ')}")
      end
    end

    module Client
      module Config
        KeepAlive = Struct.new(:time_ms, :timeout_ms, :permit_without_calls)
        Credentials = Struct.new(:type, :root_certs, :private_certs, :cert_chain)
        Auth = Struct.new(:client_id, :client_secret, :issuer_url)
        Config = Struct.new(:target, :credentials, :keep_alive, :auth)

        class Defaults
          def self.default_keep_alive
            KeepAlive.new(
              time_ms: 10_000,
              timeout_ms: 5000,
              permit_without_calls: true
            )
          end

          def self.default_credentials
            Credentials.new(
              type: 'secure'
            )
          end
        end
      end
    end
  end
end

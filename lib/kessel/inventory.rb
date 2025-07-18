# frozen_string_literal: true

module Kessel
  # Core Kessel Inventory module containing configuration and utilities
  # for the Kessel SDK.
  #
  # This module provides foundational classes for configuring gRPC clients,
  # handling authentication, and managing connection parameters for the
  # Kessel Inventory service.
  #
  # @author Project Kessel
  # @since 1.0.0
  module Inventory
    # Exception raised when required configuration fields are missing.
    #
    # This error is thrown during client builder validation when mandatory
    # configuration options (like target server) are not provided.
    #
    # @example
    #   raise IncompleteKesselConfiguration.new(['target', 'credentials'])
    #   # => "IncompleteKesselConfigurationError: Missing the following fields to build: target, credentials"
    class IncompleteKesselConfiguration < StandardError
      # Creates a new configuration error with the list of missing fields.
      #
      # @param fields [Array<String>] Array of missing configuration field names
      # @example
      #   error = IncompleteKesselConfiguration.new(['target'])
      #   error.message # => "IncompleteKesselConfigurationError: Missing the following fields to build: target"
      def initialize(fields)
        fields.is_a? Array
        super("IncompleteKesselConfigurationError: Missing the following fields to build: #{fields.join(', ')}")
      end
    end

    # Client configuration module containing data structures and defaults
    # for configuring gRPC connections to Kessel services.
    module Client
      # Configuration classes and structures for gRPC client settings.
      #
      # This module defines various configuration objects used to set up
      # gRPC connections, including keepalive settings, credentials, and
      # authentication parameters.
      module Config
        # gRPC keepalive configuration settings.
        #
        # Controls how the gRPC client manages connection health checks
        # and keepalive behavior with the server.
        #
        # @!attribute time_ms
        #   @return [Integer] Time in milliseconds before sending keepalive ping (default: 10000)
        # @!attribute timeout_ms
        #   @return [Integer] Keepalive ping timeout in milliseconds (default: 5000)
        # @!attribute permit_without_calls
        #   @return [Boolean] Allow keepalive pings when no calls are active (default: true)
        #
        # @example
        #   keepalive = KeepAlive.new(time_ms: 15000, timeout_ms: 3000, permit_without_calls: false)
        KeepAlive = Struct.new(:time_ms, :timeout_ms, :permit_without_calls)

        # gRPC channel credentials configuration.
        #
        # Specifies the type of credentials and certificate data for secure
        # or insecure connections.
        #
        # @!attribute type
        #   @return [String] Credential type - either "secure" or "insecure"
        # @!attribute root_certs
        #   @return [String, nil] PEM-encoded root certificates for server verification
        # @!attribute private_certs
        #   @return [String, nil] PEM-encoded private key for client authentication
        # @!attribute cert_chain
        #   @return [String, nil] PEM-encoded certificate chain for client authentication
        #
        # @example Insecure credentials
        #   creds = Credentials.new(type: "insecure")
        #
        # @example Secure credentials with custom certificates
        #   creds = Credentials.new(
        #     type: "secure",
        #     root_certs: File.read("ca.pem"),
        #     private_certs: File.read("client-key.pem"),
        #     cert_chain: File.read("client-cert.pem")
        #   )
        Credentials = Struct.new(:type, :root_certs, :private_certs, :cert_chain)

        # OAuth 2.0 authentication configuration.
        #
        # Contains credentials for OAuth 2.0 Client Credentials flow authentication
        # with Kessel services.
        #
        # @!attribute client_id
        #   @return [String] OAuth client identifier
        # @!attribute client_secret
        #   @return [String] OAuth client secret
        # @!attribute issuer_url
        #   @return [String] OAuth issuer URL for token endpoint discovery
        #
        # @example
        #   auth = Auth.new(
        #     client_id: "my-app-id",
        #     client_secret: "my-app-secret",
        #     issuer_url: "https://auth.kessel.example.com"
        #   )
        Auth = Struct.new(:client_id, :client_secret, :issuer_url)

        # Complete client configuration structure.
        #
        # Aggregates all configuration options needed to establish a gRPC
        # connection to Kessel services.
        #
        # @!attribute target
        #   @return [String] Server address in "host:port" format
        # @!attribute credentials
        #   @return [Credentials] gRPC credentials configuration
        # @!attribute keep_alive
        #   @return [KeepAlive] Connection keepalive settings
        # @!attribute auth
        #   @return [Auth] OAuth authentication configuration
        #
        # @example
        #   config = Config.new(
        #     target: "kessel.example.com:443",
        #     credentials: Credentials.new(type: "secure"),
        #     keep_alive: KeepAlive.new(time_ms: 10000),
        #     auth: Auth.new(client_id: "app", client_secret: "secret", issuer_url: "https://auth.example.com")
        #   )
        Config = Struct.new(:target, :credentials, :keep_alive, :auth)

        # Provides default configuration values for gRPC client settings.
        #
        # This class offers sensible defaults for keepalive and credential
        # configurations that work well in most environments.
        class Defaults
          # Returns default keepalive configuration.
          #
          # Provides conservative keepalive settings suitable for most
          # production environments.
          #
          # @return [KeepAlive] Default keepalive configuration with:
          #   - time_ms: 10000 (10 seconds between pings)
          #   - timeout_ms: 5000 (5 second ping timeout)
          #   - permit_without_calls: true (allow pings without active calls)
          #
          # @example
          #   keepalive = Defaults.default_keep_alive
          #   keepalive.time_ms # => 10000
          def self.default_keep_alive
            KeepAlive.new(
              time_ms: 10_000,
              timeout_ms: 5000,
              permit_without_calls: true
            )
          end

          # Returns default credentials configuration.
          #
          # Provides secure credentials by default, encouraging encrypted
          # connections in production environments.
          #
          # @return [Credentials] Default secure credentials configuration
          #
          # @example
          #   creds = Defaults.default_credentials
          #   creds.type # => "secure"
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

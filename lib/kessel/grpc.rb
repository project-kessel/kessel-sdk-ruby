# frozen_string_literal: true

require 'kessel/inventory'
require 'kessel/auth'
require 'grpc'

module Kessel
  # gRPC client building and configuration module.
  #
  # This module provides the ClientBuilder class for creating fluent,
  # configurable gRPC clients for Kessel services. It offers a builder
  # pattern API for setting up connections with proper authentication,
  # keepalive settings, and channel configurations.
  #
  # @author Project Kessel
  # @since 1.0.0
  module GRPC
    # Client-related classes and configuration for gRPC connections.
    module Client
      # Configuration classes specific to gRPC client setup.
      module Config
        # Extended gRPC configuration that includes channel arguments.
        #
        # Extends the base configuration with gRPC-specific channel arguments
        # for fine-tuning connection behavior.
        #
        # @!attribute target
        #   @return [String] Server address in "host:port" format
        # @!attribute credentials
        #   @return [Object] gRPC credentials object
        # @!attribute keep_alive
        #   @return [Hash] Keepalive configuration
        # @!attribute auth
        #   @return [Hash] Authentication configuration
        # @!attribute channel_args
        #   @return [Hash] Additional gRPC channel arguments
        #
        # @example
        #   config = GRPCConfig.new(
        #     "localhost:9000",
        #     :insecure,
        #     { time_ms: 10000 },
        #     { client_id: "app" },
        #     { "grpc.max_receive_message_length" => 1024 * 1024 }
        #   )
        GRPCConfig = Struct.new(:target, :credentials, :keep_alive, :auth, :channel_args)
      end
    end

    # Fluent builder for creating configured gRPC clients.
    #
    # The ClientBuilder class provides a fluent interface for configuring
    # and building gRPC clients with various options including authentication,
    # keepalive settings, and channel arguments.
    #
    # This class should not be used directly. Instead, use the service-specific
    # builders created by calling `.create(service_class)`.
    #
    # @example Creating a service-specific builder
    #   builder_class = ClientBuilder.create(MyService::Stub)
    #   client = builder_class.builder
    #     .with_target('localhost:9000')
    #     .with_insecure_credentials
    #     .build
    #
    # @see #create
    class ClientBuilder
      # Creates a new builder class for the specified gRPC service.
      #
      # This method dynamically creates an anonymous class that inherits from
      # ClientBuilder and is bound to a specific gRPC service class. Each
      # service gets its own builder class to avoid interference.
      #
      # @param service_class [Class] The gRPC service stub class (e.g., MyService::Stub)
      # @return [Class] A new builder class bound to the service
      #
      # @example
      #   health_builder = ClientBuilder.create(HealthService::Stub)
      #   inventory_builder = ClientBuilder.create(InventoryService::Stub)
      #
      #   # Each builder maintains its own service class
      #   health_client = health_builder.builder.with_target('localhost:9000').build
      #   inventory_client = inventory_builder.builder.with_target('localhost:9001').build
      def self.create(service_class)
        builder_class = Class.new(ClientBuilder)
        builder_class.instance_variable_set(:@service_class, service_class)
        define_class_methods(builder_class)
        define_instance_methods(builder_class)
        builder_class
      end

      private_class_method def self.define_class_methods(builder_class)
        builder_class.define_singleton_method(:builder) { new }
        builder_class.define_singleton_method(:service_class) { @service_class }
      end

      private_class_method def self.define_instance_methods(builder_class)
        # Build credentials method
        builder_class.define_method(:build_credentials) do
          return :this_channel_is_insecure if @credentials.type == 'insecure'

          ::GRPC::Core::ChannelCredentials.new(@credentials.root_certs, @credentials.private_certs,
                                               @credentials.cert_chain)
        end

        define_build_method(builder_class)

        # Mark methods as private
        builder_class.send(:private, :build_credentials)
      end

      private_class_method def self.define_build_method(builder_class)
        # Main build method
        builder_class.define_method(:build) do
          validate
          interceptors = []

          if @auth
            begin
              oauth_client = Auth::OAuth.new(
                client_id: @auth.client_id,
                client_secret: @auth.client_secret,
                issuer_url: @auth.issuer_url
              )
              interceptors << Auth::OAuthInterceptor.new(oauth_client)
            rescue Auth::OAuthDependencyError => e
              raise Auth::OAuthDependencyError,
                    "OIDC authentication requested but openid_connect gem is missing. #{e.message}\n" \
                    'Add "gem \'openid_connect\'" to your Gemfile or remove OAuth configuration.'
            end
          end

          self.class.service_class.new(@target, build_credentials,
                                       channel_args: @channel_args,
                                       interceptors: interceptors)
        end
      end

      # Initializes a new ClientBuilder with default configuration.
      #
      # Sets up default keepalive and credential settings from the Inventory
      # configuration defaults.
      def initialize
        super
        @channel_args = {}
        with_keep_alive(Inventory::Client::Config::Defaults.default_keep_alive)
        with_credentials_config(Inventory::Client::Config::Defaults.default_credentials)
      end

      # Sets the target server address.
      #
      # @param target [String] Server address in "host:port" format
      # @return [self] Returns self for method chaining
      #
      # @example
      #   builder.with_target('kessel.example.com:443')
      def with_target(target)
        @target = target
        self
      end

      # Configures the client to use insecure (non-TLS) connections.
      #
      # @return [self] Returns self for method chaining
      #
      # @example
      #   builder.with_insecure_credentials
      def with_insecure_credentials
        @credentials = Inventory::Client::Config::Credentials.new(type: 'insecure')
        # @credentials = :this_channel_is_insecure
        self
      end

      # Configures the client to use secure TLS connections with optional client certificates.
      #
      # @param root_certs [String, nil] PEM-encoded root certificates for server verification
      # @param private_certs [String, nil] PEM-encoded private key for client authentication
      # @param cert_chain [String, nil] PEM-encoded certificate chain for client authentication
      # @return [self] Returns self for method chaining
      #
      # @example Basic secure connection
      #   builder.with_secure_credentials
      #
      # @example With client certificates
      #   builder.with_secure_credentials(
      #     File.read('ca.pem'),
      #     File.read('client-key.pem'),
      #     File.read('client-cert.pem')
      #   )
      def with_secure_credentials(
        root_certs = nil,
        private_certs = nil,
        cert_chain = nil
      )
        @credentials = Inventory::Client::Config::Credentials.new(type: 'secure', root_certs: root_certs,
                                                                  private_certs: private_certs, cert_chain: cert_chain)
        self
      end

      # Sets the credentials configuration directly.
      #
      # @param credentials_config [Inventory::Client::Config::Credentials] Pre-configured credentials object
      # @return [self] Returns self for method chaining
      #
      # @example
      #   creds = Inventory::Client::Config::Credentials.new(type: 'secure')
      #   builder.with_credentials_config(creds)
      def with_credentials_config(credentials_config)
        @credentials = credentials_config
        self
      end

      # Sets the OAuth authentication configuration.
      #
      # When OAuth is configured, the client will automatically obtain and refresh
      # access tokens using the OAuth 2.0 Client Credentials flow. The tokens will
      # be included in all gRPC requests as Bearer tokens in the Authorization header.
      #
      # @param auth_config [Inventory::Client::Config::Auth] Authentication configuration
      # @return [self] Returns self for method chaining
      #
      # @example
      #   auth = Inventory::Client::Config::Auth.new(
      #     client_id: 'my-app',
      #     client_secret: 'secret',
      #     issuer_url: 'https://auth.example.com'
      #   )
      #   builder.with_auth(auth)
      #
      # @note OAuth functionality requires standard Ruby libraries (net/http, json, etc.)
      #   that are included in most Ruby installations. If dependencies are missing,
      #   an error will be raised when the client is built.
      def with_auth(auth_config)
        @auth = auth_config
        self
      end

      # Configures connection keepalive settings.
      #
      # @param keep_alive_config [Inventory::Client::Config::KeepAlive] Keepalive configuration
      # @return [self] Returns self for method chaining
      #
      # @example
      #   keepalive = Inventory::Client::Config::KeepAlive.new(
      #     time_ms: 15000,
      #     timeout_ms: 3000,
      #     permit_without_calls: false
      #   )
      #   builder.with_keep_alive(keepalive)
      def with_keep_alive(keep_alive_config)
        default_keep_alive_config = Inventory::Client::Config::Defaults.default_keep_alive
        @channel_args['grpc.keepalive_time_ms'] =
          nil_coalescing(keep_alive_config.time_ms, default_keep_alive_config.time_ms)
        @channel_args['grpc.keepalive_timeout_ms'] =
          nil_coalescing(keep_alive_config.timeout_ms, default_keep_alive_config.timeout_ms)
        @channel_args['grpc.keepalive_permit_without_calls'] =
          nil_coalescing(keep_alive_config.permit_without_calls, default_keep_alive_config.permit_without_calls) ? 1 : 0
        self
      end

      # Sets a custom gRPC channel option.
      #
      # @param arg [String] The gRPC channel argument name
      # @param value [Object] The value for the channel argument
      # @return [self] Returns self for method chaining
      #
      # @see https://grpc.github.io/grpc/core/group__grpc__arg__keys.html
      #
      # @example
      #   builder.with_channel_arg('grpc.max_receive_message_length', 1024 * 1024)
      def with_channel_arg(arg, value)
        @channel_args[arg] = value
        self
      end

      # Applies a complete configuration object to the builder.
      #
      # @param config [Inventory::Client::Config::Config] Complete configuration object
      # @return [self] Returns self for method chaining
      #
      # @example
      #   config = Inventory::Client::Config::Config.new(
      #     target: 'localhost:9000',
      #     credentials: Inventory::Client::Config::Credentials.new(type: 'insecure')
      #   )
      #   builder.with_config(config)
      def with_config(config)
        with_target(config.target)
        with_keep_alive(config.keep_alive) unless config.keep_alive.nil?
        with_credentials_config(config.credentials) unless config.credentials.nil?

        if config.respond_to? :channel_args
          config.channel_args.each_pair do |arg, value|
            with_channel_arg(arg, value)
          end
        end

        self
      end

      # Raises an error when called on the base ClientBuilder class.
      #
      # The base ClientBuilder should not be used directly for building clients.
      # Instead, use service-specific builders created with {.create}.
      #
      # @raise [RuntimeError] Always raises an error with usage instructions
      def build
        raise 'ClientBuilder should not be used directly. Instead use the client builder for the particular version ' \
              'you are targeting'
      end

      private

      # Validates that required configuration is present.
      #
      # @return [self] Returns self if validation passes
      # @raise [Kessel::Inventory::IncompleteKesselConfiguration] if required fields are missing
      # @api private
      def validate
        missing_fields = []
        missing_fields.push 'target' unless @target

        unless missing_fields.empty?
          raise ::Kessel::Inventory::IncompleteKesselConfiguration,
                missing_fields
        end

        self
      end

      # Returns the first non-nil value (null coalescing).
      #
      # @param first [Object] First value to check
      # @param second [Object] Fallback value if first is nil
      # @return [Object] Either first (if not nil) or second
      # @api private
      def nil_coalescing(first, second)
        first.nil? ? second : first
      end
    end
  end
end

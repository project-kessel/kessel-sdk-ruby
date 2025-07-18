require 'kessel/inventory'
require 'grpc'

module Kessel
  module GRPC

    module Client
      module Config
        GRPCConfig = Struct.new(:target, :credentials, :keep_alive, :auth, :channel_args)
      end
    end

    class ClientBuilder
      @target
      @credentials
      @auth
      @channel_args

      def self.create(service_class)
        client_builder_class = Class.new(ClientBuilder) do
          @@service_class = service_class

          def self.builder
            self.new
          end

          def build_credentials
            if @credentials.type == "insecure"
              return :this_channel_is_insecure
            else
              return ::GRPC::Core::ChannelCredentials.new(@credentials.root_certs, @credentials.private_certs, @credentials.cert_chain)
            end
          end

          def build
            self.validate
            interceptors = []

            if @auth
              # Connect oauth interceptor
            end

            @@service_class.new(@target, self.build_credentials, channel_args: @channel_args, interceptors: interceptors)
          end
        end

        client_builder_class
      end

      def initialize
        super
        @channel_args = {}
        self.with_keep_alive(Inventory::Client::Config::Defaults.default_keep_alive)
        self.with_credentials_config(Inventory::Client::Config::Defaults.default_credentials)
      end

      private def validate
        missing_fields = []
        missing_fields.push "target" unless @target

        raise ::Kessel::Inventory::IncompleteKesselConfiguration.new missing_fields unless missing_fields.empty?
        self
      end

      private def nil_coalescing(first, second)
        first.nil? ? second : first
      end

      def with_target(target)
        @target = target
        self
      end

      def with_insecure_credentials
        @credentials = Inventory::Client::Config::Credentials.new(type: "insecure")
        # @credentials = :this_channel_is_insecure
        self
      end

      def with_secure_credentials(
        root_certs = nil,
        private_certs = nil,
        cert_chain = nil
      )
        @credentials = Inventory::Client::Config::Credentials.new(type: "secure", root_certs: root_certs, private_certs: private_certs, cert_chain: cert_chain)
        self
      end

      def with_credentials_config(credentials_config)
        @credentials = credentials_config
        self
      end

      def with_auth(auth_config)
        @auth = auth_config
        self
      end

      def with_keep_alive(keep_alive_config)
        default_keep_alive_config = Inventory::Client::Config::Defaults.default_keep_alive
        @channel_args["grpc.keepalive_time_ms"] = self.nil_coalescing(keep_alive_config.time_ms, default_keep_alive_config.time_ms)
        @channel_args["grpc.keepalive_timeout_ms"] = self.nil_coalescing(keep_alive_config.timeout_ms, default_keep_alive_config.timeout_ms)
        @channel_args["grpc.keepalive_permit_without_calls"] = self.nil_coalescing(keep_alive_config.permit_without_calls, default_keep_alive_config.permit_without_calls)  ? 1 : 0
        self
      end

      # Sets a custom gRPC channel option.
      # @see {@link https://grpc.github.io/grpc/core/group__grpc__arg__keys.html}
      def with_channel_arg(arg, value)
        @channel_args[arg] = value
        self
      end

      def with_config(config)
        self.with_target(config.target)
            .with_keep_alive(config.keep_alive)
            .with_credentials_config(config.credentials)

        if config.respond_to? :channel_args
          config.channel_args.each_pair do |arg, value|
            self.with_channel_arg(arg, value)
          end
        end

        self
      end

      def build
        raise 'ClientBuilder should not be used directly. Instead use the client builder for the particular version you are targeting'
      end

    end
  end
end

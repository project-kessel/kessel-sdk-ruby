# frozen_string_literal: true

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
      def self.create(service_class)
        Class.new(ClientBuilder) do
          @service_class = service_class

          def self.builder
            new
          end

          class << self
            attr_reader :service_class
          end

          def build_credentials
            return :this_channel_is_insecure if @credentials.type == 'insecure'

            ::GRPC::Core::ChannelCredentials.new(@credentials.root_certs, @credentials.private_certs,
                                                 @credentials.cert_chain)
          end

          def build
            validate
            interceptors = []

            if @auth
              # Connect oauth interceptor
            end

            self.class.service_class.new(@target, build_credentials, channel_args: @channel_args,
                                                                     interceptors: interceptors)
          end
        end
      end

      def initialize
        super
        @channel_args = {}
        with_keep_alive(Inventory::Client::Config::Defaults.default_keep_alive)
        with_credentials_config(Inventory::Client::Config::Defaults.default_credentials)
      end

      def with_target(target)
        @target = target
        self
      end

      def with_insecure_credentials
        @credentials = Inventory::Client::Config::Credentials.new(type: 'insecure')
        # @credentials = :this_channel_is_insecure
        self
      end

      def with_secure_credentials(
        root_certs = nil,
        private_certs = nil,
        cert_chain = nil
      )
        @credentials = Inventory::Client::Config::Credentials.new(type: 'secure', root_certs: root_certs,
                                                                  private_certs: private_certs, cert_chain: cert_chain)
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
        @channel_args['grpc.keepalive_time_ms'] =
          nil_coalescing(keep_alive_config.time_ms, default_keep_alive_config.time_ms)
        @channel_args['grpc.keepalive_timeout_ms'] =
          nil_coalescing(keep_alive_config.timeout_ms, default_keep_alive_config.timeout_ms)
        @channel_args['grpc.keepalive_permit_without_calls'] =
          nil_coalescing(keep_alive_config.permit_without_calls, default_keep_alive_config.permit_without_calls) ? 1 : 0
        self
      end

      # Sets a custom gRPC channel option.
      # @see {@link https://grpc.github.io/grpc/core/group__grpc__arg__keys.html}
      def with_channel_arg(arg, value)
        @channel_args[arg] = value
        self
      end

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

      def build
        raise 'ClientBuilder should not be used directly. Instead use the client builder for the particular version ' \
              'you are targeting'
      end

      private

      def validate
        missing_fields = []
        missing_fields.push 'target' unless @target

        unless missing_fields.empty?
          raise ::Kessel::Inventory::IncompleteKesselConfiguration,
                missing_fields
        end

        self
      end

      def nil_coalescing(first, second)
        first.nil? ? second : first
      end
    end
  end
end

# frozen_string_literal: true

require 'grpc'
require 'kessel/grpc'

module Kessel
  module Inventory
    def service_builder(service_class)
      builder_class = Class.new(ClientBuilder)
      builder_class.instance_variable_set(:@service_class, service_class)
      builder_class
    end

    class ClientBuilder
      include Kessel::GRPC

      def initialize(target)
        @target = target
        raise 'Invalid target type' if @target.nil? || !@target.is_a?(String)
      end

      def oauth2_client_authenticated(oauth2_client_credentials:, channel_credentials: nil)
        @call_credentials = oauth2_call_credentials(oauth2_client_credentials)
        @channel_credentials = channel_credentials
        validate_credentials
        self
      end

      def authenticated(call_credentials: nil, channel_credentials: nil)
        @call_credentials = call_credentials
        @channel_credentials = channel_credentials
        validate_credentials
        self
      end

      def unauthenticated(channel_credentials: nil)
        @call_credentials = nil
        @channel_credentials = channel_credentials
        validate_credentials
        self
      end

      def insecure
        @call_credentials = nil
        @channel_credentials = :this_channel_is_insecure
        validate_credentials
        self
      end

      def build
        @channel_credentials = ::GRPC::Core::ChannelCredentials.new if @channel_credentials.nil?

        credentials = @channel_credentials
        credentials = credentials.compose(@call_credentials) unless @call_credentials.nil?
        self.class.service_class.new(@target, credentials)
      end

      private

      class << self
        attr_reader :service_class
      end

      def validate_credentials
        return unless @channel_credentials == :this_channel_is_insecure && !@call_credentials.nil?

        raise 'Invalid credential configuration: can not authenticate with insecure channel'
      end
    end
  end
end

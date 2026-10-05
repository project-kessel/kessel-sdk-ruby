# frozen_string_literal: true

require 'grpc'
require 'kessel/grpc'

module Kessel
  module Inventory
    def client_builder_for_stub(stub_class)
      builder_class = Class.new(ClientBuilder)
      builder_class.instance_variable_set(:@stub_class, stub_class)
      builder_class
    end

    class ClientBuilder
      include Kessel::GRPC

      MAX_KEEPALIVE_MILLISECONDS = 2_147_483_647
      private_constant :MAX_KEEPALIVE_MILLISECONDS

      def initialize(target)
        @target = target
        raise 'Invalid target type' if @target.nil? || !@target.is_a?(String)

        @channel_args = {
          'grpc.keepalive_time_ms' => 45_000,
          'grpc.keepalive_timeout_ms' => 10_000,
          'grpc.keepalive_permit_without_calls' => 1,
          'grpc.http2.max_pings_without_data' => 0
        }
      end

      def keepalive(interval: nil, timeout: nil, permit_without_calls: nil)
        @channel_args.merge!(keepalive_channel_args(interval, timeout, permit_without_calls))
        self
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
        self.class.stub_class.new(@target, credentials, channel_args: @channel_args.dup)
      end

      private

      class << self
        attr_reader :stub_class
      end

      def validate_credentials
        return unless @channel_credentials == :this_channel_is_insecure && !@call_credentials.nil?

        raise 'Invalid credential configuration: can not authenticate with insecure channel'
      end

      def keepalive_channel_args(interval, timeout, permit_without_calls)
        channel_args = {}
        channel_args['grpc.keepalive_time_ms'] = duration_to_milliseconds(interval, 'interval') unless interval.nil?
        channel_args['grpc.keepalive_timeout_ms'] = duration_to_milliseconds(timeout, 'timeout') unless timeout.nil?

        unless permit_without_calls.nil?
          unless permit_without_calls.equal?(true) || permit_without_calls.equal?(false)
            raise 'Invalid keepalive permit_without_calls: must be true, false, or nil'
          end

          channel_args['grpc.keepalive_permit_without_calls'] = permit_without_calls ? 1 : 0
        end

        channel_args
      end

      def duration_to_milliseconds(value, name)
        unless value.is_a?(Numeric) && !value.is_a?(Complex) && value.respond_to?(:finite?) && value.finite?
          raise "Invalid keepalive #{name}: must be a finite real number of seconds"
        end

        scaled_milliseconds = value * 1000
        unless valid_scaled_keepalive_milliseconds?(scaled_milliseconds)
          raise "Invalid keepalive #{name}: must convert to 1..#{MAX_KEEPALIVE_MILLISECONDS} milliseconds"
        end

        scaled_milliseconds.floor
      end

      def valid_scaled_keepalive_milliseconds?(milliseconds)
        milliseconds.respond_to?(:finite?) &&
          milliseconds.finite? &&
          (1...(MAX_KEEPALIVE_MILLISECONDS + 1)).cover?(milliseconds)
      end
    end
  end
end

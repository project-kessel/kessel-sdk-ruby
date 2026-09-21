# frozen_string_literal: true

require 'grpc'
require 'kessel/version'
require 'socket'
require 'timeout'

module Kessel
  # OpenID Connect authentication module for Kessel services.
  #
  # This module provides OIDC Client Credentials flow authentication
  # with automatic discovery. Works seamlessly with OIDC-compliant providers.
  #
  # @example Basic usage
  #   auth = Kessel::Auth::OAuth2ClientCredentials.new.new(
  #     client_id: 'my-app',
  #     client_secret: 'secret',
  #     token_endpoint: 'https://my-domain/auth/realms/my-realm/protocol/openid-connect/token'
  #   )
  #   token = auth.get_token
  #
  # @author Project Kessel
  # @since 1.0.0
  module Auth
    EXPIRATION_WINDOW = 300 # 5 minutes in seconds
    DEFAULT_EXPIRES_IN = 3600 # 1 hour in seconds

    # Exception raised when OAuth functionality is requested but dependencies are missing.
    class OAuthDependencyError < StandardError
      # Creates a new OAuth dependency error.
      #
      # @param message [String] Error message describing the missing dependency
      def initialize(message = 'OAuth functionality requires the openid_connect gem')
        super
      end
    end

    # Exception raised when OAuth authentication fails.
    class OAuthAuthenticationError < StandardError
      # Creates a new OAuth authentication error.
      #
      # @param message [String] Error message describing the authentication failure
      def initialize(message = 'OAuth authentication failed')
        super
      end
    end

    OIDCDiscoveryMetadata = Struct.new(:token_endpoint)
    RefreshTokenResponse = Struct.new(:access_token, :expires_at)

    module AuthRequest
      def configure_request(request)
        raise NotImplementedError, "#{self.class} must implement #configure_request"
      end
    end

    def fetch_oidc_discovery(provider_url)
      check_dependencies!
      discovery = ::OpenIDConnect::Discovery::Provider::Config.discover!(provider_url)
      OIDCDiscoveryMetadata.new(discovery.token_endpoint)
    rescue StandardError => e
      raise OAuthAuthenticationError, "Failed to discover OIDC configuration from #{provider_url}: #{e.message}"
    end

    def oauth2_auth_request(credentials)
      OAuth2AuthRequest.new(credentials)
    end

    private

    class OAuth2AuthRequest
      include AuthRequest

      def initialize(credentials)
        @credentials = credentials
      end

      def configure_request(request)
        token = @credentials.get_token
        request['authorization'] = "Bearer #{token.access_token}"
      end
    end

    # Checks if the openid_connect gem is available.
    #
    # @raise [OAuthDependencyError] if openid_connect gem is missing
    # @api private
    def check_dependencies!
      require 'openid_connect'
    rescue LoadError
      raise OAuthDependencyError,
            'OAuth functionality requires the openid_connect gem. Add "gem \'openid_connect\'" to your Gemfile.'
    end

    # OpenID Connect Client Credentials flow implementation using discovery.
    #
    # This provides a secure OIDC Client Credentials flow implementation with
    # automatic endpoint discovery. Works seamlessly with OIDC-compliant providers
    # that support discovery.
    #
    # @example
    #   oauth = OAuth2ClientCredentials.new(
    #     client_id: 'kessel-client',
    #     client_secret: 'super-secret-key',
    #     token_endpoint: 'https://my-domain/auth/realms/my-realm/protocol/openid-connect/token'
    #   )
    #
    #   # Get current access token (automatically cached and refreshed)
    #   token = oauth.get_token
    # rubocop:disable Metrics/ClassLength
    class OAuth2ClientCredentials
      include Kessel::Auth

      # Creates a new OIDC client with specified token endpoint.
      #
      # @param client_id [String] OIDC client identifier
      # @param client_secret [String] OIDC client secret
      # @param token_endpoint [String] OIDC token endpoint URL
      # @param retry [Hash] Optional token-endpoint retry settings. Keys are
      #   `max_retries` (non-negative Integer; 0 disables retries), `base_delay`
      #   and `max_delay` (positive finite seconds), and `jitter` (`:full` or
      #   `:none`). Defaults are 3, 0.5, 2.0, and `:full`, respectively.
      #
      # @raise [OAuthDependencyError] if the openid_connect gem is not available
      # @raise [OAuthAuthenticationError] if authentication fails
      # @raise [ArgumentError] if retry settings are invalid
      #
      # @example
      #   oauth = OAuth2ClientCredentials.new(
      #     client_id: 'my-app',
      #     client_secret: 'secret',
      #     token_endpoint: 'https://my-domain/auth/realms/my-realm/protocol/openid-connect/token'
      #   )
      def initialize(client_id:, client_secret:, token_endpoint:, **options)
        validate_retry_options!(options)
        retry_config = normalize_retry_config(options.fetch(:retry, {}))
        check_dependencies!

        @client_id = client_id
        @client_secret = client_secret
        @token_endpoint = token_endpoint
        @retry_config = retry_config
        @token_mutex = Mutex.new
        @generation_state_mutex = Mutex.new
        @generation_users = Hash.new(0)
        @generation_failures = {}
        @generation = 0
      end

      # Gets the current access token with automatic caching and refresh.
      #
      # Uses OIDC Client Credentials flow with automatic token caching,
      # expiration checking, and refresh logic.
      #
      # @return [RefreshTokenResponse] A valid access token
      # @raise [OAuthAuthenticationError] if token acquisition fails
      #
      # @example
      #   token = oauth.get_token
      #   # Use token in Authorization header: "Bearer #{token}"
      def get_token(force_refresh: false)
        return @cached_token if !force_refresh && token_valid?

        generation = register_generation

        begin
          @token_mutex.synchronize do
            failure = generation_failure(generation)
            raise failure if failure

            # Another thread already refreshed while we waited on the lock
            return @cached_token if @generation != generation && token_valid?

            begin
              @cached_token = refresh
            rescue StandardError => e
              record_failure_and_advance(generation, e)
              raise
            end
            advance_generation

            @cached_token
          end
        rescue StandardError => e
          raise OAuthAuthenticationError, "Failed to obtain client credentials token: #{e.message}", cause: e
        ensure
          unregister_generation(generation)
        end
      end

      private

      def register_generation
        @generation_state_mutex.synchronize do
          generation = @generation
          @generation_users[generation] += 1
          generation
        end
      end

      def generation_failure(generation)
        @generation_state_mutex.synchronize { @generation_failures[generation] }
      end

      def record_failure_and_advance(generation, error)
        @generation_state_mutex.synchronize do
          @generation_failures[generation] = error
          @generation += 1
        end
      end

      def advance_generation
        @generation_state_mutex.synchronize { @generation += 1 }
      end

      def unregister_generation(generation)
        @generation_state_mutex.synchronize do
          @generation_users[generation] -= 1
          next unless @generation_users[generation].zero?

          @generation_users.delete(generation)
          @generation_failures.delete(generation)
        end
      end

      def refresh
        client = create_oidc_client

        request_params = {
          grant_type: 'client_credentials',
          client_id: @client_id,
          client_secret: @client_secret
        }

        token_data = access_token_with_retries(client, request_params)
        RefreshTokenResponse.new(
          access_token: token_data.access_token,
          expires_at: Time.now + (token_data.expires_in || DEFAULT_EXPIRES_IN)
        ).freeze
      end

      def access_token_with_retries(client, request_params)
        retry_index = 0

        begin
          client.access_token!(request_params)
        rescue StandardError => e
          raise unless retryable_token_error?(e) && retry_index < @retry_config[:max_retries]

          sleep(retry_delay(retry_index))
          retry_index += 1
          retry
        end
      end

      def validate_retry_options!(options)
        unknown_keys = options.keys - [:retry]
        return if unknown_keys.empty?

        raise ArgumentError, "unknown keyword: #{unknown_keys.first.inspect}"
      end

      def normalize_retry_config(retry_options)
        unless retry_options.is_a?(Hash) && retry_options.keys.all?(Symbol)
          raise ArgumentError, 'retry must be a symbol-keyed Hash'
        end

        unknown_keys = retry_options.keys - %i[max_retries base_delay max_delay jitter]
        raise ArgumentError, "unknown retry option: #{unknown_keys.first.inspect}" unless unknown_keys.empty?

        config = {
          max_retries: 3,
          base_delay: 0.5,
          max_delay: 2.0,
          jitter: :full
        }.merge(retry_options)
        validate_retry_config_values!(config)
        config.freeze
      end

      def validate_retry_config_values!(config)
        unless config[:max_retries].is_a?(Integer) && config[:max_retries] >= 0
          raise ArgumentError, 'retry max_retries must be a non-negative Integer'
        end

        %i[base_delay max_delay].each do |key|
          next if valid_delay?(config[key])

          raise ArgumentError, "retry #{key} must be a positive finite Integer or Float"
        end

        return if %i[full none].include?(config[:jitter])

        raise ArgumentError, 'retry jitter must be :full or :none'
      end

      def valid_delay?(value)
        (value.is_a?(Integer) || value.is_a?(Float)) && value.positive? &&
          (!value.is_a?(Float) || value.finite?)
      end

      def retry_delay(retry_index)
        cap = [@retry_config[:max_delay], @retry_config[:base_delay] * (2**retry_index)].min
        return cap if @retry_config[:jitter] == :none

        rand(cap.to_f)
      end

      def retryable_token_error?(error)
        retryable_rack_oauth_error?(error) || retryable_transient_error?(error)
      end

      def retryable_rack_oauth_error?(error)
        return false unless defined?(::Rack::OAuth2::Client::Error)
        return false unless error.is_a?(::Rack::OAuth2::Client::Error)

        status = error.status
        status == 429 || (status.is_a?(Integer) && status.between?(500, 599))
      end

      def retryable_transient_error?(error)
        transient_error_classes.any? { |error_class| error.is_a?(error_class) }
      end

      def transient_error_classes
        %w[
          Faraday::ConnectionFailed
          Faraday::TimeoutError
          Timeout::Error
          SocketError
          EOFError
          Errno::ECONNREFUSED
          Errno::ECONNRESET
          Errno::ETIMEDOUT
          Errno::EHOSTUNREACH
          Errno::ENETUNREACH
        ].map { |name| optional_error_class(name) }.compact
      end

      def optional_error_class(name)
        Object.const_get(name, false)
      rescue NameError
        nil
      end

      # Checks if we have a valid cached token.
      #
      # @return [Boolean] true if token exists and not expired
      def token_valid?
        return false unless @cached_token

        expires_at = @cached_token['expires_at']
        return false unless expires_at

        Time.now.to_i + EXPIRATION_WINDOW < expires_at.to_i
      rescue StandardError
        false
      end

      # Creates an OIDC client using discovered configuration.
      #
      # @return [OpenIDConnect::Client] Configured OIDC client
      # @api private
      def create_oidc_client
        ::OpenIDConnect::Client.new(
          identifier: @client_id,
          secret: @client_secret,
          token_endpoint: @token_endpoint
        )
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

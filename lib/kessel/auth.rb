# frozen_string_literal: true

require 'grpc'
require 'kessel/version'

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

    def fetch_oidc_discovery(provider_url)
      check_dependencies!
      discovery = ::OpenIDConnect::Discovery::Provider::Config.discover!(provider_url)
      OIDCDiscoveryMetadata.new(discovery.token_endpoint)
    rescue StandardError => e
      raise OAuthAuthenticationError, "Failed to discover OIDC configuration from #{provider_url}: #{e.message}"
    end

    # Checks if the openid_connect gem is available.
    #
    # @raise [OAuthDependencyError] if openid_connect gem is missing
    # @api private
    private

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
    class OAuth2ClientCredentials
      include Kessel::Auth

      # Creates a new OIDC client with specified token endpoint.
      #
      # @param client_id [String] OIDC client identifier
      # @param client_secret [String] OIDC client secret
      # @param token_endpoint [String] OIDC token endpoint URL
      #
      # @raise [OAuthDependencyError] if the openid_connect gem is not available
      # @raise [OAuthAuthenticationError] if authentication fails
      #
      # @example
      #   oauth = OAuth2ClientCredentials.new(
      #     client_id: 'my-app',
      #     client_secret: 'secret',
      #     token_endpoint: 'https://my-domain/auth/realms/my-realm/protocol/openid-connect/token'
      #   )
      def initialize(client_id:, client_secret:, token_endpoint:)
        check_dependencies!

        @client_id = client_id
        @client_secret = client_secret
        @token_endpoint = token_endpoint
        @token_mutex = Mutex.new
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

        @token_mutex.synchronize do
          @cached_token = nil if force_refresh

          # Double-check: another thread might have refreshed the token
          return @cached_token if token_valid?

          @cached_token = refresh

          return @cached_token
        rescue StandardError => e
          raise OAuthAuthenticationError, "Failed to obtain client credentials token: #{e.message}"
        end
      end

      private

      def refresh
        client = create_oidc_client

        request_params = {
          grant_type: 'client_credentials',
          client_id: @client_id,
          client_secret: @client_secret
        }

        token_data = client.access_token!(request_params)
        RefreshTokenResponse.new(
          access_token: token_data.access_token,
          expires_at: Time.now + (token_data.expires_in || DEFAULT_EXPIRES_IN)
        ).freeze
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
  end
end

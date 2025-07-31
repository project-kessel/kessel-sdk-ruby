# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kessel::Auth do
  describe 'module structure' do
    it 'defines the Auth module' do
      expect(described_class).to be_a(Module)
    end

    it 'defines exception classes' do
      expect(Kessel::Auth::OAuthDependencyError).to be < StandardError
      expect(Kessel::Auth::OAuthAuthenticationError).to be < StandardError
    end

    it 'defines OIDCDiscoveryMetadata struct' do
      metadata = Kessel::Auth::OIDCDiscoveryMetadata.new('https://example.com/token')
      expect(metadata.token_endpoint).to eq('https://example.com/token')
    end
  end

  describe 'exception classes' do
    describe Kessel::Auth::OAuthDependencyError do
      it 'has a default message' do
        error = described_class.new
        expect(error.message).to eq('OAuth functionality requires the openid_connect gem')
      end

      it 'accepts a custom message' do
        custom_message = 'Custom dependency error'
        error = described_class.new(custom_message)
        expect(error.message).to eq(custom_message)
      end
    end

    describe Kessel::Auth::OAuthAuthenticationError do
      it 'has a default message' do
        error = described_class.new
        expect(error.message).to eq('OAuth authentication failed')
      end

      it 'accepts a custom message' do
        custom_message = 'Custom auth error'
        error = described_class.new(custom_message)
        expect(error.message).to eq(custom_message)
      end
    end
  end

  describe '#fetch_oidc_discovery' do
    let(:provider_url) { 'https://auth.example.com/auth/realms/test' }
    let(:token_endpoint) { 'https://auth.example.com/auth/realms/test/protocol/openid-connect/token' }

    # Create a test class that includes the module to test the method
    let(:test_class) do
      Class.new do
        include Kessel::Auth
      end
    end
    let(:test_instance) { test_class.new }

    before do
      # Stub the dependency check to always pass
      allow(test_instance).to receive(:check_dependencies!).and_return(true)
    end

    context 'when openid_connect gem is available and discovery succeeds' do
      let(:mock_discovery_config) do
        double('OpenIDConnect::Discovery::Provider::Config',
               token_endpoint: token_endpoint)
      end

             before do
         # Mock the OpenIDConnect discovery
         discovery_class = Class.new do
           def self.discover!(url)
             raise "Mocked discovery not set up for: #{url}"
           end
         end
         stub_const('OpenIDConnect::Discovery::Provider::Config', discovery_class)
         allow(discovery_class).to receive(:discover!)
           .with(provider_url)
           .and_return(mock_discovery_config)
       end

      it 'returns OIDCDiscoveryMetadata with token_endpoint' do
        result = test_instance.fetch_oidc_discovery(provider_url)

        expect(result).to be_a(Kessel::Auth::OIDCDiscoveryMetadata)
        expect(result.token_endpoint).to eq(token_endpoint)
      end

      it 'calls dependency check' do
        expect(test_instance).to receive(:check_dependencies!)
        test_instance.fetch_oidc_discovery(provider_url)
      end

      it 'calls OpenIDConnect discovery with correct provider URL' do
        expect(OpenIDConnect::Discovery::Provider::Config).to receive(:discover!)
          .with(provider_url)
          .and_return(mock_discovery_config)

        test_instance.fetch_oidc_discovery(provider_url)
      end
    end

    context 'when discovery fails' do
      let(:discovery_error) { StandardError.new('Network error') }

             before do
         discovery_class = Class.new do
           def self.discover!(url)
             raise "Mocked discovery not set up for: #{url}"
           end
         end
         stub_const('OpenIDConnect::Discovery::Provider::Config', discovery_class)
         allow(discovery_class).to receive(:discover!)
           .with(provider_url)
           .and_raise(discovery_error)
       end

      it 'raises OAuthAuthenticationError with descriptive message' do
        expect { test_instance.fetch_oidc_discovery(provider_url) }
          .to raise_error(Kessel::Auth::OAuthAuthenticationError,
                         "Failed to discover OIDC configuration from #{provider_url}: Network error")
      end
    end

         context 'when dependency check fails' do
       before do
         allow(test_instance).to receive(:check_dependencies!)
           .and_raise(Kessel::Auth::OAuthDependencyError, 'openid_connect gem missing')
       end

       it 'raises OAuthAuthenticationError with dependency error message' do
         expect { test_instance.fetch_oidc_discovery(provider_url) }
           .to raise_error(Kessel::Auth::OAuthAuthenticationError,
                          /Failed to discover OIDC configuration.*openid_connect gem missing/)
       end
     end
  end

  describe Kessel::Auth::OAuth do
    let(:client_id) { 'test-client' }
    let(:client_secret) { 'test-secret' }
    let(:token_endpoint) { 'https://auth.example.com/protocol/openid-connect/token' }

         describe '#initialize' do
       context 'when openid_connect gem is available' do
         it 'creates an OAuth instance with correct attributes' do
           # Mock the private method by allowing the OAuth instance to access it
           allow_any_instance_of(described_class).to receive(:require).with('openid_connect').and_return(true)

           oauth = described_class.new(
             client_id: client_id,
             client_secret: client_secret,
             token_endpoint: token_endpoint
           )

           expect(oauth.client_id).to eq(client_id)
           expect(oauth.token_endpoint).to eq(token_endpoint)
         end
       end

       context 'when openid_connect gem is missing' do
         it 'raises OAuthDependencyError when gem is missing' do
           # Mock require to fail
           allow_any_instance_of(described_class).to receive(:require).with('openid_connect')
             .and_raise(LoadError, 'cannot load such file -- openid_connect')

           expect do
             described_class.new(
               client_id: client_id,
               client_secret: client_secret,
               token_endpoint: token_endpoint
             )
           end.to raise_error(Kessel::Auth::OAuthDependencyError)
         end
       end
     end

         describe '#token' do
       let(:oauth) do
         # Mock require to succeed
         allow_any_instance_of(described_class).to receive(:require).with('openid_connect').and_return(true)

         described_class.new(
           client_id: client_id,
           client_secret: client_secret,
           token_endpoint: token_endpoint
         )
       end

       let(:mock_token_response) { { 'access_token' => 'test-token', 'expires_at' => Time.now.to_i + 3600 } }
                let(:mock_oidc_client) do
           double('OpenIDConnect::Client', token: double('token', access_token: 'test-token', expires_in: 3600))
         end

         before do
           # Mock OpenIDConnect module and Client class
           openid_module = Module.new
           client_class = Class.new do
             def initialize(*args); end
             def access_token!(params)
               Struct.new(:access_token, :expires_in).new('test-token', 3600)
             end
           end
           openid_module.const_set('Client', client_class)
           stub_const('OpenIDConnect', openid_module)
         end

                  it 'returns the token from client credentials flow' do
           token = oauth.token
           expect(token).to eq('test-token')
         end
       end

       describe '#refresh' do
         let(:oauth) do
           # Mock require to succeed
           allow_any_instance_of(described_class).to receive(:require).with('openid_connect').and_return(true)
           
           described_class.new(
             client_id: client_id,
             client_secret: client_secret,
             token_endpoint: token_endpoint
           )
         end

         before do
           # Mock OpenIDConnect module and Client class
           openid_module = Module.new
           client_class = Class.new do
             def initialize(*args); end
             def access_token!(params)
               Struct.new(:access_token, :expires_in).new('fresh-token', 3600)
             end
           end
           openid_module.const_set('Client', client_class)
           stub_const('OpenIDConnect', openid_module)
         end

         it 'returns the raw OIDC token response' do
           response = oauth.refresh
           expect(response.access_token).to eq('fresh-token')
           expect(response.expires_in).to eq(3600)
         end
       end
  end

  describe Kessel::Auth::OAuthInterceptor do
    let(:mock_oauth_client) do
      double('OAuth', token: 'test-access-token')
    end

    let(:interceptor) { described_class.new(mock_oauth_client) }

    describe '#initialize' do
      it 'stores the oauth client' do
        expect(interceptor.instance_variable_get(:@oauth_client)).to eq(mock_oauth_client)
      end

      it 'inherits from GRPC::ClientInterceptor' do
        expect(interceptor).to be_a(GRPC::ClientInterceptor)
      end
    end

         describe 'interceptor methods' do
       let(:metadata) { {} }

       # Test that the interceptor modifies metadata correctly
       describe '#request_response' do
         it 'adds authorization header to metadata' do
           result = interceptor.request_response(
             request: 'test_request',
             call: double('call'),
             method: 'test_method',
             metadata: metadata
           ) { 'response' }

           expect(metadata).to include('authorization' => 'Bearer test-access-token')
           expect(result).to eq('response')
         end
       end

       describe '#client_streamer' do
         it 'adds authorization header to metadata' do
           result = interceptor.client_streamer(
             requests: ['request'],
             call: double('call'),
             method: 'test_method',
             metadata: metadata
           ) { 'response' }

           expect(metadata).to include('authorization' => 'Bearer test-access-token')
           expect(result).to eq('response')
         end
       end

       describe '#server_streamer' do
         it 'adds authorization header to metadata' do
           result = interceptor.server_streamer(
             request: 'test_request',
             call: double('call'),
             method: 'test_method',
             metadata: metadata
           ) { 'response' }

           expect(metadata).to include('authorization' => 'Bearer test-access-token')
           expect(result).to eq('response')
         end
       end

       describe '#bidi_streamer' do
         it 'adds authorization header to metadata' do
           result = interceptor.bidi_streamer(
             requests: ['request'],
             call: double('call'),
             method: 'test_method',
             metadata: metadata
           ) { 'response' }

           expect(metadata).to include('authorization' => 'Bearer test-access-token')
           expect(result).to eq('response')
         end
       end
     end
  end
end

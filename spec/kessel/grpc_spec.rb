# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kessel::GRPC do
  describe 'module structure' do
    it 'has the expected module hierarchy' do
      expect(described_class).to be_a(Module)
      expect(Kessel::GRPC::Client).to be_a(Module)
      expect(Kessel::GRPC::Client::Config).to be_a(Module)
    end

    it 'defines GRPCConfig struct' do
      config = Kessel::GRPC::Client::Config::GRPCConfig.new(
        'localhost:9000',
        :insecure,
        { time_ms: 1000 },
        { client_id: 'test' },
        { arg: 'value' }
      )

      expect(config.target).to eq('localhost:9000')
      expect(config.credentials).to eq(:insecure)
      expect(config.keep_alive).to eq({ time_ms: 1000 })
      expect(config.auth).to eq({ client_id: 'test' })
      expect(config.channel_args).to eq({ arg: 'value' })
    end
  end

  describe Kessel::GRPC::ClientBuilder do
    let(:client_builder_class) { described_class }

    describe '.create' do
      subject(:builder_class) { client_builder_class.create(mock_service_class) }

      let(:mock_service_class) do
        Class.new do
          def self.new(target, credentials, channel_args: {}, interceptors: [])
            {
              target: target,
              credentials: credentials,
              channel_args: channel_args,
              interceptors: interceptors
            }
          end
        end
      end

      it 'returns a class that inherits from ClientBuilder' do
        expect(builder_class).to be < client_builder_class
      end

      it 'sets the service class as a class variable' do
        expect(builder_class.class_variable_get(:@@service_class)).to eq(mock_service_class)
      end

      describe 'generated builder class' do
        let(:builder_instance) { builder_class.builder }

        it 'has a builder class method that returns an instance' do
          expect(builder_class).to respond_to(:builder)
          expect(builder_instance).to be_an_instance_of(builder_class)
        end

        describe '#build_credentials' do
          context 'with insecure credentials' do
            before do
              builder_instance.with_insecure_credentials
            end

            it 'returns the insecure symbol' do
              expect(builder_instance.send(:build_credentials)).to eq(:this_channel_is_insecure)
            end
          end

          context 'with secure credentials' do
            let(:root_certs) { 'root_cert_data' }
            let(:private_certs) { 'private_cert_data' }
            let(:cert_chain) { 'cert_chain_data' }

            before do
              builder_instance.with_secure_credentials(root_certs, private_certs, cert_chain)

              # Mock the GRPC::Core::ChannelCredentials.new method
              allow(GRPC::Core::ChannelCredentials).to receive(:new)
                .with(root_certs, private_certs, cert_chain)
                .and_return(:mocked_credentials)
            end

            it 'returns GRPC channel credentials' do
              expect(builder_instance.send(:build_credentials)).to eq(:mocked_credentials)
            end
          end
        end

        describe '#build' do
          context 'with valid configuration' do
            let(:target) { 'localhost:9000' }
            let(:expected_result) do
              {
                target: target,
                credentials: :this_channel_is_insecure,
                channel_args: hash_including('grpc.keepalive_time_ms'),
                interceptors: []
              }
            end

            before do
              builder_instance
                .with_target(target)
                .with_insecure_credentials
            end

            it 'builds a gRPC client with correct parameters' do
              result = builder_instance.build
              expect(result).to match(expected_result)
            end

            it 'includes keepalive settings in channel args' do
              result = builder_instance.build
              channel_args = result[:channel_args]

              expect(channel_args).to include('grpc.keepalive_time_ms')
              expect(channel_args).to include('grpc.keepalive_timeout_ms')
              expect(channel_args).to include('grpc.keepalive_permit_without_calls')
            end
          end

          context 'without required target' do
            before do
              builder_instance.with_insecure_credentials
            end

            it 'raises IncompleteKesselConfiguration error' do
              expect { builder_instance.build }.to raise_error(
                Kessel::Inventory::IncompleteKesselConfiguration,
                /Missing the following fields to build: target/
              )
            end
          end
        end
      end
    end

    describe 'instance methods' do
      let(:builder) { client_builder_class.new }

      describe '#initialize' do
        it 'sets default configuration' do
          expect(builder.instance_variable_get(:@channel_args)).to be_a(Hash)
          expect(builder.instance_variable_get(:@credentials)).to be_a(Kessel::Inventory::Client::Config::Credentials)
        end

        it 'sets default keepalive configuration' do
          channel_args = builder.instance_variable_get(:@channel_args)
          expect(channel_args['grpc.keepalive_time_ms']).to eq(10_000)
          expect(channel_args['grpc.keepalive_timeout_ms']).to eq(5000)
        end
      end

      describe '#with_target' do
        let(:target) { 'example.com:443' }

        it 'sets the target and returns self' do
          result = builder.with_target(target)
          expect(result).to be(builder)
          expect(builder.instance_variable_get(:@target)).to eq(target)
        end
      end

      describe '#with_insecure_credentials' do
        it 'sets insecure credentials and returns self' do
          result = builder.with_insecure_credentials
          expect(result).to be(builder)

          credentials = builder.instance_variable_get(:@credentials)
          expect(credentials.type).to eq('insecure')
        end
      end

      describe '#with_secure_credentials' do
        let(:root_certs) { 'root_cert_data' }
        let(:private_certs) { 'private_cert_data' }
        let(:cert_chain) { 'cert_chain_data' }

        it 'sets secure credentials and returns self' do
          result = builder.with_secure_credentials(root_certs, private_certs, cert_chain)
          expect(result).to be(builder)

          credentials = builder.instance_variable_get(:@credentials)
          expect(credentials.type).to eq('secure')
          expect(credentials.root_certs).to eq(root_certs)
          expect(credentials.private_certs).to eq(private_certs)
          expect(credentials.cert_chain).to eq(cert_chain)
        end
      end

      describe '#with_credentials_config' do
        let(:credentials_config) do
          Kessel::Inventory::Client::Config::Credentials.new(
            type: 'custom',
            root_certs: 'custom_root'
          )
        end

        it 'sets the credentials config and returns self' do
          result = builder.with_credentials_config(credentials_config)
          expect(result).to be(builder)
          expect(builder.instance_variable_get(:@credentials)).to eq(credentials_config)
        end
      end

      describe '#with_auth' do
        let(:auth_config) do
          Kessel::Inventory::Client::Config::Auth.new(
            'client_id',
            'client_secret',
            'https://auth.example.com'
          )
        end

        it 'sets the auth config and returns self' do
          result = builder.with_auth(auth_config)
          expect(result).to be(builder)
          expect(builder.instance_variable_get(:@auth)).to eq(auth_config)
        end
      end

      describe '#with_keep_alive' do
        let(:keep_alive_config) do
          Kessel::Inventory::Client::Config::KeepAlive.new(
            time_ms: 5000,
            timeout_ms: 2000,
            permit_without_calls: false
          )
        end

        it 'sets keep alive configuration and returns self' do
          result = builder.with_keep_alive(keep_alive_config)
          expect(result).to be(builder)

          channel_args = builder.instance_variable_get(:@channel_args)
          expect(channel_args['grpc.keepalive_time_ms']).to eq(5000)
          expect(channel_args['grpc.keepalive_timeout_ms']).to eq(2000)
          expect(channel_args['grpc.keepalive_permit_without_calls']).to eq(0)
        end

        it 'merges with default values using nil coalescing' do
          partial_config = Kessel::Inventory::Client::Config::KeepAlive.new(
            time_ms: 3000,
            timeout_ms: nil,
            permit_without_calls: nil
          )

          builder.with_keep_alive(partial_config)
          channel_args = builder.instance_variable_get(:@channel_args)

          expect(channel_args['grpc.keepalive_time_ms']).to eq(3000)
          expect(channel_args['grpc.keepalive_timeout_ms']).to eq(5000) # default
          expect(channel_args['grpc.keepalive_permit_without_calls']).to eq(1) # default (true -> 1)
        end
      end

      describe '#with_channel_arg' do
        it 'sets custom channel argument and returns self' do
          result = builder.with_channel_arg('custom.arg', 'custom_value')
          expect(result).to be(builder)

          channel_args = builder.instance_variable_get(:@channel_args)
          expect(channel_args['custom.arg']).to eq('custom_value')
        end
      end

      describe '#with_config' do
        let(:target) { 'configured.example.com:443' }
        let(:credentials) { Kessel::Inventory::Client::Config::Credentials.new(type: 'secure') }
        let(:keep_alive) { Kessel::Inventory::Client::Config::KeepAlive.new(time_ms: 8000) }
        let(:config) do
          config_instance = Kessel::Inventory::Client::Config::Config.new(target, credentials, keep_alive, nil)
          # Add channel_args method
          def config_instance.channel_args
            { 'custom.setting' => 'configured_value' }
          end
          config_instance
        end

        it 'applies full configuration and returns self' do
          result = builder.with_config(config)
          expect(result).to be(builder)

          expect(builder.instance_variable_get(:@target)).to eq(target)
          expect(builder.instance_variable_get(:@credentials)).to eq(credentials)

          channel_args = builder.instance_variable_get(:@channel_args)
          expect(channel_args['grpc.keepalive_time_ms']).to eq(8000)
          expect(channel_args['custom.setting']).to eq('configured_value')
        end

        context 'with nil values' do
          let(:config_with_nils) do
            Kessel::Inventory::Client::Config::Config.new(target, nil, nil, nil)
          end

          it 'skips nil configurations' do
            original_credentials = builder.instance_variable_get(:@credentials)

            builder.with_config(config_with_nils)

            expect(builder.instance_variable_get(:@target)).to eq(target)
            expect(builder.instance_variable_get(:@credentials)).to eq(original_credentials)
          end
        end
      end

      describe '#build' do
        it 'raises an error when called directly on base class' do
          expect { builder.build }.to raise_error(
            'ClientBuilder should not be used directly. Instead use the client builder for the particular ' \
            'version you are targeting'
          )
        end
      end

      describe 'private methods' do
        describe '#validate' do
          context 'with missing target' do
            it 'raises IncompleteKesselConfiguration' do
              expect { builder.send(:validate) }.to raise_error(
                Kessel::Inventory::IncompleteKesselConfiguration,
                /Missing the following fields to build: target/
              )
            end
          end

          context 'with valid configuration' do
            before { builder.with_target('localhost:9000') }

            it 'returns self' do
              expect(builder.send(:validate)).to be(builder)
            end
          end
        end

        describe '#nil_coalescing' do
          it 'returns first value when not nil' do
            result = builder.send(:nil_coalescing, 'first', 'second')
            expect(result).to eq('first')
          end

          it 'returns second value when first is nil' do
            result = builder.send(:nil_coalescing, nil, 'second')
            expect(result).to eq('second')
          end
        end
      end
    end

    describe 'fluent API chaining' do
      let(:builder) { client_builder_class.new }

      it 'allows method chaining' do
        result = builder
                 .with_target('example.com:443')
                 .with_insecure_credentials
                 .with_channel_arg('custom.arg', 'value')

        expect(result).to be(builder)
        expect(builder.instance_variable_get(:@target)).to eq('example.com:443')

        credentials = builder.instance_variable_get(:@credentials)
        expect(credentials.type).to eq('insecure')

        channel_args = builder.instance_variable_get(:@channel_args)
        expect(channel_args['custom.arg']).to eq('value')
      end
    end
  end
end

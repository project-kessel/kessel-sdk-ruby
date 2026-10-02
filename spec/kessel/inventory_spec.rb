# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kessel::Inventory do
  describe 'module structure' do
    it 'defines the Inventory module' do
      expect(defined?(Kessel::Inventory)).to eq('constant')
      expect(Kessel::Inventory).to be_a(Module)
    end

    it 'defines the client_builder_for_stub method' do
      expect(Kessel::Inventory).to respond_to(:client_builder_for_stub)
    end

    it 'defines the ClientBuilder class' do
      expect(defined?(Kessel::Inventory::ClientBuilder)).to eq('constant')
      expect(Kessel::Inventory::ClientBuilder).to be_a(Class)
    end
  end

  describe '#client_builder_for_stub' do
    let(:mock_stub_class) { Class.new }

    it 'returns a ClientBuilder subclass' do
      builder_class = Kessel::Inventory.client_builder_for_stub(mock_stub_class)
      expect(builder_class).to be_a(Class)
      expect(builder_class.ancestors).to include(Kessel::Inventory::ClientBuilder)
    end

    it 'sets the service class on the builder' do
      builder_class = Kessel::Inventory.client_builder_for_stub(mock_stub_class)
      expect(builder_class.instance_variable_get(:@stub_class)).to eq(mock_stub_class)
    end
  end

  describe 'ClientBuilder' do
    let(:target) { 'localhost:9000' }
    let(:builder) { Kessel::Inventory::ClientBuilder.new(target) }
    let(:mock_stub_class) { double('ServiceClass') }
    let(:mock_stub_instance) { double('StubInstance') }
    let(:oauth_credentials) { double('OAuth2ClientCredentials') }
    let(:channel_credentials) { double('ChannelCredentials') }
    let(:call_credentials) { double('CallCredentials') }

    before do
      # Mock the service class for the builder
      allow(builder.class).to receive(:stub_class).and_return(mock_stub_class)
      allow(mock_stub_class).to receive(:new).and_return(mock_stub_instance)

      # Mock GRPC credentials
      allow(GRPC::Core::ChannelCredentials).to receive(:new).and_return(channel_credentials)
      allow(channel_credentials).to receive(:compose).and_return(channel_credentials)

      # Mock oauth2_call_credentials function - stub it on the ClientBuilder class
      allow_any_instance_of(Kessel::Inventory::ClientBuilder)
        .to receive(:oauth2_call_credentials)
        .and_return(call_credentials)
    end

    describe '#initialize' do
      it 'creates a ClientBuilder with valid target' do
        expect { Kessel::Inventory::ClientBuilder.new('localhost:9000') }.not_to raise_error
      end

      it 'raises error for nil target' do
        expect { Kessel::Inventory::ClientBuilder.new(nil) }.to raise_error('Invalid target type')
      end

      it 'raises error for non-string target' do
        expect { Kessel::Inventory::ClientBuilder.new(123) }.to raise_error('Invalid target type')
      end

      it 'returns self for method chaining' do
        result = Kessel::Inventory::ClientBuilder.new(target)
        expect(result).to be_a(Kessel::Inventory::ClientBuilder)
      end
    end

    describe '#oauth2_client_authenticated' do
      it 'configures OAuth2 client credentials authentication' do
        result = builder.oauth2_client_authenticated(oauth2_client_credentials: oauth_credentials)
        expect(result).to eq(builder)
        expect(builder.instance_variable_get(:@call_credentials)).to eq(call_credentials)
      end

      it 'accepts optional channel credentials' do
        custom_channel_creds = double('CustomChannelCredentials')
        result = builder.oauth2_client_authenticated(
          oauth2_client_credentials: oauth_credentials,
          channel_credentials: custom_channel_creds
        )
        expect(result).to eq(builder)
        expect(builder.instance_variable_get(:@channel_credentials)).to eq(custom_channel_creds)
      end

      it 'calls validate_credentials' do
        expect(builder).to receive(:validate_credentials)
        builder.oauth2_client_authenticated(oauth2_client_credentials: oauth_credentials)
      end
    end

    describe '#authenticated' do
      it 'configures custom authentication credentials' do
        result = builder.authenticated(call_credentials: call_credentials)
        expect(result).to eq(builder)
        expect(builder.instance_variable_get(:@call_credentials)).to eq(call_credentials)
      end

      it 'accepts optional channel credentials' do
        result = builder.authenticated(
          call_credentials: call_credentials,
          channel_credentials: channel_credentials
        )
        expect(result).to eq(builder)
        expect(builder.instance_variable_get(:@channel_credentials)).to eq(channel_credentials)
      end

      it 'calls validate_credentials' do
        expect(builder).to receive(:validate_credentials)
        builder.authenticated(call_credentials: call_credentials)
      end
    end

    describe '#unauthenticated' do
      it 'configures unauthenticated client' do
        result = builder.unauthenticated
        expect(result).to eq(builder)
        expect(builder.instance_variable_get(:@call_credentials)).to be_nil
      end

      it 'accepts optional channel credentials' do
        result = builder.unauthenticated(channel_credentials: channel_credentials)
        expect(result).to eq(builder)
        expect(builder.instance_variable_get(:@channel_credentials)).to eq(channel_credentials)
      end

      it 'calls validate_credentials' do
        expect(builder).to receive(:validate_credentials)
        builder.unauthenticated
      end
    end

    describe '#insecure' do
      it 'configures insecure connection' do
        result = builder.insecure
        expect(result).to eq(builder)
        expect(builder.instance_variable_get(:@call_credentials)).to be_nil
        expect(builder.instance_variable_get(:@channel_credentials)).to eq(:this_channel_is_insecure)
      end

      it 'calls validate_credentials' do
        expect(builder).to receive(:validate_credentials)
        builder.insecure
      end
    end

    describe '#keepalive' do
      it 'converts seconds to milliseconds and preserves omitted values across updates' do
        result = builder.keepalive(interval: 0.75, timeout: 1.25, permit_without_calls: false)
                        .keepalive(interval: 1.2349, timeout: 2.3459, permit_without_calls: nil)

        expect(result).to be(builder)
        expect(mock_stub_class).to receive(:new).with(
          target,
          channel_credentials,
          channel_args: {
            'grpc.keepalive_time_ms' => 1_234,
            'grpc.keepalive_timeout_ms' => 2_345,
            'grpc.keepalive_permit_without_calls' => 0,
            'grpc.http2.max_pings_without_data' => 0
          }
        )
        builder.build
      end

      it 'accepts the minimum and maximum representable millisecond values' do
        builder.keepalive(interval: Rational(1, 1000), timeout: Rational(2_147_483_647, 1000))

        expect(mock_stub_class).to receive(:new).with(
          target,
          channel_credentials,
          channel_args: {
            'grpc.keepalive_time_ms' => 1,
            'grpc.keepalive_timeout_ms' => 2_147_483_647,
            'grpc.keepalive_permit_without_calls' => 1,
            'grpc.http2.max_pings_without_data' => 0
          }
        )
        builder.build
      end

      it 'leaves prior values unchanged when supplied values are invalid, including Float::MAX' do
        builder.keepalive(interval: 1.5, timeout: 2.5, permit_without_calls: false)

        expect do
          builder.keepalive(interval: 3, timeout: 0)
        end.to raise_error(RuntimeError, /Invalid keepalive timeout/)
        expect do
          builder.keepalive(interval: Float::MAX)
        end.to raise_error(RuntimeError, /Invalid keepalive interval.*must convert/)
        expect do
          builder.keepalive(timeout: Float::MAX)
        end.to raise_error(RuntimeError, /Invalid keepalive timeout.*must convert/)

        expect(mock_stub_class).to receive(:new).with(
          target,
          channel_credentials,
          channel_args: {
            'grpc.keepalive_time_ms' => 1_500,
            'grpc.keepalive_timeout_ms' => 2_500,
            'grpc.keepalive_permit_without_calls' => 0,
            'grpc.http2.max_pings_without_data' => 0
          }
        )
        builder.build
      end

      [
        { description: 'a non-numeric value', value: '1' },
        { description: 'a complex value', value: Complex(1, 0) },
        { description: 'an infinite value', value: Float::INFINITY },
        { description: 'a NaN value', value: Float::NAN },
        { description: 'a zero duration', value: 0 },
        { description: 'a negative duration', value: -1 },
        { description: 'a duration below one millisecond', value: 0.0009 },
        { description: 'a duration above the gRPC limit', value: 2_147_483.648 }
      ].each do |tt|
        it "rejects #{tt[:description]}" do
          expect { builder.keepalive(interval: tt[:value]) }
            .to raise_error(RuntimeError, /Invalid keepalive interval/)
        end
      end

      it 'requires permit_without_calls to be true, false, or nil' do
        expect { builder.keepalive(permit_without_calls: 0) }
          .to raise_error(RuntimeError, 'Invalid keepalive permit_without_calls: must be true, false, or nil')
      end
    end

    describe '#build' do
      context 'with default configuration' do
        it 'creates service instance with default channel credentials' do
          expect(mock_stub_class).to receive(:new).with(
            target,
            channel_credentials,
            channel_args: {
              'grpc.keepalive_time_ms' => 45_000,
              'grpc.keepalive_timeout_ms' => 10_000,
              'grpc.keepalive_permit_without_calls' => 1,
              'grpc.http2.max_pings_without_data' => 0
            }
          )
          builder.build
        end
      end

      context 'with insecure configuration' do
        it 'creates service instance with insecure credentials' do
          expect(mock_stub_class).to receive(:new).with(
            target,
            :this_channel_is_insecure,
            channel_args: {
              'grpc.keepalive_time_ms' => 45_000,
              'grpc.keepalive_timeout_ms' => 10_000,
              'grpc.keepalive_permit_without_calls' => 1,
              'grpc.http2.max_pings_without_data' => 0
            }
          )
          builder.insecure.build
        end
      end

      context 'with call credentials' do
        it 'composes credentials before creating service' do
          composed_credentials = double('ComposedCredentials')
          expect(channel_credentials).to receive(:compose).with(call_credentials).and_return(composed_credentials)
          expect(mock_stub_class).to receive(:new).with(
            target,
            composed_credentials,
            channel_args: {
              'grpc.keepalive_time_ms' => 45_000,
              'grpc.keepalive_timeout_ms' => 10_000,
              'grpc.keepalive_permit_without_calls' => 1,
              'grpc.http2.max_pings_without_data' => 0
            }
          )

          builder.authenticated(call_credentials: call_credentials, channel_credentials: channel_credentials).build
        end
      end

      it 'returns the created service instance' do
        result = builder.build
        expect(result).to eq(mock_stub_instance)
      end
    end

    describe '#validate_credentials' do
      it 'raises error when using call credentials with insecure channel' do
        builder.instance_variable_set(:@channel_credentials, :this_channel_is_insecure)
        builder.instance_variable_set(:@call_credentials, call_credentials)

        expect { builder.send(:validate_credentials) }.to raise_error(
          'Invalid credential configuration: can not authenticate with insecure channel'
        )
      end

      it 'does not raise error for valid configurations' do
        builder.instance_variable_set(:@channel_credentials, channel_credentials)
        builder.instance_variable_set(:@call_credentials, call_credentials)

        expect { builder.send(:validate_credentials) }.not_to raise_error
      end

      it 'does not raise error for insecure without call credentials' do
        builder.instance_variable_set(:@channel_credentials, :this_channel_is_insecure)
        builder.instance_variable_set(:@call_credentials, nil)

        expect { builder.send(:validate_credentials) }.not_to raise_error
      end
    end
  end

  describe 'native gRPC channel configuration' do
    it 'constructs the v1beta2 channel with keepalive options without making an RPC' do
      channels = []
      captured_channel_args = nil

      allow(GRPC::Core::Channel).to receive(:new).and_wrap_original do |original, *arguments|
        captured_channel_args = arguments[1].dup
        channel = original.call(*arguments)
        channels << channel
        channel
      end

      begin
        Kessel::Inventory::V1beta2::KesselInventoryService::ClientBuilder.new('localhost:9000').insecure.build

        expect(captured_channel_args).to include(
          'grpc.keepalive_time_ms' => 45_000,
          'grpc.keepalive_timeout_ms' => 10_000,
          'grpc.keepalive_permit_without_calls' => 1,
          'grpc.http2.max_pings_without_data' => 0
        )
      ensure
        channels.each(&:close)
      end
    end
  end

  describe 'version modules' do
    describe 'V1' do
      it 'defines KesselInventoryHealthService with ClientBuilder' do
        expect(defined?(Kessel::Inventory::V1::KesselInventoryHealthService)).to eq('constant')
        expect(defined?(Kessel::Inventory::V1::KesselInventoryHealthService::ClientBuilder)).to eq('constant')
      end
    end

    describe 'V1beta1' do
      it 'defines Relationships modules with ClientBuilder' do
        expect(defined?(Kessel::Inventory::V1beta1::Relationships::KesselK8SPolicyIsPropagatedToK8SClusterService))
          .to eq('constant')
        expect(defined?(Kessel::Inventory::V1beta1::Relationships::KesselK8SPolicyIsPropagatedToK8SClusterService::ClientBuilder))
          .to eq('constant')
      end

      it 'defines Resources modules with ClientBuilder' do
        expect(defined?(Kessel::Inventory::V1beta1::Resources::KesselK8sClusterService)).to eq('constant')
        expect(defined?(Kessel::Inventory::V1beta1::Resources::KesselK8sClusterService::ClientBuilder))
          .to eq('constant')
        expect(defined?(Kessel::Inventory::V1beta1::Resources::KesselK8sPolicyService)).to eq('constant')
        expect(defined?(Kessel::Inventory::V1beta1::Resources::KesselK8sPolicyService::ClientBuilder))
          .to eq('constant')
      end
    end

    describe 'V1beta2' do
      it 'defines KesselInventoryService with ClientBuilder' do
        expect(defined?(Kessel::Inventory::V1beta2::KesselInventoryService)).to eq('constant')
        expect(defined?(Kessel::Inventory::V1beta2::KesselInventoryService::ClientBuilder)).to eq('constant')
      end
    end
  end
end

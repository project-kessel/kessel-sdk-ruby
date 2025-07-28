# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kessel::Inventory do
  describe 'module structure' do
    it 'has the expected module hierarchy' do
      expect(described_class).to be_a(Module)
      expect(Kessel::Inventory::Client).to be_a(Module)
      expect(Kessel::Inventory::Client::Config).to be_a(Module)
    end
  end

  describe Kessel::Inventory::IncompleteKesselConfiguration do
    subject(:exception_class) { described_class }

    it 'inherits from StandardError' do
      expect(exception_class).to be < StandardError
    end

    describe '#initialize' do
      context 'with an array of missing fields' do
        let(:missing_fields) { %w[target credentials] }
        let(:exception) { exception_class.new(missing_fields) }

        it 'creates an exception with properly formatted message' do
          expected_message = 'IncompleteKesselConfigurationError: Missing the following fields to build: target, ' \
                             'credentials'
          expect(exception.message).to eq(expected_message)
        end
      end

      context 'with a single missing field' do
        let(:missing_fields) { ['target'] }
        let(:exception) { exception_class.new(missing_fields) }

        it 'creates an exception with single field in message' do
          expected_message = 'IncompleteKesselConfigurationError: Missing the following fields to build: target'
          expect(exception.message).to eq(expected_message)
        end
      end

      context 'with no missing fields' do
        let(:missing_fields) { [] }
        let(:exception) { exception_class.new(missing_fields) }

        it 'creates an exception with empty field list' do
          expected_message = 'IncompleteKesselConfigurationError: Missing the following fields to build: '
          expect(exception.message).to eq(expected_message)
        end
      end
    end
  end

  describe Kessel::Inventory::Client::Config do
    let(:config_module) { described_class }

    describe 'struct definitions' do
      it 'defines KeepAlive struct with correct attributes' do
        keep_alive = config_module::KeepAlive.new(1000, 2000, true)

        expect(keep_alive.time_ms).to eq(1000)
        expect(keep_alive.timeout_ms).to eq(2000)
        expect(keep_alive.permit_without_calls).to be(true)
      end

      it 'defines Credentials struct with correct attributes' do
        credentials = config_module::Credentials.new('secure', 'root_cert', 'private_cert', 'cert_chain')

        expect(credentials.type).to eq('secure')
        expect(credentials.root_certs).to eq('root_cert')
        expect(credentials.private_certs).to eq('private_cert')
        expect(credentials.cert_chain).to eq('cert_chain')
      end

      it 'defines Auth struct with correct attributes' do
        auth = config_module::Auth.new('client_id', 'client_secret', 'https://issuer.com')

        expect(auth.client_id).to eq('client_id')
        expect(auth.client_secret).to eq('client_secret')
        expect(auth.issuer_url).to eq('https://issuer.com')
      end

      it 'defines Config struct with correct attributes' do
        target = 'localhost:9000'
        credentials = config_module::Credentials.new('secure')
        keep_alive = config_module::KeepAlive.new(1000, 2000, true)
        auth = config_module::Auth.new('id', 'secret', 'url')

        config = config_module::Config.new(target, credentials, keep_alive, auth)

        expect(config.target).to eq(target)
        expect(config.credentials).to eq(credentials)
        expect(config.keep_alive).to eq(keep_alive)
        expect(config.auth).to eq(auth)
      end
    end

    describe Kessel::Inventory::Client::Config::Defaults do
      let(:defaults_class) { described_class }

      describe '.default_keep_alive' do
        subject(:keep_alive) { defaults_class.default_keep_alive }

        it 'returns a KeepAlive struct' do
          expect(keep_alive).to be_a(Kessel::Inventory::Client::Config::KeepAlive)
        end

        it 'has the expected default values' do
          expect(keep_alive.time_ms).to eq(10_000)
          expect(keep_alive.timeout_ms).to eq(5000)
          expect(keep_alive.permit_without_calls).to be(true)
        end

        it 'returns a new instance each time' do
          first_call = defaults_class.default_keep_alive
          second_call = defaults_class.default_keep_alive

          expect(first_call).not_to be(second_call)
          expect(first_call).to eq(second_call)
        end
      end

      describe '.default_credentials' do
        subject(:credentials) { defaults_class.default_credentials }

        it 'returns a Credentials struct' do
          expect(credentials).to be_a(Kessel::Inventory::Client::Config::Credentials)
        end

        it 'has the expected default values' do
          expect(credentials.type).to eq('secure')
          expect(credentials.root_certs).to be_nil
          expect(credentials.private_certs).to be_nil
          expect(credentials.cert_chain).to be_nil
        end

        it 'returns a new instance each time' do
          first_call = defaults_class.default_credentials
          second_call = defaults_class.default_credentials

          expect(first_call).not_to be(second_call)
          expect(first_call).to eq(second_call)
        end
      end
    end
  end
end

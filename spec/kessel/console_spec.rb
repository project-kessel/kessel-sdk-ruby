# frozen_string_literal: true

require 'spec_helper'
require 'base64'
require 'json'
require 'kessel/console'

def encode_identity_header(payload)
  Base64.strict_encode64(JSON.generate(payload))
end

RSpec.describe Kessel::Console do
  describe '.principal_from_rh_identity' do
    it 'resolves User identity' do
      identity = {
        'type' => 'User',
        'org_id' => '1979710',
        'user' => { 'user_id' => '7393748', 'username' => 'foobar' }
      }
      ref = described_class.principal_from_rh_identity(identity)
      expect(ref.resource.resource_type).to eq('principal')
      expect(ref.resource.resource_id).to eq('redhat/7393748')
      expect(ref.resource.reporter.type).to eq('rbac')
    end

    it 'resolves ServiceAccount identity' do
      identity = {
        'type' => 'ServiceAccount',
        'org_id' => '456',
        'service_account' => { 'user_id' => 'sa-456', 'client_id' => 'b69eaf9e', 'username' => 'svc-b69eaf9e' }
      }
      ref = described_class.principal_from_rh_identity(identity)
      expect(ref.resource.resource_id).to eq('redhat/sa-456')
    end

    it 'uses custom domain' do
      identity = { 'type' => 'User', 'user' => { 'user_id' => '42' } }
      ref = described_class.principal_from_rh_identity(identity, domain: 'custom')
      expect(ref.resource.resource_id).to eq('custom/42')
    end

    it 'raises for unsupported identity type' do
      identity = { 'type' => 'System', 'system' => { 'cn' => 'abc' } }
      expect { described_class.principal_from_rh_identity(identity) }
        .to raise_error(ArgumentError, /Unsupported identity type/)
    end

    it 'raises for missing type field' do
      identity = { 'org_id' => '123' }
      expect { described_class.principal_from_rh_identity(identity) }
        .to raise_error(ArgumentError, /Unsupported identity type/)
    end

    it 'raises for missing user details' do
      identity = { 'type' => 'User' }
      expect { described_class.principal_from_rh_identity(identity) }
        .to raise_error(ArgumentError, /missing the 'user' field/)
    end

    it 'raises for missing service_account details' do
      identity = { 'type' => 'ServiceAccount' }
      expect { described_class.principal_from_rh_identity(identity) }
        .to raise_error(ArgumentError, /missing the 'service_account' field/)
    end

    it 'raises for user details not a Hash' do
      identity = { 'type' => 'User', 'user' => 'not-a-hash' }
      expect { described_class.principal_from_rh_identity(identity) }
        .to raise_error(ArgumentError, /missing the 'user' field/)
    end

    it 'raises for missing user_id' do
      identity = { 'type' => 'User', 'user' => { 'username' => 'foobar' } }
      expect { described_class.principal_from_rh_identity(identity) }
        .to raise_error(ArgumentError, /Unable to resolve user ID/)
    end

    it 'raises for empty user_id' do
      identity = { 'type' => 'User', 'user' => { 'user_id' => '' } }
      expect { described_class.principal_from_rh_identity(identity) }
        .to raise_error(ArgumentError, /Unable to resolve user ID/)
    end

    it 'raises for nil identity' do
      expect { described_class.principal_from_rh_identity(nil) }
        .to raise_error(ArgumentError, /identity must be a Hash/)
    end

    it 'raises for string identity' do
      expect { described_class.principal_from_rh_identity('not-a-hash') }
        .to raise_error(ArgumentError, /identity must be a Hash/)
    end

    %w[System X509 Associate].each do |identity_type|
      it "raises for unsupported type #{identity_type}" do
        identity = { 'type' => identity_type }
        expect { described_class.principal_from_rh_identity(identity) }
          .to raise_error(ArgumentError, /Unsupported identity type/)
      end
    end
  end

  describe '.principal_from_rh_identity_header' do
    it 'decodes valid User header' do
      header = encode_identity_header(
        'identity' => {
          'type' => 'User',
          'org_id' => '1979710',
          'user' => { 'user_id' => '7393748', 'username' => 'foobar' }
        }
      )
      ref = described_class.principal_from_rh_identity_header(header)
      expect(ref.resource.resource_id).to eq('redhat/7393748')
      expect(ref.resource.resource_type).to eq('principal')
    end

    it 'decodes valid ServiceAccount header' do
      header = encode_identity_header(
        'identity' => {
          'type' => 'ServiceAccount',
          'org_id' => '456',
          'service_account' => { 'user_id' => 'sa-789', 'client_id' => 'b69eaf9e' }
        }
      )
      ref = described_class.principal_from_rh_identity_header(header)
      expect(ref.resource.resource_id).to eq('redhat/sa-789')
    end

    it 'uses custom domain' do
      header = encode_identity_header(
        'identity' => { 'type' => 'User', 'user' => { 'user_id' => '1' } }
      )
      ref = described_class.principal_from_rh_identity_header(header, domain: 'acme')
      expect(ref.resource.resource_id).to eq('acme/1')
    end

    it 'raises for missing identity envelope' do
      header = encode_identity_header('type' => 'User', 'user' => { 'user_id' => '42' })
      expect { described_class.principal_from_rh_identity_header(header) }
        .to raise_error(ArgumentError, /missing the 'identity' envelope key/)
    end

    it 'raises for invalid JSON' do
      header = Base64.strict_encode64('this is not json')
      expect { described_class.principal_from_rh_identity_header(header) }
        .to raise_error(ArgumentError, /Failed to decode identity header/)
    end

    it 'raises for non-object JSON' do
      header = Base64.strict_encode64('"just a string"')
      expect { described_class.principal_from_rh_identity_header(header) }
        .to raise_error(ArgumentError, /did not decode to a JSON object/)
    end

    it 'raises for unsupported type in header' do
      header = encode_identity_header(
        'identity' => { 'type' => 'System', 'system' => { 'cn' => 'abc', 'cert_type' => 'system' } }
      )
      expect { described_class.principal_from_rh_identity_header(header) }
        .to raise_error(ArgumentError, /Unsupported identity type/)
    end

    it 'raises for missing user_id in header' do
      header = encode_identity_header(
        'identity' => {
          'type' => 'User',
          'org_id' => '1979710',
          'user' => { 'username' => 'foobar' }
        }
      )
      expect { described_class.principal_from_rh_identity_header(header) }
        .to raise_error(ArgumentError, /Unable to resolve user ID/)
    end

    it 'decodes realistic User header' do
      header = encode_identity_header(
        'identity' => {
          'account_number' => '540155',
          'org_id' => '1979710',
          'user' => {
            'username' => 'rhn-support-foobar',
            'is_internal' => true,
            'is_org_admin' => true,
            'first_name' => 'foo',
            'last_name' => 'bar',
            'is_active' => true,
            'user_id' => '7393748',
            'email' => 'example@redhat.com'
          },
          'type' => 'User'
        }
      )
      ref = described_class.principal_from_rh_identity_header(header)
      expect(ref.resource.resource_id).to eq('redhat/7393748')
      expect(ref.resource.resource_type).to eq('principal')
      expect(ref.resource.reporter.type).to eq('rbac')
    end

    it 'decodes realistic ServiceAccount header' do
      header = encode_identity_header(
        'identity' => {
          'org_id' => '456',
          'type' => 'ServiceAccount',
          'service_account' => {
            'user_id' => 'sa-b69eaf9e',
            'client_id' => 'b69eaf9e-e6a6-4f9e-805e-02987daddfbd',
            'username' => 'service-account-b69eaf9e-e6a6-4f9e-805e-02987daddfbd'
          }
        }
      )
      ref = described_class.principal_from_rh_identity_header(header)
      expect(ref.resource.resource_id).to eq('redhat/sa-b69eaf9e')
    end
  end
end

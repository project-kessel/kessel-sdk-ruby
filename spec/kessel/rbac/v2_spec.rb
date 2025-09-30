# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require 'json'

RSpec.describe Kessel::RBAC::V2 do
  include Kessel::RBAC::V2

  let(:rbac_base_endpoint) { 'http://localhost:8888' }
  let(:org_id) { '12345' }
  let(:workspace_response_body) do
    {
      'data' => [
        {
          'id' => 'workspace-123',
          'name' => 'Test Workspace',
          'type' => 'default',
          'description' => 'A test workspace'
        }
      ]
    }.to_json
  end
  let(:mock_auth) { double('auth') }
  let(:mock_response) { double('response', is_a?: true, body: workspace_response_body, code: 200) }
  let(:mock_http) { double('http') }
  let(:mock_request) { double('request') }

  describe 'module structure' do
    it 'defines the RBAC::V2 module' do
      expect(defined?(Kessel::RBAC::V2)).to eq('constant')
    end

    it 'defines WORKSPACE_ENDPOINT constant' do
      expect(Kessel::RBAC::V2::WORKSPACE_ENDPOINT).to eq('/api/rbac/v2/workspaces/')
    end

    it 'defines Workspace struct' do
      expect(defined?(Kessel::RBAC::V2::Workspace)).to eq('constant')
    end
  end

  describe 'Workspace struct' do
    it 'creates workspace with all attributes' do
      workspace = Kessel::RBAC::V2::Workspace.new(
        id: 'test-id',
        name: 'Test Name',
        type: 'default',
        description: 'Test Description'
      )

      expect(workspace.id).to eq('test-id')
      expect(workspace.name).to eq('Test Name')
      expect(workspace.type).to eq('default')
      expect(workspace.description).to eq('Test Description')
    end
  end

  describe '#fetch_default_workspace' do
    before do
      allow(self).to receive(:fetch_workspace).with(rbac_base_endpoint, org_id, 'default', auth: mock_auth)
        .and_return(Kessel::RBAC::V2::Workspace.new(id: 'default-123', name: 'Default', type: 'default', description: 'Default workspace'))
    end

    it 'calls fetch_workspace with default type' do
      expect(self).to receive(:fetch_workspace).with(rbac_base_endpoint, org_id, 'default', auth: mock_auth)

      fetch_default_workspace(rbac_base_endpoint, org_id, auth: mock_auth)
    end

    it 'returns workspace with default type' do
      result = fetch_default_workspace(rbac_base_endpoint, org_id, auth: mock_auth)

      expect(result).to be_a(Kessel::RBAC::V2::Workspace)
      expect(result.type).to eq('default')
    end
  end

  describe '#fetch_root_workspace' do
    before do
      allow(self).to receive(:fetch_workspace).with(rbac_base_endpoint, org_id, 'root', auth: mock_auth)
        .and_return(Kessel::RBAC::V2::Workspace.new(id: 'root-123', name: 'Root', type: 'root', description: 'Root workspace'))
    end

    it 'calls fetch_workspace with root type' do
      expect(self).to receive(:fetch_workspace).with(rbac_base_endpoint, org_id, 'root', auth: mock_auth)

      fetch_root_workspace(rbac_base_endpoint, org_id, auth: mock_auth)
    end

    it 'returns workspace with root type' do
      result = fetch_root_workspace(rbac_base_endpoint, org_id, auth: mock_auth)

      expect(result).to be_a(Kessel::RBAC::V2::Workspace)
      expect(result.type).to eq('root')
    end
  end

  describe '#fetch_workspace' do
    let(:mock_uri) { double('uri', host: 'localhost', port: 8888, query: nil) }

    before do
      allow_any_instance_of(Object).to receive(:URI).with('http://localhost:8888/api/rbac/v2/workspaces/').and_return(mock_uri)
      allow(mock_uri).to receive(:query=)
      allow(Net::HTTP).to receive(:start).with('localhost', 8888).and_yield(mock_http)
      allow(Net::HTTP::Get).to receive(:new).with(mock_uri).and_return(mock_request)
      allow(mock_request).to receive(:[]=)
      allow(mock_auth).to receive(:configure_request)
      allow(mock_http).to receive(:request).and_return(mock_response)
      allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    end

    context 'when request is successful' do
      it 'makes HTTP request with correct headers' do
        expect(mock_request).to receive(:[]=).with('x-rh-rbac-org-id', org_id)
        expect(mock_auth).to receive(:configure_request).with(mock_request)

        fetch_workspace(rbac_base_endpoint, org_id, 'default', auth: mock_auth)
      end

      it 'returns Workspace object with correct attributes' do
        result = fetch_workspace(rbac_base_endpoint, org_id, 'default', auth: mock_auth)

        expect(result).to be_a(Kessel::RBAC::V2::Workspace)
        expect(result.id).to eq('workspace-123')
        expect(result.name).to eq('Test Workspace')
        expect(result.type).to eq('default')
        expect(result.description).to eq('A test workspace')
      end

      it 'handles endpoint with leading slash' do
        expect_any_instance_of(Object).to receive(:URI).with('http://localhost:8888/api/rbac/v2/workspaces/')

        fetch_workspace('http://localhost:8888/', org_id, 'default', auth: mock_auth)
      end

      it 'sets query parameters correctly' do
        expect(URI).to receive(:encode_www_form).with({ type: 'default' }).and_return('type=default')
        expect(mock_uri).to receive(:query=).with('type=default')

        fetch_workspace(rbac_base_endpoint, org_id, 'default', auth: mock_auth)
      end
    end

    context 'when request fails' do
      before do
        allow(mock_response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
        allow(mock_response).to receive(:code).and_return(404)
      end

      it 'raises error with status code' do
        expect do
          fetch_workspace(rbac_base_endpoint, org_id, 'default', auth: mock_auth)
        end.to raise_error(/Error while fetching the workspace of type default.*status code 404/)
      end
    end

    context 'when response contains unexpected number of workspaces' do
      let(:multiple_workspaces_response) do
        {
          'data' => [
            { 'id' => 'ws1', 'name' => 'Workspace 1', 'type' => 'default', 'description' => 'First' },
            { 'id' => 'ws2', 'name' => 'Workspace 2', 'type' => 'default', 'description' => 'Second' }
          ]
        }.to_json
      end

      before do
        allow(mock_response).to receive(:body).and_return(multiple_workspaces_response)
      end

      it 'raises error about unexpected number of workspaces' do
        expect do
          fetch_workspace(rbac_base_endpoint, org_id, 'default', auth: mock_auth)
        end.to raise_error(/Unexpected number of default workspaces: 2/)
      end
    end

    context 'when no auth is provided' do
      it 'makes request without authentication' do
        expect(mock_request).to receive(:[]=).with('x-rh-rbac-org-id', org_id)
        expect(mock_request).not_to receive(:configure_request)

        fetch_workspace(rbac_base_endpoint, org_id, 'default', auth: nil)
      end
    end
  end
end

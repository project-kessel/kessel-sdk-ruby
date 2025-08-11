# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Kessel SDK' do
  describe 'library structure' do
    it 'defines the main Kessel module' do
      expect(defined?(Kessel)).to be_truthy
      expect(Kessel).to be_a(Module)
    end

    it 'defines the Kessel::Inventory module' do
      expect(defined?(Kessel::Inventory)).to be_truthy
      expect(Kessel::Inventory).to be_a(Module)
    end

    it 'has a version constant' do
      expect(defined?(Kessel::Inventory::VERSION)).to be_truthy
      expect(Kessel::Inventory::VERSION).to be_a(String)
      expect(Kessel::Inventory::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe 'generated protobuf classes' do
    it 'loads without errors' do
      expect { require 'kessel-sdk' }.not_to raise_error
    end

    it 'defines inventory service classes when available' do
      # These may not be available until buf generate is run
      # So we test conditionally
      expect(Kessel::Inventory::V1beta2).to be_a(Module) if defined?(Kessel::Inventory::V1beta2)
    end
  end

  describe 'inventory module structure' do
    it 'loads inventory modules' do
      expect { require 'kessel/inventory/v1' }.not_to raise_error
      expect { require 'kessel/inventory/v1beta1' }.not_to raise_error
      expect { require 'kessel/inventory/v1beta2' }.not_to raise_error
    end

    it 'defines service builder function' do
      expect(Kessel::Inventory).to respond_to(:service_builder)
    end

    it 'defines ClientBuilder class' do
      expect(defined?(Kessel::Inventory::ClientBuilder)).to eq('constant')
      expect(Kessel::Inventory::ClientBuilder).to be_a(Class)
    end

    it 'defines version-specific service modules' do
      # V1
      if defined?(Kessel::Inventory::V1)
        expect(defined?(Kessel::Inventory::V1::KesselInventoryHealthService)).to eq('constant')
      end

      # V1beta1
      if defined?(Kessel::Inventory::V1beta1)
        expect(defined?(Kessel::Inventory::V1beta1::Relationships::KesselK8SPolicyIsPropagatedToK8SClusterService))
          .to eq('constant')
        expect(defined?(Kessel::Inventory::V1beta1::Resources::KesselK8sClusterService)).to eq('constant')
        expect(defined?(Kessel::Inventory::V1beta1::Resources::KesselK8sPolicyService)).to eq('constant')
      end

      # V1beta2
      if defined?(Kessel::Inventory::V1beta2)
        expect(defined?(Kessel::Inventory::V1beta2::KesselInventoryService)).to eq('constant')
      end
    end

    it 'defines ClientBuilder for each service' do
      # V1
      if defined?(Kessel::Inventory::V1::KesselInventoryHealthService)
        expect(defined?(Kessel::Inventory::V1::KesselInventoryHealthService::ClientBuilder)).to eq('constant')
      end

      # V1beta1
      if defined?(Kessel::Inventory::V1beta1)
        expect(
          defined?(
            Kessel::Inventory::V1beta1::Relationships::KesselK8SPolicyIsPropagatedToK8SClusterService::ClientBuilder
          )
        ).to eq('constant')
        expect(defined?(Kessel::Inventory::V1beta1::Resources::KesselK8sClusterService::ClientBuilder))
          .to eq('constant')
        expect(defined?(Kessel::Inventory::V1beta1::Resources::KesselK8sPolicyService::ClientBuilder)).to eq('constant')
      end

      # V1beta2
      if defined?(Kessel::Inventory::V1beta2::KesselInventoryService)
        expect(defined?(Kessel::Inventory::V1beta2::KesselInventoryService::ClientBuilder)).to eq('constant')
      end
    end
  end
end

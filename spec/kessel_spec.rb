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
end

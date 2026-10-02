#!/usr/bin/env ruby
# frozen_string_literal: true

require 'dotenv/load'
require 'kessel-sdk'

class KeepaliveExample
  class << self
    include Kessel::Inventory::V1beta2

    def run
      client = KesselInventoryService::ClientBuilder.new(ENV.fetch('KESSEL_ENDPOINT', nil))
                                                    .keepalive(interval: 60, timeout: 10, permit_without_calls: false)
                                                    .build

      p 'Inventory client configured with custom HTTP/2 keepalive settings'
      client
    rescue StandardError => e
      p "Error: #{e}"
      raise
    end
  end
end

KeepaliveExample.run

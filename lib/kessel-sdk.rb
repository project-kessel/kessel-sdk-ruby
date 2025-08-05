# frozen_string_literal: true

require 'kessel/version'
require 'kessel/inventory'
require 'kessel/grpc'
require 'kessel/auth'

# Load version-specific modules
require 'kessel/inventory/v1'
require 'kessel/inventory/v1beta1'
require 'kessel/inventory/v1beta2'

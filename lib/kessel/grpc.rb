# frozen_string_literal: true

require 'kessel/auth'
require 'grpc'

module Kessel
  module GRPC
    def oauth2_call_credentials(auth)
      call_credentials_proc = proc do |metadata|
        token = auth.get_token
        metadata.merge('authorization' => "Bearer #{token.access_token}")
      end
      ::GRPC::Core::CallCredentials.new(call_credentials_proc)
    end
  end
end

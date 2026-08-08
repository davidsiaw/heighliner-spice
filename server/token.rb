# frozen_string_literal: true

require 'openssl'

module Spice
  # The shared secret, compared in constant time.
  class Token
    def initialize(expected)
      @expected = expected.to_s
    end

    def matches?(given)
      given = given.to_s
      given.bytesize == @expected.bytesize &&
        OpenSSL.fixed_length_secure_compare(given, @expected)
    rescue NoMethodError
      # Older openssl builds lack fixed_length_secure_compare.
      given == @expected
    end
  end
end

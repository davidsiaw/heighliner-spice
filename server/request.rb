# frozen_string_literal: true

require 'json'
require 'openssl'

module Spice
  # The client's opening header: who it is, what to run, and what kind of
  # terminal it has. Everything that can be rejected is rejected here, before
  # any process is spawned.
  class Request
    attr_reader :argv, :cwd, :env, :rows, :cols

    def self.parse(line)
      raise Denied, 'no header' if line.nil?

      new(JSON.parse(line))
    rescue JSON::ParserError => e
      raise Denied, "malformed header: #{e.message}"
    end

    def initialize(header)
      @header = header
      authorize!

      @argv = Array(header['argv']).map(&:to_s)
      @cwd = header['cwd'].to_s
      validate!

      @tty = header['tty'] ? true : false
      @rows = header['rows'].to_i
      @cols = header['cols'].to_i
      @env = build_env
    end

    # Whether the *client* is a terminal. Decides whether the pty should behave
    # like one, or stay out of the way for a program capturing output.
    def tty?
      @tty
    end

    private

    def authorize!
      return unless Config.authenticated?
      return if secure_equal?(@header['token'].to_s, Config.token)

      raise Denied, 'bad or missing token'
    end

    def secure_equal?(given, expected)
      given.bytesize == expected.bytesize &&
        OpenSSL.fixed_length_secure_compare(given, expected)
    rescue StandardError
      # OpenSSL may be unavailable in a trimmed image.
      given == expected
    end

    def validate!
      raise Denied, 'no argv' if @argv.empty?
      return if File.directory?(@cwd)

      # Nearly always means the host path is not mounted into this container.
      raise Denied, "cwd #{@cwd.inspect} does not exist on the spice server. " \
                    'The project tree must be mounted at the same absolute ' \
                    'path here as in the sandbox.'
    end

    def build_env
      client = @header['env'].is_a?(Hash) ? @header['env'] : {}
      env = Config::ENV_ALLOWLIST.each_with_object({}) do |key, out|
        value = client[key] || ENV.fetch(key, nil)
        out[key] = value.to_s if value
      end
      # heighliner uses CONTEXT_DIR to stage 1Password certificates.
      env['CONTEXT_DIR'] = @cwd
      env
    end
  end
end

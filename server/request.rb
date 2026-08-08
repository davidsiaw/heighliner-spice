# frozen_string_literal: true

require 'json'

module Spice
  # The client's opening header. Everything rejectable is rejected here, before
  # anything is spawned.
  class Request
    attr_reader :argv, :cwd, :env, :rows, :cols

    def self.parse(line)
      raise Denied, 'no header' if line.nil?

      header = JSON.parse(line)
      raise Denied, 'header is not an object' unless header.is_a?(Hash)

      new(header)
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

    # Whether the *client* is a terminal, which decides how the pty behaves.
    def tty?
      @tty
    end

    def authorize!
      return unless Config.authenticated?
      return if token.matches?(@header['token'])

      raise Denied, 'bad or missing token'
    end

    def validate!
      raise Denied, 'no argv' if @argv.empty?
      raise Denied, policy.refusal unless policy.permitted?
      return if File.directory?(@cwd)

      raise Denied, "cwd #{@cwd.inspect} does not exist on the spice server. " \
                    'The project tree must be mounted at the same absolute ' \
                    'path here as in the sandbox.'
    end

    def build_env
      client = @header['env'].is_a?(Hash) ? @header['env'] : {}
      env = Config::ENV_ALLOWLIST.each_with_object({}) do |key, out|
        value = client[key] || env_var(key)
        out[key] = value.to_s if value
      end
      env['CONTEXT_DIR'] = @cwd
      env
    end

    private

    def token
      @token ||= Token.new(Config.token)
    end

    def policy
      @policy ||= Policy.new(@argv)
    end

    def env_var(name)
      ENV.fetch(name, nil)
    end
  end
end

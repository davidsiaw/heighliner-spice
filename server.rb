# frozen_string_literal: true

# Spice server. See spice/docs/ for the design; docs/development.md for layout.

# Safe only while nothing here is referenced at load time. See
# docs/development.md#loading.
Dir.glob("#{__dir__}/wire/*.rb").each { |piece| require piece }
Dir.glob("#{__dir__}/server/*.rb").each { |piece| require piece }

# Runs heighliner on behalf of sandboxes that have no docker socket.
module Spice
  def self.run
    warn_if_open
    health = Health.server
    Thread.new { health.start }
    stop_on_signal(health)
    announce
    Listener.new.start
  end

  def self.warn_if_open
    return if Config.authenticated?

    warn 'spice: SPICE_TOKEN is empty, running unauthenticated'
  end

  def self.stop_on_signal(health)
    %w[INT TERM].each do |signal|
      trap(signal) do
        health.shutdown
        exit 0
      end
    end
  end

  def self.announce
    warn "spice: health on 0.0.0.0:#{Config.health_port}, " \
         "stream on 0.0.0.0:#{Config.stream_port}"
  end
end

Spice.run if $PROGRAM_NAME == __FILE__

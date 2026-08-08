# frozen_string_literal: true

require 'tmpdir'
require 'net/http'
require 'English'
require 'timeout'
require 'stringio'
SPICE_ROOT = File.expand_path('..', __dir__)

# A stand-in heighliner, so Command and the integration spec need neither docker
# nor a real install. Put it first on PATH for anything that spawns.
FAKE_BIN = File.expand_path('support/bin', __dir__)
FAKE_HEIGHLINER = "#{FAKE_BIN}/heighliner".freeze

# Wire first: both halves reference it when their classes are defined.
Dir.glob("#{SPICE_ROOT}/wire/*.rb").each { |piece| require piece }
Dir.glob("#{SPICE_ROOT}/server/*.rb").each { |piece| require piece }
Dir.glob("#{SPICE_ROOT}/client/spice_client/*.rb").each { |piece| require piece }
Dir.glob("#{__dir__}/support/*.rb").each { |helper| require helper }

RSpec.configure do |config|
  config.include PtyReader
  config.include FrameClient
  config.include SpiceServer
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

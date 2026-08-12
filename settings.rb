# frozen_string_literal: true

# Prints the host-side names sp and pa need, as shell assignments to eval.
#
# The names -- config dir, docker network, resolver container -- are heighliner's
# rather than spice's, so they are asked of the heighliner gem installed here
# instead of being hardcoded in a shell script on the host. See docs/settings.md.

# Loaded the same way as server.rb; see docs/development.md#loading.
Dir.glob("#{__dir__}/wire/*.rb").each { |piece| require piece }
Dir.glob("#{__dir__}/server/*.rb").each { |piece| require piece }

# Optional on purpose: without it HeighlinerSettings applies the same rule the
# gem does, so this still answers on an image where heighliner is absent.
begin
  require 'heighliner'
rescue LoadError
  nil
end

Spice::Settings.print if $PROGRAM_NAME == __FILE__

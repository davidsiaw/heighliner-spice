# frozen_string_literal: true

module Spice
  # Raised for anything the client did wrong, or asked for and may not have.
  # The message is sent back verbatim in an ERROR frame, so it is written for a
  # person (or an agent) to read and act on, not for a log.
  class Denied < StandardError; end
end

# frozen_string_literal: true

module Spice
  # Sent to the client verbatim, so the message is written to be acted on.
  class Denied < StandardError; end
end

# frozen_string_literal: true

module SpiceClient
  # Something the user has to fix before anything can work: no server
  # configured, or no server reachable. The message is printed as-is and is
  # written to tell a person (or an agent) what to do next.
  class Failure < StandardError; end
end

# frozen_string_literal: true

# The spice client: stands in for heighliner in a sandbox that has no docker.
# See spice/docs/ for the design.
module SpiceClient
  # Runs the command and returns its exit code.
  def self.run(argv)
    terminal = Terminal.new
    socket = Endpoint.from_env.connect
    request = Request.new(argv: argv, terminal: terminal)
    Session.new(socket, terminal).run(request)
  end

  # Same, but turns the failures a user can act on into an exit code and a
  # message rather than a backtrace.
  def self.main(argv, warner: $stderr)
    run(argv)
  rescue Failure => e
    warner.puts e.message
    1
  rescue Interrupt
    # Only reachable without a terminal; with one, ^C goes to the far end.
    130
  end
end

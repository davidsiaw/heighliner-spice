# frozen_string_literal: true

module Spice
  # Commands a sandbox may not run.
  #
  # Not a security boundary -- the token is that. These either affect every
  # project on the server, or are a setup decision that belongs to a person.
  # See docs/operations.md.
  class Policy
    OFF_LIMITS = {
      'init' => {
        because: 'names the environment this project is served under and allocates its ports, ' \
                 'once, for everyone who works on it',
        instead: 'Ask for `heighliner init <name>` to be run on the host, then carry straight on. ' \
                 'Everything you need afterwards is yours: `up`, `logs`, `login`, `root` and the ' \
                 '`db_*` commands.'
      },
      'deinit' => {
        because: "releases this project's environment and the ports allocated to it",
        instead: 'Nothing you need to do requires it. If the environment looks wrong, describe what ' \
                 'you saw and let the user decide.'
      },
      'shutdown' => {
        because: 'stops the shared proxy, DNS and browser containers that every project on this ' \
                 'server depends on',
        instead: 'Restarting just this application is usually what is actually needed, and ' \
                 '`heighliner up` on its own does that. Avoid `heighliner down` unless you mean to ' \
                 'discard the database. If the shared containers really do need restarting, say so ' \
                 'and ask; it takes the user seconds.'
      },
      'set' => {
        because: 'changes the domain suffix and HTTPS certificate source for every project on this ' \
                 'spice server',
        instead: 'If something looks misconfigured -- the wrong domain suffix, or missing HTTPS ' \
                 'certificates -- describe it and ask for it to be changed on the host. ' \
                 '`heighliner show http-suffix` and `heighliner show cert-source` are yours to read ' \
                 'any time.'
      }
    }.freeze

    def initialize(argv)
      @argv = argv
    end

    def subcommand
      @argv.find { |arg| !arg.start_with?('-') }
    end

    def permitted?
      !OFF_LIMITS.key?(subcommand)
    end

    def refusal
      rule = OFF_LIMITS.fetch(subcommand)
      <<~MSG.chomp
        `heighliner #{subcommand}` is one for the user rather than spice, because it #{rule[:because]}.

        #{rule[:instead]}
      MSG
    end
  end
end

# frozen_string_literal: true

module Spice
  # The host-side names sp and pa need, asked of heighliner rather than guessed.
  # See docs/settings.md.
  class Settings
    VARIABLES = {
      'SPICE_HL_CONFIG_DIR' => :config_dir,
      'SPICE_HL_NETWORK' => :network,
      'SPICE_HL_DNS' => :dns_container,
      'SPICE_HL_FLAVOR' => :flavor
    }.freeze

    def self.print(out: $stdout, source: HeighlinerSettings.new)
      new(source).print(out)
    end

    def initialize(source)
      @source = source
    end

    def print(out)
      VARIABLES.each do |name, method|
        out.puts "#{name}=#{shell_quote(@source.public_send(method))}"
      end
    end

    # Single quotes are the only quoting a POSIX shell does not interpret at all,
    # and a config value is data: it must never become shell syntax.
    def shell_quote(value)
      # The block form: in the string form, "\\'" means the post-match, not a quote.
      "'#{value.to_s.gsub("'") { "'\\''" }}'"
    end
  end
end

# frozen_string_literal: true

require 'yaml'

module Spice
  # Reads the names heighliner will actually use from heighliner's own config.
  # See docs/settings.md for why it reads rather than loads.
  class HeighlinerSettings
    DEFAULTS = {
      network: 'heighliner_net',
      dns: 'heighliner-dns'
    }.freeze

    def config_dir
      @config_dir ||= heighliner_config_dir
    end

    # Heighliner used to be called kaiser, and keeps using ~/.kaiser when that is
    # the only one present. The installed gem is asked first so this can never
    # disagree with it; older gems cannot answer, so the rule is repeated here.
    def heighliner_config_dir
      config_class = heighliner_config
      return config_class.detect_config_dir if config_class.respond_to?(:detect_config_dir)

      return "#{home}/.kaiser" if !dir?("#{home}/.heighliner") && dir?("#{home}/.kaiser")

      "#{home}/.heighliner"
    end

    def flavor
      File.basename(config_dir) == '.kaiser' ? 'kaiser' : 'heighliner'
    end

    def network
      config[:networkname] || config['networkname'] || DEFAULTS[:network]
    end

    def dns_container
      shared_name(:dns)
    end

    def shared_name(key)
      names = config[:shared_names] || config['shared_names'] || {}
      names[key] || names[key.to_s] || DEFAULTS.fetch(key)
    end

    def config
      @config ||= load_config
    end

    def load_config
      file = "#{config_dir}/config.yml"
      return {} unless file?(file)

      read_yaml(file) || {}
    rescue Psych::Exception
      # A hand-broken config is heighliner's problem to report, with its own
      # message. Answering with defaults keeps sp and pa startable enough to
      # reach it.
      {}
    end

    # The gem is present in the image but not in the test bundle, so its absence
    # is a normal answer rather than an error.
    def heighliner_config
      Object.const_get('Heighliner::Config')
    rescue NameError
      nil
    end

    def read_yaml(file)
      YAML.safe_load_file(file, permitted_classes: [Symbol])
    end

    def home
      Dir.home
    end

    def dir?(path)
      Dir.exist?(path)
    end

    def file?(path)
      File.exist?(path)
    end
  end
end

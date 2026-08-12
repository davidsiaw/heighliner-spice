# frozen_string_literal: true

RSpec.describe Spice::HeighlinerSettings do
  # Stands in for Heighliner::Config, which is installed in the image but not in
  # the test bundle. See docs/settings.md.
  def installed_heighliner_config
    stub_const('Heighliner::Config', Class.new do
      def self.detect_config_dir
        '/home/me/.somewhere'
      end
    end)
  end

  # A settings object whose whole world -- home, which directories exist, and what
  # each config file contains -- is described by the call.
  def settings(dirs: [], files: {})
    described_class.new.tap do |s|
      allow(s).to receive_messages(home: '/home/me', heighliner_config: nil)
      stub_filesystem(s, dirs, files)
    end
  end

  def stub_filesystem(subject, dirs, files)
    allow(subject).to receive(:dir?) { |path| dirs.include?(path) }
    allow(subject).to receive(:file?) { |path| files.key?(path) }
    allow(subject).to receive(:read_yaml) { |path| files.fetch(path) }
  end

  describe '#config_dir' do
    it 'asks the installed heighliner gem when it can answer' do
      installed_heighliner_config

      expect(described_class.new.config_dir).to eq('/home/me/.somewhere')
    end

    it 'answers on its own when no heighliner gem is loaded' do
      expect(described_class.new.heighliner_config).to be_nil
    end

    it 'uses ~/.heighliner when neither directory exists' do
      expect(settings.config_dir).to eq('/home/me/.heighliner')
    end

    it 'uses ~/.kaiser when only the old kaiser directory exists' do
      expect(settings(dirs: ['/home/me/.kaiser']).config_dir).to eq('/home/me/.kaiser')
    end

    it 'prefers ~/.heighliner when both exist, matching heighliner' do
      s = settings(dirs: ['/home/me/.kaiser', '/home/me/.heighliner'])

      expect(s.config_dir).to eq('/home/me/.heighliner')
    end
  end

  describe '#flavor' do
    it 'reports heighliner for a heighliner config dir' do
      expect(settings.flavor).to eq('heighliner')
    end

    it 'reports kaiser for an inherited kaiser config dir' do
      expect(settings(dirs: ['/home/me/.kaiser']).flavor).to eq('kaiser')
    end
  end

  describe '#network' do
    it 'defaults to heighliner_net when there is no config file' do
      expect(settings.network).to eq('heighliner_net')
    end

    it 'reads the network a kaiser-era config names, so pa joins the right one' do
      s = settings(
        dirs: ['/home/me/.kaiser'],
        files: { '/home/me/.kaiser/config.yml' => { networkname: 'kaiser_net' } }
      )

      expect(s.network).to eq('kaiser_net')
    end

    it 'accepts string keys, because the file is written by another program' do
      s = settings(files: { '/home/me/.heighliner/config.yml' => { 'networkname' => 'other_net' } })

      expect(s.network).to eq('other_net')
    end
  end

  describe '#dns_container' do
    it 'defaults to heighliner-dns' do
      expect(settings.dns_container).to eq('heighliner-dns')
    end

    it 'reads the resolver name a kaiser-era config names' do
      s = settings(
        dirs: ['/home/me/.kaiser'],
        files: { '/home/me/.kaiser/config.yml' => { shared_names: { dns: 'kaiser-dns' } } }
      )

      expect(s.dns_container).to eq('kaiser-dns')
    end

    it 'falls back to the default when shared_names omits it' do
      s = settings(files: { '/home/me/.heighliner/config.yml' => { shared_names: { certs: 'x' } } })

      expect(s.dns_container).to eq('heighliner-dns')
    end
  end

  describe '#load_config' do
    it 'answers with defaults on an unparseable config, so sp still starts' do
      s = described_class.new
      allow(s).to receive_messages(home: '/home/me', dir?: false, file?: true)
      allow(s).to receive(:read_yaml).and_raise(Psych::SyntaxError.new('f', 1, 1, 0, 'x', 'y'))

      expect(s.network).to eq('heighliner_net')
    end
  end
end

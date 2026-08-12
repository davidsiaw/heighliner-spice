# frozen_string_literal: true

RSpec.describe Spice::Settings do
  def source(overrides = {})
    values = {
      config_dir: '/home/me/.heighliner',
      network: 'heighliner_net',
      dns_container: 'heighliner-dns',
      flavor: 'heighliner'
    }.merge(overrides)

    instance_double(Spice::HeighlinerSettings, **values)
  end

  def printed(overrides = {})
    out = StringIO.new
    described_class.print(out: out, source: source(overrides))
    out.string
  end

  it 'prints every variable as a shell assignment' do
    expect(printed.lines.map { |line| line.split('=').first }).to eq(
      %w[SPICE_HL_CONFIG_DIR SPICE_HL_NETWORK SPICE_HL_DNS SPICE_HL_FLAVOR]
    )
  end

  it 'prints what a kaiser-era config names, so sp needs no rules of its own' do
    output = printed(
      config_dir: '/home/me/.kaiser',
      network: 'kaiser_net',
      dns_container: 'kaiser-dns',
      flavor: 'kaiser'
    )

    expect(output).to eq(<<~SHELL)
      SPICE_HL_CONFIG_DIR='/home/me/.kaiser'
      SPICE_HL_NETWORK='kaiser_net'
      SPICE_HL_DNS='kaiser-dns'
      SPICE_HL_FLAVOR='kaiser'
    SHELL
  end

  describe '#shell_quote' do
    it 'single-quotes values, so nothing in a config becomes shell syntax' do
      expect(described_class.new(source).shell_quote('a b; rm -rf /')).to eq("'a b; rm -rf /'")
    end

    it 'escapes an embedded single quote' do
      expect(described_class.new(source).shell_quote("it's")).to eq(%q('it'\''s'))
    end
  end
end

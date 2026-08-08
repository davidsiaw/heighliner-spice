# frozen_string_literal: true

RSpec.describe Spice::Token do
  describe '#matches?' do
    it 'accepts the expected secret' do
      expect(described_class.new('sekrit').matches?('sekrit')).to be(true)
    end

    it 'rejects a different secret of the same length' do
      expect(described_class.new('sekrit').matches?('sekret')).to be(false)
    end

    it 'rejects a shorter secret, which openssl refuses to compare' do
      expect(described_class.new('sekrit').matches?('no')).to be(false)
    end

    it 'rejects a longer secret' do
      expect(described_class.new('sekrit').matches?('sekrity')).to be(false)
    end

    it 'rejects nothing at all, which is what a client sending no token gives' do
      expect(described_class.new('sekrit').matches?(nil)).to be(false)
    end

    it 'rejects an empty secret' do
      expect(described_class.new('sekrit').matches?('')).to be(false)
    end

    it 'accepts a non-string, because JSON can carry other types' do
      expect(described_class.new('42').matches?(42)).to be(true)
    end

    it 'still compares correctly when openssl lacks the constant-time compare' do
      allow(OpenSSL).to receive(:fixed_length_secure_compare).and_raise(NoMethodError)

      expect(described_class.new('sekrit').matches?('sekrit')).to be(true)
    end

    it 'still rejects a wrong secret when openssl lacks the constant-time compare' do
      allow(OpenSSL).to receive(:fixed_length_secure_compare).and_raise(NoMethodError)

      expect(described_class.new('sekrit').matches?('sekret')).to be(false)
    end

    it 'compares in constant time when it can, so the secret cannot be guessed byte by byte' do
      allow(OpenSSL).to receive(:fixed_length_secure_compare).and_return(true)

      described_class.new('sekrit').matches?('sekrit')

      expect(OpenSSL).to have_received(:fixed_length_secure_compare).with('sekrit', 'sekrit')
    end
  end
end

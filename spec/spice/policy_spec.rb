# frozen_string_literal: true

RSpec.describe Spice::Policy do
  describe '#subcommand' do
    it 'is the first argument that is not a flag' do
      expect(described_class.new(%w[-v up]).subcommand).to eq('up')
    end

    it 'is the subcommand even when flags follow it' do
      expect(described_class.new(%w[up -av]).subcommand).to eq('up')
    end

    it 'is nil when there is nothing but flags' do
      expect(described_class.new(%w[-v]).subcommand).to be_nil
    end
  end

  describe '#permitted?' do
    it 'allows booting the application' do
      expect(described_class.new(['up']).permitted?).to be(true)
    end

    it 'allows stopping just this application' do
      expect(described_class.new(['down']).permitted?).to be(true)
    end

    it 'allows reading configuration, which is how an agent finds the suffix' do
      expect(described_class.new(%w[show http-suffix]).permitted?).to be(true)
    end

    it 'allows running a command in the container' do
      expect(described_class.new(['login', 'bin/rails db:migrate']).permitted?).to be(true)
    end

    it 'allows resetting the database, which is per project' do
      expect(described_class.new(['db_reset']).permitted?).to be(true)
    end

    it 'refuses init, because naming the environment is a setup decision' do
      expect(described_class.new(%w[init myapp]).permitted?).to be(false)
    end

    it 'refuses deinit, which throws away the environment and its ports' do
      expect(described_class.new(['deinit']).permitted?).to be(false)
    end

    it 'refuses shutdown, which stops containers every project depends on' do
      expect(described_class.new(['shutdown']).permitted?).to be(false)
    end

    it 'refuses set, which rewrites configuration shared by every project' do
      expect(described_class.new(%w[set http-suffix example.com]).permitted?).to be(false)
    end

    it 'refuses a listed command even behind a flag' do
      expect(described_class.new(%w[-v set cert-url https://evil]).permitted?).to be(false)
    end

    it 'refuses a listed command with no arguments of its own' do
      expect(described_class.new(['set']).permitted?).to be(false)
    end

    it 'allows a command that merely takes a listed name as an argument' do
      expect(described_class.new(%w[db_load init]).permitted?).to be(true)
    end
  end

  describe '#refusal' do
    it 'names the command that was refused' do
      expect(described_class.new(%w[set http-suffix]).refusal).to include('`heighliner set`')
    end

    it 'frames it as the user\'s job rather than a prohibition' do
      expect(described_class.new(['shutdown']).refusal).to include('one for the user')
    end

    it 'says why, so the reader does not think it is a bug' do
      expect(described_class.new(%w[set http-suffix]).refusal).to include('every project on this spice server')
    end

    it 'tells the reader exactly what to ask for when the project needs setting up' do
      expect(described_class.new(['init']).refusal).to include('heighliner init <name>')
    end

    it 'reassures that the rest of the work is still theirs' do
      expect(described_class.new(['init']).refusal).to include('carry straight on')
    end

    it 'offers the narrower command that usually solves it instead of a shutdown' do
      expect(described_class.new(['shutdown']).refusal).to include('`heighliner up` on its own')
    end

    it 'does not suggest down as a restart, which would discard the database' do
      expect(described_class.new(['shutdown']).refusal).not_to include('`heighliner down` then')
    end

    it 'points at the read-only commands that remain available' do
      expect(described_class.new(['set']).refusal).to include('heighliner show http-suffix')
    end

    it 'gives every refusal something to do next' do
      unusable = described_class::OFF_LIMITS.keys.reject do |name|
        described_class.new([name]).refusal.match?(/ask|describe|carry|say so/i)
      end

      expect(unusable).to be_empty
    end
  end
end

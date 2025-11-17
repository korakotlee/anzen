# frozen_string_literal: true

require 'spec_helper'
require 'anzen/configuration'
require 'tempfile'

RSpec.describe Anzen::Configuration do
  describe '.from_env' do
    it 'loads config from JSON environment variable' do
      config_json = { enabled_monitors: ['recursion'], monitors: { recursion: { depth_limit: 500 } } }.to_json
      allow(ENV).to receive(:[]).with('ANZEN_CONFIG').and_return(config_json)

      config = described_class.from_env
      expect(config.get('monitors.recursion.depth_limit')).to eq(500)
    end

    it 'loads config from YAML environment variable' do
      config_yaml = "enabled_monitors:\n  - recursion\nmonitors:\n  recursion:\n    depth_limit: 500"
      allow(ENV).to receive(:[]).with('ANZEN_CONFIG').and_return(config_yaml)

      config = described_class.from_env
      expect(config.get('monitors.recursion.depth_limit')).to eq(500)
    end

    it 'raises ConfigurationError if ANZEN_CONFIG not set' do
      allow(ENV).to receive(:[]).with('ANZEN_CONFIG').and_return(nil)

      expect do
        described_class.from_env
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if ANZEN_CONFIG is invalid JSON/YAML' do
      allow(ENV).to receive(:[]).with('ANZEN_CONFIG').and_return('{invalid: json')

      expect do
        described_class.from_env
      end.to raise_error
    end
  end

  describe '.from_file' do
    it 'loads config from JSON file' do
      tempfile = Tempfile.new(['.json'])
      tempfile.write({ enabled_monitors: ['recursion'], monitors: { recursion: { depth_limit: 500 } } }.to_json)
      tempfile.close

      config = described_class.from_file(tempfile.path)
      expect(config.get('monitors.recursion.depth_limit')).to eq(500)
    ensure
      tempfile.unlink
    end

    it 'loads config from YAML file' do
      tempfile = Tempfile.new(['.yaml'])
      tempfile.write("enabled_monitors:\n  - recursion\nmonitors:\n  recursion:\n    depth_limit: 500")
      tempfile.close

      config = described_class.from_file(tempfile.path)
      expect(config.get('monitors.recursion.depth_limit')).to eq(500)
    ensure
      tempfile.unlink
    end

    it 'raises ConfigurationError if file does not exist' do
      expect do
        described_class.from_file('/nonexistent/path/config.json')
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if file content is invalid' do
      tempfile = Tempfile.new(['.json'])
      tempfile.write('{invalid: json')
      tempfile.close

      expect do
        described_class.from_file(tempfile.path)
      end.to raise_error
    ensure
      tempfile.unlink
    end
  end

  describe '.programmatic' do
    it 'creates configuration from hash' do
      config_hash = { enabled_monitors: ['recursion'], monitors: { recursion: { depth_limit: 500 } } }
      config = described_class.programmatic(config_hash)

      expect(config.get('monitors.recursion.depth_limit')).to eq(500)
    end

    it 'creates empty configuration if no hash provided' do
      config = described_class.programmatic
      expect(config.to_h).to eq({})
    end
  end

  describe '#get' do
    subject(:config) { described_class.new({ monitors: { recursion: { depth_limit: 500 } } }) }

    it 'retrieves value by dot-notation path' do
      expect(config.get('monitors.recursion.depth_limit')).to eq(500)
    end

    it 'raises ConfigurationError if path does not exist' do
      expect do
        config.get('monitors.nonexistent.value')
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if trying to access property on non-hash' do
      config_with_string = described_class.new({ value: 'string' })
      expect do
        config_with_string.get('value.nested')
      end.to raise_error(Anzen::ConfigurationError)
    end
  end

  describe '#monitor_enabled?' do
    subject(:config) { described_class.new({ enabled_monitors: %w[recursion memory] }) }

    it 'returns true if monitor is enabled' do
      expect(config.monitor_enabled?('recursion')).to be(true)
    end

    it 'returns false if monitor is not enabled' do
      expect(config.monitor_enabled?('cpu')).to be(false)
    end

    it 'returns false if enabled_monitors not configured' do
      config_empty = described_class.new({})
      expect(config_empty.monitor_enabled?('recursion')).to be(false)
    end
  end

  describe '#monitor_config' do
    subject(:config) do
      described_class.new({
                            monitors: {
                              recursion: { depth_limit: 500 },
                              memory: { limit_mb: 1024 }
                            }
                          })
    end

    it 'returns configuration for specific monitor' do
      expect(config.monitor_config('recursion')).to eq({ 'depth_limit' => 500 })
    end

    it 'raises ConfigurationError if monitor config not found' do
      expect do
        config.monitor_config('nonexistent')
      end.to raise_error(Anzen::ConfigurationError)
    end
  end

  describe '#validate!' do
    it 'accepts valid configuration' do
      config_hash = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 500 }
        }
      }

      config = described_class.new(config_hash)
      expect(config.validate!).to be(true)
    end

    it 'raises ConfigurationError if enabled_monitors is not array' do
      expect do
        described_class.new({ enabled_monitors: 'recursion' })
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if monitors is not hash' do
      expect do
        described_class.new({ monitors: ['recursion'] })
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if recursion.depth_limit is not numeric' do
      expect do
        described_class.new({
                              monitors: {
                                recursion: { depth_limit: 'not_a_number' }
                              }
                            })
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if recursion.depth_limit is negative' do
      expect do
        described_class.new({
                              monitors: {
                                recursion: { depth_limit: -100 }
                              }
                            })
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if recursion.depth_limit is zero' do
      expect do
        described_class.new({
                              monitors: {
                                recursion: { depth_limit: 0 }
                              }
                            })
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if memory.limit_mb is not numeric' do
      expect do
        described_class.new({
                              monitors: {
                                memory: { limit_mb: 'not_a_number' }
                              }
                            })
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if memory.limit_mb is not positive' do
      expect do
        described_class.new({
                              monitors: {
                                memory: { limit_mb: 0 }
                              }
                            })
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if memory.limit_percent is not numeric' do
      expect do
        described_class.new({
                              monitors: {
                                memory: { limit_percent: 'not_a_number' }
                              }
                            })
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if memory.limit_percent is below 0' do
      expect do
        described_class.new({
                              monitors: {
                                memory: { limit_percent: -1 }
                              }
                            })
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'raises ConfigurationError if memory.limit_percent is above 100' do
      expect do
        described_class.new({
                              monitors: {
                                memory: { limit_percent: 150 }
                              }
                            })
      end.to raise_error(Anzen::ConfigurationError)
    end
  end

  describe '#to_h' do
    it 'returns copy of configuration hash' do
      config_hash = { enabled_monitors: ['recursion'] }
      config = described_class.new(config_hash)

      result = config.to_h
      # The config is normalized to string keys
      expect(result).to eq({ 'enabled_monitors' => ['recursion'] })
    end

    it 'returns modifications do not affect original' do
      config_hash = { enabled_monitors: ['recursion'] }
      config = described_class.new(config_hash)

      returned_hash = config.to_h
      returned_hash['enabled_monitors'] << 'memory'

      expect(config.to_h['enabled_monitors']).to eq(['recursion'])
    end
  end
end

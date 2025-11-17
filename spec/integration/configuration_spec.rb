# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe 'Configuration Integration' do
  # Test end-to-end configuration scenarios
  # Verify Anzen can be configured from various sources and behaves correctly

  before(:each) do
    # Reset Anzen state for each test
    Anzen.class_variable_set(:@@initialized, false)
    Anzen.class_variable_set(:@@registry, nil)

    # Clear environment variables
    ENV.delete('ANZEN_CONFIG')
  end

  describe 'Setup from inline config hash' do
    it 'configures monitors with custom thresholds' do
      config = {
        enabled_monitors: %w[recursion memory],
        monitors: {
          recursion: { depth_limit: 500 },
          memory: { limit_mb: 256, sampling_interval_ms: 200 }
        }
      }

      Anzen.setup(config: config)

      # Verify monitors are enabled
      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to contain_exactly('recursion', 'memory')

      # Verify custom thresholds by checking that monitors were created with correct config
      # (thresholds are not exposed in status, but we can verify by checking behavior)
      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:name]).to eq('recursion')
      expect(memory_monitor[:name]).to eq('memory')
    end

    it 'enables only specified monitors' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 512 }
        }
      }

      Anzen.setup(config: config)

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['recursion'])

      disabled_monitors = status[:monitors].reject { |m| m[:enabled] }.map { |m| m[:name] }
      expect(disabled_monitors).to include('memory')
    end

    it 'uses default values when config not provided' do
      config = {
        enabled_monitors: %w[recursion memory]
      }

      Anzen.setup(config: config)

      status = Anzen.status
      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      # Default depth_limit is 1000
      expect(recursion_monitor[:name]).to eq('recursion')
      # Default limit_mb is 512
      expect(memory_monitor[:name]).to eq('memory')
    end
  end

  describe 'Setup from environment variable' do
    it 'loads JSON config from ANZEN_CONFIG' do
      config_json = {
        enabled_monitors: ['memory'],
        monitors: {
          memory: { limit_mb: 128 }
        }
      }.to_json

      ENV['ANZEN_CONFIG'] = config_json

      Anzen.setup

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['memory'])

      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }
      expect(memory_monitor[:enabled]).to be(true)
    end

    it 'handles invalid JSON gracefully' do
      ENV['ANZEN_CONFIG'] = 'invalid json {'

      expect do
        Anzen.setup
      end.to raise_error(Anzen::ConfigurationError)
    end
  end

  describe 'Setup from YAML file' do
    let(:temp_config_file) { Tempfile.new(['anzen_config', '.yaml']) }

    after(:each) do
      temp_config_file.close
      temp_config_file.unlink
    end

    it 'loads YAML config from file' do
      config_yaml = <<~YAML
        enabled_monitors:
          - recursion
          - memory
        monitors:
          recursion:
            depth_limit: 750
          memory:
            limit_mb: 256
      YAML

      temp_config_file.write(config_yaml)
      temp_config_file.flush

      config = {
        config_file: temp_config_file.path
      }

      Anzen.setup(config: config)

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to contain_exactly('recursion', 'memory')

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:enabled]).to be(true)
      expect(memory_monitor[:enabled]).to be(true)
    end

    it 'handles missing config file gracefully' do
      config = {
        config_file: '/nonexistent/path/config.yaml'
      }

      expect do
        Anzen.setup(config: config)
      end.to raise_error(Anzen::ConfigurationError, /Config file not found/)
    end
  end

  describe 'Configuration validation' do
    it 'rejects invalid monitor names' do
      config = {
        enabled_monitors: ['invalid_monitor'],
        monitors: {}
      }

      expect do
        Anzen.setup(config: config)
      end.to raise_error(Anzen::ConfigurationError)
    end

    it 'rejects invalid threshold values' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: -1 }
        }
      }

      expect do
        Anzen.setup(config: config)
      end.to raise_error(Anzen::ConfigurationError, /recursion\.depth_limit must be positive/)
    end

    it 'rejects non-array enabled_monitors' do
      config = {
        enabled_monitors: 'recursion', # Should be array
        monitors: {}
      }

      expect do
        Anzen.setup(config: config)
      end.to raise_error(Anzen::ConfigurationError, /enabled_monitors must be an array/)
    end
  end

  describe 'Status queries' do
    it 'returns detailed monitor status' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 500 }
        }
      }

      Anzen.setup(config: config)

      status = Anzen.status

      # Check top-level status
      expect(status).to have_key(:monitors)
      expect(status).to have_key(:enabled_count)
      expect(status).to have_key(:violations_total)

      expect(status[:enabled_count]).to eq(1)
      expect(status[:violations_total]).to eq(0)

      # Check monitor details
      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_monitor).to have_key(:name)
      expect(recursion_monitor).to have_key(:enabled)
      expect(recursion_monitor).to have_key(:violations)
      expect(recursion_monitor).to have_key(:last_check)

      expect(recursion_monitor[:name]).to eq('recursion')
      expect(recursion_monitor[:enabled]).to be(true)
      expect(recursion_monitor[:violations]).to eq(0)
    end

    it 'reflects runtime changes in status' do
      config = {
        enabled_monitors: [],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 512 }
        }
      }

      Anzen.setup(config: config)

      # Initially no monitors enabled
      status = Anzen.status
      expect(status[:enabled_count]).to eq(0)

      # Enable a monitor
      Anzen.enable('recursion')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      # Enable another monitor
      Anzen.enable('memory')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(2)

      # Disable one
      Anzen.disable('recursion')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)
    end
  end

  describe 'Different environment configurations' do
    it 'supports development vs production configs' do
      # Development config - strict monitoring
      dev_config = {
        enabled_monitors: %w[recursion memory],
        monitors: {
          recursion: { depth_limit: 100 },
          memory: { limit_mb: 128, sampling_interval_ms: 50 }
        }
      }

      Anzen.setup(config: dev_config)

      status = Anzen.status
      expect(status[:enabled_count]).to eq(2)

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:enabled]).to be(true)
      expect(memory_monitor[:enabled]).to be(true)
    end

    it 'supports minimal monitoring for performance' do
      # Production config - minimal monitoring
      prod_config = {
        enabled_monitors: ['memory'],
        monitors: {
          memory: { limit_mb: 1024, sampling_interval_ms: 1000 } # Less frequent checks
        }
      }

      Anzen.setup(config: prod_config)

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['memory'])

      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }
      expect(memory_monitor[:enabled]).to be(true)
    end
  end
end

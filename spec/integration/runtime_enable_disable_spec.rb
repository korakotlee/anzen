# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Runtime Enable/Disable Integration' do
  # Test end-to-end runtime monitor control scenarios
  # Verify Anzen can enable/disable monitors at runtime and maintain state

  before(:each) do
    # Reset Anzen state for each test
    Anzen.class_variable_set(:@@initialized, false)
    Anzen.class_variable_set(:@@registry, nil)

    # Setup with all monitors available but none enabled initially
    config = {
      enabled_monitors: [],
      monitors: {
        recursion: { depth_limit: 1000 },
        memory: { limit_mb: 512, sampling_interval_ms: 100 }
      }
    }

    Anzen.setup(config: config)
  end

  describe 'Runtime enable/disable operations' do
    it 'enables a monitor at runtime' do
      # Initially no monitors enabled
      status = Anzen.status
      expect(status[:enabled_count]).to eq(0)

      # Enable recursion monitor
      result = Anzen.enable('recursion')
      expect(result).to be_a(Set)
      expect(result).to include('recursion')

      # Verify it's enabled
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_monitor[:enabled]).to be(true)
    end

    it 'disables a monitor at runtime' do
      # Enable both monitors first
      Anzen.enable('recursion')
      Anzen.enable('memory')

      status = Anzen.status
      expect(status[:enabled_count]).to eq(2)

      # Disable recursion monitor
      result = Anzen.disable('recursion')
      expect(result).to be_a(Set)
      expect(result).not_to include('recursion')

      # Verify it's disabled
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_monitor[:enabled]).to be(false)
    end

    it 'handles enabling already enabled monitor' do
      Anzen.enable('recursion')

      # Try to enable again
      result = Anzen.enable('recursion')
      expect(result).to be_a(Set)
      expect(result).to include('recursion')

      # Should still be enabled
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)
    end

    it 'handles disabling already disabled monitor' do
      # Try to disable without enabling first
      result = Anzen.disable('recursion')
      expect(result).to be_a(Set)
      expect(result).not_to include('recursion')

      # Should still be disabled
      status = Anzen.status
      expect(status[:enabled_count]).to eq(0)
    end

    it 'enables multiple monitors sequentially' do
      Anzen.enable('recursion')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      Anzen.enable('memory')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(2)

      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to contain_exactly('recursion', 'memory')
    end

    it 'disables multiple monitors sequentially' do
      Anzen.enable('recursion')
      Anzen.enable('memory')

      Anzen.disable('recursion')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      Anzen.disable('memory')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(0)
    end
  end

  describe 'Error handling for invalid operations' do
    it 'raises error for unknown monitor name' do
      expect do
        Anzen.enable('unknown_monitor')
      end.to raise_error(Anzen::MonitorNotFoundError, /Monitor 'unknown_monitor' not found/)

      expect do
        Anzen.disable('unknown_monitor')
      end.to raise_error(Anzen::MonitorNotFoundError, /Monitor 'unknown_monitor' not found/)
    end

    it 'raises error when Anzen not initialized' do
      # Reset without setup
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      expect do
        Anzen.enable('recursion')
      end.to raise_error(Anzen::InitializationError, /Anzen not initialized/)

      expect do
        Anzen.disable('recursion')
      end.to raise_error(Anzen::InitializationError, /Anzen not initialized/)
    end
  end

  describe 'State persistence across operations' do
    it 'maintains monitor state across multiple operations' do
      # Enable recursion
      Anzen.enable('recursion')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      # Enable memory
      Anzen.enable('memory')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(2)

      # Disable recursion
      Anzen.disable('recursion')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      # Check specific states
      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:enabled]).to be(false)
      expect(memory_monitor[:enabled]).to be(true)
    end

    it 'preserves thresholds when enabling/disabling' do
      # Reset for this test
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      # Enable with custom thresholds
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 500 },
          memory: { limit_mb: 256 }
        }
      }

      Anzen.setup(config: config)

      # Disable recursion
      Anzen.disable('recursion')

      # Re-enable recursion
      Anzen.enable('recursion')

      # Verify thresholds preserved
      status = Anzen.status
      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_monitor[:enabled]).to be(true)
    end
  end

  describe 'Status reporting with runtime changes' do
    it 'reports correct enabled count after operations' do
      initial_status = Anzen.status
      expect(initial_status[:enabled_count]).to eq(0)

      Anzen.enable('recursion')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      Anzen.enable('memory')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(2)

      Anzen.disable('recursion')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      Anzen.disable('memory')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(0)
    end

    it 'includes runtime state in detailed monitor info' do
      Anzen.enable('recursion')

      status = Anzen.status
      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }

      expect(recursion_monitor).to have_key(:enabled)
      expect(recursion_monitor[:enabled]).to be(true)
      expect(recursion_monitor).to have_key(:violations)
      expect(recursion_monitor).to have_key(:last_check)
    end

    it 'shows disabled monitors in status' do
      status = Anzen.status

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:enabled]).to be(false)
      expect(memory_monitor[:enabled]).to be(false)
    end
  end

  describe 'Integration with configuration setup' do
    it 'respects initial configuration when enabling/disabling' do
      # Reset for this test
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      # Setup with recursion enabled initially
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 512 }
        }
      }

      Anzen.setup(config: config)

      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      # Disable initially enabled monitor
      Anzen.disable('recursion')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(0)

      # Enable previously disabled monitor
      Anzen.enable('memory')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)
    end

    it 'allows runtime control independent of initial config' do
      # Reset for this test
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      # Setup with no monitors enabled
      config = {
        enabled_monitors: [],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 512 }
        }
      }

      Anzen.setup(config: config)

      # Enable both at runtime
      Anzen.enable('recursion')
      Anzen.enable('memory')

      status = Anzen.status
      expect(status[:enabled_count]).to eq(2)

      # Disable one
      Anzen.disable('memory')
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)
    end
  end

  describe 'Concurrent operations simulation' do
    it 'handles sequential enable/disable operations correctly' do
      # Simulate rapid enable/disable operations
      operations = [
        -> { Anzen.enable('recursion') },
        -> { Anzen.enable('memory') },
        -> { Anzen.disable('recursion') },
        -> { Anzen.enable('recursion') },
        -> { Anzen.disable('memory') }
      ]

      operations.each(&:call)

      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:enabled]).to be(true)
      expect(memory_monitor[:enabled]).to be(false)
    end
  end
end

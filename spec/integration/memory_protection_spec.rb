# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Memory Protection Integration' do
  before do
    # Reset Anzen state
    Anzen.class_variable_set(:@@initialized, false)
    Anzen.class_variable_set(:@@registry, nil)
  end

  describe 'MemoryMonitor end-to-end' do
    it 'detects memory exceeding limit' do
      config = {
        enabled_monitors: ['memory'],
        monitors: { memory: { limit_mb: 50 } }
      }
      Anzen.setup(config: config)

      # Mock high memory usage that exceeds limit
      memory_monitor = Anzen.class_variable_get(:@@registry).get('memory')
      allow(memory_monitor).to receive(:read_process_memory_mb).and_return(75.0)

      expect do
        Anzen.check!
      end.to raise_error(Anzen::MemoryLimitExceeded) do |error|
        expect(error.current_memory_mb).to eq(75.0)
        expect(error.threshold_mb).to eq(50)
      end
    end

    it 'allows memory within limit' do
      config = {
        enabled_monitors: ['memory'],
        monitors: { memory: { limit_mb: 100 } }
      }
      Anzen.setup(config: config)

      # Mock memory usage within limit
      memory_monitor = Anzen.class_variable_get(:@@registry).get('memory')
      allow(memory_monitor).to receive(:read_process_memory_mb).and_return(80.0)

      # Should not raise
      expect do
        Anzen.check!
      end.not_to raise_error
    end

    it 'respects sampling interval' do
      config = {
        enabled_monitors: ['memory'],
        monitors: { memory: { limit_mb: 50, sampling_interval_ms: 200 } }
      }
      Anzen.setup(config: config)

      memory_monitor = Anzen.class_variable_get(:@@registry).get('memory')

      # First check - should execute
      allow(memory_monitor).to receive(:read_process_memory_mb).and_return(30.0)
      Anzen.check!
      first_check_time = memory_monitor.last_check_time

      # Second check immediately - should skip due to sampling interval
      allow(memory_monitor).to receive(:read_process_memory_mb).and_return(80.0) # Would exceed limit
      Anzen.check! # Should not raise because check is skipped

      # Verify check was skipped (time not updated)
      expect(memory_monitor.last_check_time).to eq(first_check_time)
    end

    it 'handles memory reading failures gracefully' do
      config = {
        enabled_monitors: ['memory'],
        monitors: { memory: { limit_mb: 100 } }
      }
      Anzen.setup(config: config)

      # Mock memory reading failure
      memory_monitor = Anzen.class_variable_get(:@@registry).get('memory')
      allow(memory_monitor).to receive(:read_process_memory_mb).and_raise(StandardError.new('disk error'))

      expect do
        Anzen.check!
      end.to raise_error(Anzen::CheckFailedError) do |error|
        expect(error.monitor_name).to eq('memory')
        expect(error.reason).to eq('Failed to read process memory')
        expect(error.original_error).to be_a(StandardError)
      end
    end
  end

  describe 'Selective monitor enablement' do
    it 'allows both monitors when both enabled' do
      config = {
        enabled_monitors: %w[memory recursion],
        monitors: {
          memory: { limit_mb: 200 },
          recursion: {}
        }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      enabled = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled).to include('memory')
      expect(enabled).to include('recursion')
    end

    it 'allows only memory when recursion disabled' do
      config = {
        enabled_monitors: ['memory'],
        monitors: { memory: { limit_mb: 100 } }
      }
      Anzen.setup(config: config)

      # Mock memory within limit
      memory_monitor = Anzen.class_variable_get(:@@registry).get('memory')
      allow(memory_monitor).to receive(:read_process_memory_mb).and_return(80.0)

      # Should not raise (only memory monitor enabled and within limit)
      expect do
        Anzen.check!
      end.not_to raise_error
    end

    it 'allows only recursion when memory disabled' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { memory: { limit_mb: 10 } } # Very low limit
      }
      Anzen.setup(config: config)

      # Create a simple recursive function that doesn't exceed limits
      def safe_recursion(depth)
        return Anzen.check! if depth <= 0

        safe_recursion(depth - 1)
      end

      # Should not raise (only recursion monitor enabled and no recursion detected)
      expect do
        safe_recursion(5)
      end.not_to raise_error
    end
  end

  describe 'Status and monitoring' do
    it 'reports both monitors in status' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      status = Anzen.status
      monitor_names = status[:monitors].map { |m| m[:name] }

      expect(monitor_names).to include('memory')
      expect(monitor_names).to include('recursion')
    end

    it 'tracks violations for each monitor independently' do
      config = {
        enabled_monitors: ['memory'],
        monitors: { memory: { limit_mb: 50 } }
      }
      Anzen.setup(config: config)

      # Trigger a memory violation
      memory_monitor = Anzen.class_variable_get(:@@registry).get('memory')
      allow(memory_monitor).to receive(:read_process_memory_mb).and_return(75.0)

      expect do
        Anzen.check!
      end.to raise_error(Anzen::MemoryLimitExceeded)

      status = Anzen.status
      memory_status = status[:monitors].find { |m| m[:name] == 'memory' }
      recursion_status = status[:monitors].find { |m| m[:name] == 'recursion' }

      expect(memory_status[:violations]).to eq(1)
      expect(recursion_status[:violations]).to eq(0)
    end
  end

  describe 'Configuration' do
    it 'uses configured memory limits' do
      config = {
        enabled_monitors: [],
        monitors: { memory: { limit_mb: 750 } }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(memory_monitor[:thresholds][:limit_mb]).to eq(750)
    end

    it 'uses configured sampling interval' do
      config = {
        enabled_monitors: [],
        monitors: { memory: { limit_mb: 100, sampling_interval_ms: 500 } }
      }
      Anzen.setup(config: config)

      memory_monitor = Anzen.class_variable_get(:@@registry).get('memory')
      expect(memory_monitor.sampling_interval_ms).to eq(500)
    end

    it 'uses default memory limit when not configured' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      status = Anzen.status
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(memory_monitor[:thresholds][:limit_mb]).to eq(512)
    end

    it 'uses default sampling interval when not configured' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      memory_monitor = Anzen.class_variable_get(:@@registry).get('memory')
      expect(memory_monitor.sampling_interval_ms).to eq(100)
    end
  end

  describe 'Runtime enable/disable' do
    it 'can enable memory monitor at runtime' do
      config = {
        enabled_monitors: [],
        monitors: { memory: { limit_mb: 50 } }
      }
      Anzen.setup(config: config)

      # Initially disabled
      status = Anzen.status
      memory_status = status[:monitors].find { |m| m[:name] == 'memory' }
      expect(memory_status[:enabled]).to be(false)

      # Enable at runtime
      Anzen.enable('memory')

      status = Anzen.status
      memory_status = status[:monitors].find { |m| m[:name] == 'memory' }
      expect(memory_status[:enabled]).to be(true)
    end

    it 'can disable memory monitor at runtime' do
      config = {
        enabled_monitors: ['memory'],
        monitors: { memory: { limit_mb: 50 } }
      }
      Anzen.setup(config: config)

      # Initially enabled
      status = Anzen.status
      memory_status = status[:monitors].find { |m| m[:name] == 'memory' }
      expect(memory_status[:enabled]).to be(true)

      # Disable at runtime
      Anzen.disable('memory')

      status = Anzen.status
      memory_status = status[:monitors].find { |m| m[:name] == 'memory' }
      expect(memory_status[:enabled]).to be(false)
    end

    it 'enforces memory limits when enabled at runtime' do
      config = {
        enabled_monitors: [],
        monitors: { memory: { limit_mb: 50 } }
      }
      Anzen.setup(config: config)

      # Enable and immediately check
      Anzen.enable('memory')

      memory_monitor = Anzen.class_variable_get(:@@registry).get('memory')
      allow(memory_monitor).to receive(:read_process_memory_mb).and_return(75.0)

      expect do
        Anzen.check!
      end.to raise_error(Anzen::MemoryLimitExceeded)
    end
  end
end

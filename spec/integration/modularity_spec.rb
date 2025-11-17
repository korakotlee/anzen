# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Monitor Modularity' do
  # Test that monitors can be enabled/disabled independently
  # and that custom monitors work alongside built-ins

  before(:each) do
    # Reset Anzen state for each test
    Anzen.class_variable_set(:@@initialized, false)
    Anzen.class_variable_set(:@@registry, nil)
  end

  let(:custom_monitor) do
    Class.new do
      def initialize
        @enabled = false
        @check_count = 0
      end

      def name
        'test_monitor'
      end

      def enable
        @enabled = true
      end

      def disable
        @enabled = false
      end

      def enabled?
        @enabled
      end

      def check!
        return unless enabled?

        @check_count += 1
        # No violation for modularity tests
      end

      def status
        { name: name, enabled: enabled?, violations: 0, checks: @check_count }
      end

      def to_cli
        "#{name}: #{enabled? ? "enabled" : "disabled"} (checks: #{@check_count})"
      end
    end.new
  end

  describe 'Selective monitor enablement' do
    it 'enables only recursion monitor' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['recursion'])

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:enabled]).to be(true)
      expect(memory_monitor[:enabled]).to be(false)
    end

    it 'enables only memory monitor' do
      config = {
        enabled_monitors: ['memory'],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['memory'])

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:enabled]).to be(false)
      expect(memory_monitor[:enabled]).to be(true)
    end

    it 'enables both recursion and memory monitors' do
      config = {
        enabled_monitors: %w[recursion memory],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to include('recursion')
      expect(enabled_monitors).to include('memory')

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:enabled]).to be(true)
      expect(memory_monitor[:enabled]).to be(true)
    end

    it 'enables no monitors by default' do
      config = {
        enabled_monitors: [],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to be_empty

      status[:monitors].each do |monitor|
        expect(monitor[:enabled]).to be(false)
      end
    end
  end

  describe 'Runtime enable/disable' do
    it 'can enable monitor at runtime' do
      config = {
        enabled_monitors: [],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      enabled_monitors = Anzen.status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to be_empty

      Anzen.enable('recursion')
      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['recursion'])

      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_monitor[:enabled]).to be(true)
    end

    it 'can disable monitor at runtime' do
      config = {
        enabled_monitors: %w[recursion memory],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      enabled_monitors = Anzen.status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to include('recursion')
      expect(enabled_monitors).to include('memory')

      Anzen.disable('memory')
      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['recursion'])

      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }
      expect(memory_monitor[:enabled]).to be(false)
    end

    it 'can toggle monitors independently' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      # Enable memory
      Anzen.enable('memory')
      enabled_monitors = Anzen.status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to contain_exactly('recursion', 'memory')

      # Disable recursion
      Anzen.disable('recursion')
      enabled_monitors = Anzen.status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['memory'])

      # Re-enable recursion
      Anzen.enable('recursion')
      enabled_monitors = Anzen.status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to contain_exactly('recursion', 'memory')
    end
  end

  describe 'Check execution based on enablement' do
    it 'only runs checks for enabled monitors' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      # Get initial check counts
      status_before = Anzen.status
      recursion_before = status_before[:monitors].find { |m| m[:name] == 'recursion' }
      memory_before = status_before[:monitors].find { |m| m[:name] == 'memory' }

      # Run checks
      Anzen.check!

      # Get check counts after
      status_after = Anzen.status
      recursion_after = status_after[:monitors].find { |m| m[:name] == 'recursion' }
      memory_after = status_after[:monitors].find { |m| m[:name] == 'memory' }

      # Only recursion should have been checked
      expect(recursion_after[:last_check]).not_to be_nil
      expect(memory_after[:last_check]).to be_nil
    end

    it 'runs checks for all enabled monitors' do
      config = {
        enabled_monitors: %w[recursion memory],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      # Run checks
      Anzen.check!

      # Both should have been checked
      status = Anzen.status
      recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
      memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }

      expect(recursion_monitor[:last_check]).not_to be_nil
      expect(memory_monitor[:last_check]).not_to be_nil
    end

    it 'skips all checks when no monitors enabled' do
      config = {
        enabled_monitors: [],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      # Get initial timestamps
      status_before = Anzen.status
      timestamps_before = status_before[:monitors].map { |m| m[:last_check] }

      # Run checks (should do nothing)
      Anzen.check!

      # Timestamps should be unchanged
      status_after = Anzen.status
      timestamps_after = status_after[:monitors].map { |m| m[:last_check] }

      expect(timestamps_after).to eq(timestamps_before)
    end
  end

  describe 'Custom monitor independence' do
    it 'custom monitor works independently of built-ins' do
      config = {
        enabled_monitors: [], # No built-ins enabled
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      # Register custom monitor
      Anzen.register_monitor(custom_monitor)
      Anzen.enable('test_monitor')

      # Only custom monitor should be enabled
      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['test_monitor'])

      # Run checks
      initial_checks = custom_monitor.status[:checks]
      Anzen.check!
      expect(custom_monitor.status[:checks]).to eq(initial_checks + 1)
    end

    it 'custom monitor can be enabled alongside built-ins' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 1024 }
        }
      }
      Anzen.setup(config: config)

      # Register and enable custom monitor
      Anzen.register_monitor(custom_monitor)
      Anzen.enable('test_monitor')

      # Both should be enabled
      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to contain_exactly('recursion', 'test_monitor')

      # Run checks - both should be checked
      recursion_checks_before = status[:monitors].find { |m| m[:name] == 'recursion' }[:last_check]
      custom_checks_before = custom_monitor.status[:checks]

      Anzen.check!

      status_after = Anzen.status
      recursion_checks_after = status_after[:monitors].find { |m| m[:name] == 'recursion' }[:last_check]
      custom_checks_after = custom_monitor.status[:checks]

      expect(recursion_checks_after).not_to eq(recursion_checks_before)
      expect(custom_checks_after).to eq(custom_checks_before + 1)
    end

    it 'disabling built-in does not affect custom monitor' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 1000 }
        }
      }
      Anzen.setup(config: config)

      # Add custom monitor
      Anzen.register_monitor(custom_monitor)
      Anzen.enable('test_monitor')

      # Disable built-in
      Anzen.disable('recursion')

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to eq(['test_monitor'])

      # Custom monitor should still work
      initial_checks = custom_monitor.status[:checks]
      Anzen.check!
      expect(custom_monitor.status[:checks]).to eq(initial_checks + 1)
    end
  end

  describe 'Monitor combinations' do
    it 'supports all possible combinations' do
      combinations = [
        [], # None
        ['recursion'], # Only recursion
        ['memory'], # Only memory
        %w[recursion memory], # Both built-ins
        %w[recursion memory test_monitor] # All including custom
      ]

      combinations.each do |enabled_list|
        # Reset for each combination
        Anzen.class_variable_set(:@@initialized, false)
        Anzen.class_variable_set(:@@registry, nil)

        config = {
          enabled_monitors: enabled_list.reject { |m| m == 'test_monitor' }, # Remove custom from config
          monitors: {
            recursion: { depth_limit: 1000 },
            memory: { limit_mb: 1024 }
          }
        }
        Anzen.setup(config: config)

        # Add custom monitor if needed
        if enabled_list.include?('test_monitor')
          Anzen.register_monitor(custom_monitor)
          Anzen.enable('test_monitor')
        end

        # Verify correct monitors are enabled
        status = Anzen.status
        enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
        expect(enabled_monitors).to match_array(enabled_list)

        # Verify checks run for enabled monitors
        enabled_monitors = status[:monitors].select { |m| enabled_list.include?(m[:name]) }
        enabled_monitors.each do |monitor|
          expect(monitor[:enabled]).to be(true)
        end

        disabled_monitors = status[:monitors].reject { |m| enabled_list.include?(m[:name]) }
        disabled_monitors.each do |monitor|
          expect(monitor[:enabled]).to be(false)
        end
      end
    end
  end
end

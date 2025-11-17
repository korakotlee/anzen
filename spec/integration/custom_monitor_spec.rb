# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Custom Monitor Integration' do
  # Test custom monitor lifecycle and integration with Anzen

  before(:each) do
    # Reset Anzen state for each test
    Anzen.class_variable_set(:@@initialized, false)
    Anzen.class_variable_set(:@@registry, nil)
  end

  let(:file_descriptor_monitor) do
    Class.new do
      def initialize(config = {})
        @config = config
        @enabled = false
        @violation_count = 0
        @check_count = 0
      end

      def name
        'file_descriptors'
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
        # Simulate checking file descriptors
        open_fds = `lsof -p #{Process.pid} | wc -l`.strip.to_i

        return unless open_fds > (@config[:limit] || 100)

        @violation_count += 1
        raise Anzen::ViolationError.new(
          "File descriptor limit exceeded: #{open_fds} > #{@config[:limit] || 100}"
        )
      end

      def status
        {
          name: name,
          enabled: enabled?,
          violations: @violation_count,
          checks_performed: @check_count,
          limit: @config[:limit] || 100
        }
      end

      def to_cli
        "#{name}: #{enabled? ? "enabled" : "disabled"} (limit: #{@config[:limit] || 100}, violations: #{@violation_count})"
      end
    end
  end

  describe 'Custom monitor registration' do
    it 'can register a custom monitor' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new({ limit: 200 })
      expect { Anzen.register_monitor(monitor) }.not_to raise_error

      status = Anzen.status
      expect(status[:monitors].map { |m| m[:name] }).to include('file_descriptors')
    end

    it 'raises MonitorNameConflictError for duplicate names' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor1 = file_descriptor_monitor.new({ limit: 200 })
      monitor2 = file_descriptor_monitor.new({ limit: 300 })

      Anzen.register_monitor(monitor1)
      expect { Anzen.register_monitor(monitor2) }.to raise_error(Anzen::MonitorNameConflictError)
    end

    it 'raises InvalidMonitorError for monitors missing methods' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      invalid_monitor = Object.new # Missing all methods

      expect { Anzen.register_monitor(invalid_monitor) }.to raise_error(Anzen::InvalidMonitorError)
    end
  end

  describe 'Custom monitor enable/disable' do
    it 'can enable custom monitor' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new
      Anzen.register_monitor(monitor)

      expect(monitor.enabled?).to be(false)
      Anzen.enable('file_descriptors')
      expect(monitor.enabled?).to be(true)
    end

    it 'can disable custom monitor' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new
      Anzen.register_monitor(monitor)
      Anzen.enable('file_descriptors')

      expect(monitor.enabled?).to be(true)
      Anzen.disable('file_descriptors')
      expect(monitor.enabled?).to be(false)
    end

    it 'raises MonitorNotFoundError for unknown monitor' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      expect { Anzen.enable('unknown_monitor') }.to raise_error(Anzen::MonitorNotFoundError)
      expect { Anzen.disable('unknown_monitor') }.to raise_error(Anzen::MonitorNotFoundError)
    end
  end

  describe 'Custom monitor check! integration' do
    it 'calls check! on enabled custom monitor during Anzen.check!' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new({ limit: 1000 }) # High limit to avoid violation
      Anzen.register_monitor(monitor)
      Anzen.enable('file_descriptors')

      initial_checks = monitor.status[:checks_performed]
      Anzen.check!
      expect(monitor.status[:checks_performed]).to eq(initial_checks + 1)
    end

    it 'does not call check! on disabled custom monitor' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new({ limit: 1000 })
      Anzen.register_monitor(monitor)
      # Leave disabled

      initial_checks = monitor.status[:checks_performed]
      Anzen.check!
      expect(monitor.status[:checks_performed]).to eq(initial_checks)
    end

    it 'propagates violations from custom monitor' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new({ limit: 0 }) # Force violation
      Anzen.register_monitor(monitor)
      Anzen.enable('file_descriptors')

      expect { Anzen.check! }.to raise_error(Anzen::ViolationError)
    end
  end

  describe 'Custom monitor status integration' do
    it 'includes custom monitor in Anzen.status' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new({ limit: 150 })
      Anzen.register_monitor(monitor)
      Anzen.enable('file_descriptors')

      status = Anzen.status
      fd_monitor_status = status[:monitors].find { |m| m[:name] == 'file_descriptors' }

      expect(fd_monitor_status).not_to be_nil
      expect(fd_monitor_status[:enabled]).to be(true)
      expect(fd_monitor_status[:violations]).to be >= 0
    end

    it 'reflects custom monitor state changes' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new
      Anzen.register_monitor(monitor)

      status = Anzen.status
      fd_status = status[:monitors].find { |m| m[:name] == 'file_descriptors' }
      expect(fd_status[:enabled]).to be(false)

      Anzen.enable('file_descriptors')
      status = Anzen.status
      fd_status = status[:monitors].find { |m| m[:name] == 'file_descriptors' }
      expect(fd_status[:enabled]).to be(true)
    end
  end

  describe 'Custom monitor lifecycle' do
    it 'maintains violation count across multiple checks' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new({ limit: 0 }) # Always violate
      Anzen.register_monitor(monitor)
      Anzen.enable('file_descriptors')

      expect { Anzen.check! }.to raise_error(Anzen::ViolationError)
      expect(monitor.status[:violations]).to eq(1)

      expect { Anzen.check! }.to raise_error(Anzen::ViolationError)
      expect(monitor.status[:violations]).to eq(2)
    end

    it 'resets state when re-registered' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor1 = file_descriptor_monitor.new({ limit: 0 })
      Anzen.register_monitor(monitor1)
      Anzen.enable('file_descriptors')
      expect { Anzen.check! }.to raise_error(Anzen::ViolationError)

      # Re-setup and register new monitor
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      monitor2 = file_descriptor_monitor.new({ limit: 1000 })
      Anzen.register_monitor(monitor2)
      Anzen.enable('file_descriptors')

      # Should not violate now
      expect { Anzen.check! }.not_to raise_error
      expect(monitor2.status[:violations]).to eq(0)
    end
  end

  describe 'Custom monitor with built-in monitors' do
    it 'works alongside built-in monitors' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: {
          recursion: { depth_limit: 1000 }
        }
      }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new({ limit: 1000 })
      Anzen.register_monitor(monitor)
      Anzen.enable('file_descriptors')

      status = Anzen.status
      monitor_names = status[:monitors].map { |m| m[:name] }
      expect(monitor_names).to include('recursion')
      expect(monitor_names).to include('file_descriptors')
      expect(monitor_names).to include('call_stack_depth')
      expect(monitor_names).to include('memory')
    end

    it 'can be selectively enabled while built-ins are disabled' do
      config = {
        enabled_monitors: [], # No built-ins enabled
        monitors: {
          recursion: { depth_limit: 1000 }
        }
      }
      Anzen.setup(config: config)

      monitor = file_descriptor_monitor.new({ limit: 1000 })
      Anzen.register_monitor(monitor)
      Anzen.enable('file_descriptors')

      status = Anzen.status
      enabled_monitors = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_monitors).to include('file_descriptors')
      expect(enabled_monitors).not_to include('recursion')
    end
  end
end

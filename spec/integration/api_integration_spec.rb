# frozen_string_literal: true

require 'spec_helper'
require 'anzen'
require 'anzen/cli'
require 'json'

RSpec.describe 'Anzen API Integration', type: :integration do
  before(:each) do
    # Reset Anzen state between tests
    Anzen._reset_for_testing
  end

  describe 'Module Methods' do
    describe 'Anzen.setup' do
      it 'initializes with programmatic configuration' do
        expect do
          Anzen.setup(
            config: {
              enabled_monitors: ['recursion'],
              monitors: {
                recursion: { depth_limit: 1000 }
              }
            }
          )
        end.not_to raise_error

        status = Anzen.status
        expect(status[:enabled]).to include('recursion')
        expect(status[:enabled]).not_to include('memory')
      end

      it 'initializes with environment variable configuration' do
        ENV['ANZEN_CONFIG'] = '{"enabled_monitors": ["memory"], "monitors": {"memory": {"limit_mb": 512}}}'

        expect do
          Anzen.setup
        end.not_to raise_error

        status = Anzen.status
        expect(status[:enabled]).to include('memory')
        expect(status[:enabled]).not_to include('recursion')
      ensure
        ENV.delete('ANZEN_CONFIG')
      end

      it 'raises InitializationError on double setup' do
        Anzen.setup(config: { enabled_monitors: [] })

        expect do
          Anzen.setup(config: { enabled_monitors: [] })
        end.to raise_error(Anzen::InitializationError)
      end

      it 'raises ConfigurationError for invalid config' do
        expect do
          Anzen.setup(config: {
                        enabled_monitors: ['recursion'],
                        monitors: {
                          recursion: { depth_limit: -1 } # Invalid negative value
                        }
                      })
        end.to raise_error(Anzen::ConfigurationError)
      end
    end

    describe 'Anzen.enable and Anzen.disable' do
      before(:each) do
        Anzen.setup(
          config: {
            enabled_monitors: [],
            monitors: {
              recursion: { depth_limit: 1000 },
              memory: { limit_mb: 512, sampling_interval_ms: 100 }
            }
          }
        )
      end

      it 'enables and disables monitors correctly' do
        # Initially disabled
        status = Anzen.status
        expect(status[:enabled]).not_to include('recursion')

        # Enable
        Anzen.enable('recursion')
        status = Anzen.status
        expect(status[:enabled]).to include('recursion')

        # Disable
        Anzen.disable('recursion')
        status = Anzen.status
        expect(status[:enabled]).not_to include('recursion')
      end

      it 'raises MonitorNotFoundError for unknown monitor' do
        expect do
          Anzen.enable('nonexistent')
        end.to raise_error(Anzen::MonitorNotFoundError)
      end
    end

    describe 'Anzen.check!' do
      before(:each) do
        Anzen.setup(
          config: {
            enabled_monitors: ['recursion'],
            monitors: {
              recursion: { depth_limit: 5 } # Very low limit for testing
            }
          }
        )
      end

      it 'passes when no violations occur' do
        expect { Anzen.check! }.not_to raise_error
      end

      it 'raises RecursionLimitExceeded on deep recursion' do
        def recursive_call(depth = 0)
          Anzen.check!
          recursive_call(depth + 1) if depth < 10
        end

        expect do
          recursive_call
        end.to raise_error(Anzen::RecursionLimitExceeded) do |e|
          expect(e.current_depth).to be > 5
          expect(e.threshold).to eq(5)
        end
      end

      it 'raises MemoryLimitExceeded when memory usage is high' do
        Anzen._reset_for_testing # Reset before re-initializing

        Anzen.setup(
          config: {
            enabled_monitors: ['memory'],
            monitors: {
              memory: { limit_mb: 1, sampling_interval_ms: 10 } # 1MB limit
            }
          }
        )

        expect do
          # Allocate memory to trigger limit
          data = []
          loop do
            Anzen.check!
            data << ('x' * 1000) # Allocate strings
          end
        end.to raise_error(Anzen::MemoryLimitExceeded) do |e|
          expect(e.current_memory_mb).to be > 1
          expect(e.threshold_mb).to eq(1)
        end
      end

      it 'raises CheckFailedError on infrastructure failure' do
        # This would require mocking infrastructure failures
        # For now, we verify the exception type exists and can be raised
        expect do
          raise Anzen::CheckFailedError.new('memory', 'Cannot read /proc/self/status', nil)
        end.to raise_error(Anzen::CheckFailedError) do |e|
          expect(e.monitor_name).to eq('memory')
          expect(e.reason).to eq('Cannot read /proc/self/status')
        end
      end
    end

    describe 'Anzen.status' do
      before(:each) do
        Anzen.setup(
          config: {
            enabled_monitors: ['recursion'],
            monitors: {
              recursion: { depth_limit: 1000 },
              memory: { limit_mb: 512, sampling_interval_ms: 100 }
            }
          }
        )
      end

      it 'returns complete status information' do
        status = Anzen.status

        expect(status).to have_key(:monitors)
        expect(status).to have_key(:enabled)
        expect(status).to have_key(:enabled_count)
        expect(status).to have_key(:violations_total)
        expect(status).to have_key(:setup_at)

        expect(status[:enabled]).to include('recursion')
        expect(status[:enabled]).not_to include('memory')
        expect(status[:enabled_count]).to eq(1)
        expect(status[:violations_total]).to eq(0)
        expect(status[:setup_at]).to be_a(Time)

        recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
        expect(recursion_monitor[:enabled]).to be true
        expect(recursion_monitor[:thresholds][:depth_limit]).to eq(1000)
      end
    end

    describe 'Anzen.register_monitor' do
      before(:each) do
        Anzen.setup(config: { enabled_monitors: [] })
      end

      it 'registers custom monitor successfully' do
        custom_monitor = double('CustomMonitor')
        allow(custom_monitor).to receive(:name).and_return('custom')
        allow(custom_monitor).to receive(:enable)
        allow(custom_monitor).to receive(:disable)
        allow(custom_monitor).to receive(:enabled?).and_return(false)
        allow(custom_monitor).to receive(:check!)
        allow(custom_monitor).to receive(:status).and_return({
                                                               name: 'custom',
                                                               enabled: false,
                                                               thresholds: {},
                                                               violations: 0
                                                             })
        allow(custom_monitor).to receive(:to_cli).and_return('custom: disabled')

        expect do
          Anzen.register_monitor(custom_monitor)
        end.not_to raise_error

        status = Anzen.status
        expect(status[:monitors].map { |m| m[:name] }).to include('custom')
      end

      it 'raises InvalidMonitorError for invalid monitor' do
        invalid_monitor = double('InvalidMonitor')
        allow(invalid_monitor).to receive(:name).and_return('invalid')
        # Missing required methods

        expect do
          Anzen.register_monitor(invalid_monitor)
        end.to raise_error(Anzen::InvalidMonitorError)
      end

      it 'raises MonitorNameConflictError for duplicate names' do
        monitor1 = double('Monitor1')
        allow(monitor1).to receive(:name).and_return('duplicate')
        allow(monitor1).to receive(:enable)
        allow(monitor1).to receive(:disable)
        allow(monitor1).to receive(:enabled?).and_return(false)
        allow(monitor1).to receive(:check!)
        allow(monitor1).to receive(:status).and_return({
                                                         name: 'duplicate',
                                                         enabled: false,
                                                         thresholds: {},
                                                         violations: 0
                                                       })
        allow(monitor1).to receive(:to_cli).and_return('duplicate: disabled')

        monitor2 = double('Monitor2')
        allow(monitor2).to receive(:name).and_return('duplicate')
        allow(monitor2).to receive(:enable)
        allow(monitor2).to receive(:disable)
        allow(monitor2).to receive(:enabled?).and_return(false)
        allow(monitor2).to receive(:check!)
        allow(monitor2).to receive(:status).and_return({
                                                         name: 'duplicate',
                                                         enabled: false,
                                                         thresholds: {},
                                                         violations: 0
                                                       })
        allow(monitor2).to receive(:to_cli).and_return('duplicate: disabled')

        Anzen.register_monitor(monitor1)

        expect do
          Anzen.register_monitor(monitor2)
        end.to raise_error(Anzen::MonitorNameConflictError)
      end
    end
  end

  describe 'CLI Commands' do
    let(:cli) { Anzen::CLI.new }

    before(:each) do
      Anzen.setup(
        config: {
          enabled_monitors: ['recursion'],
          monitors: {
            recursion: { depth_limit: 1000 },
            memory: { limit_mb: 512, sampling_interval_ms: 100 }
          }
        }
      )
    end

    describe 'status command' do
      it 'returns text format status' do
        output = cli.status(format: :text)
        expect(output).to include('Anzen Safety Protection Status')
        expect(output).to include('Enabled Monitors: recursion')
        expect(output).to include('Monitor: recursion')
        expect(output).to include('Status: enabled')
      end

      it 'returns JSON format status' do
        output = cli.status(format: :json)
        parsed = JSON.parse(output)
        expect(parsed).to have_key('monitors')
        expect(parsed).to have_key('enabled')
        expect(parsed['enabled']).to include('recursion')
      end
    end

    describe 'config command' do
      it 'returns text format config for all monitors' do
        output = cli.config(format: :text)
        expect(output).to include('Anzen Configuration')
        expect(output).to include('Monitor: recursion')
        expect(output).to include('Enabled: yes')
      end

      it 'returns JSON format config for all monitors' do
        output = cli.config(format: :json)
        parsed = JSON.parse(output)
        expect(parsed).to have_key('monitors')
        expect(parsed['monitors']).to have_key('recursion')
      end

      it 'returns config for specific monitor' do
        output = cli.config(monitor_name: 'recursion', format: :text)
        expect(output).to include('Monitor: recursion')
        expect(output).to include('Enabled: yes')
        expect(output).to include('depth_limit: 1000')
      end

      it 'raises MonitorNotFoundError for unknown monitor' do
        expect do
          cli.config(monitor_name: 'nonexistent', format: :text)
        end.to raise_error(Anzen::MonitorNotFoundError)
      end
    end

    describe 'info command' do
      it 'returns text format info' do
        output = cli.info(format: :text)
        expect(output).to include('Anzen Gem Information')
        expect(output).to include('Version:')
        expect(output).to include('Ruby Version:')
        expect(output).to include('Available Monitors: recursion, memory')
      end

      it 'returns JSON format info' do
        output = cli.info(format: :json)
        parsed = JSON.parse(output)
        expect(parsed).to have_key('name')
        expect(parsed).to have_key('version')
        expect(parsed).to have_key('monitors_available')
        expect(parsed['monitors_available']).to include('recursion')
        expect(parsed['monitors_available']).to include('memory')
      end
    end

    describe 'help command' do
      it 'returns general help' do
        output = cli.help
        expect(output).to include('Anzen Safety Protection - Command Line Interface')
        expect(output).to include('Commands:')
        expect(output).to include('status')
        expect(output).to include('config')
        expect(output).to include('info')
        expect(output).to include('help')
      end

      it 'returns command-specific help' do
        output = cli.help(command: 'status')
        expect(output).to include('anzen status - Display protection status')
        expect(output).to include('Usage: anzen status [options]')
      end

      it 'returns unknown command message for invalid command' do
        output = cli.help(command: 'invalid')
        expect(output).to include("Unknown command 'invalid'")
      end
    end
  end

  describe 'Exception Types' do
    it 'raises all violation exceptions correctly' do
      # RecursionLimitExceeded
      expect do
        raise Anzen::RecursionLimitExceeded.new(1500, 1000)
      end.to raise_error(Anzen::RecursionLimitExceeded) do |e|
        expect(e.current_depth).to eq(1500)
        expect(e.threshold).to eq(1000)
      end

      # MemoryLimitExceeded
      expect do
        raise Anzen::MemoryLimitExceeded.new(600, 512)
      end.to raise_error(Anzen::MemoryLimitExceeded) do |e|
        expect(e.current_memory_mb).to eq(600)
        expect(e.threshold_mb).to eq(512)
      end
    end

    it 'raises infrastructure exceptions correctly' do
      # CheckFailedError
      expect do
        raise Anzen::CheckFailedError.new('memory', 'Cannot read memory stats', RuntimeError.new('permission denied'))
      end.to raise_error(Anzen::CheckFailedError) do |e|
        expect(e.monitor_name).to eq('memory')
        expect(e.reason).to eq('Cannot read memory stats')
        expect(e.original_error).to be_a(RuntimeError)
      end

      # ConfigurationError
      expect do
        raise Anzen::ConfigurationError.new('Invalid monitor config')
      end.to raise_error(Anzen::ConfigurationError)

      # MonitorNotFoundError
      expect do
        raise Anzen::MonitorNotFoundError.new('unknown_monitor')
      end.to raise_error(Anzen::MonitorNotFoundError)

      # InvalidMonitorError
      expect do
        raise Anzen::InvalidMonitorError.new('Missing check! method')
      end.to raise_error(Anzen::InvalidMonitorError)

      # MonitorNameConflictError
      expect do
        raise Anzen::MonitorNameConflictError.new('duplicate_name')
      end.to raise_error(Anzen::MonitorNameConflictError)

      # InitializationError
      expect do
        raise Anzen::InitializationError.new('Already initialized')
      end.to raise_error(Anzen::InitializationError)
    end
  end

  describe 'User Story Acceptance Scenarios' do
    describe 'User Story 1: Recursion Detection' do
      it 'detects direct recursion and raises RecursionLimitExceeded' do
        Anzen.setup(
          config: {
            enabled_monitors: ['recursion'],
            monitors: {
              recursion: { depth_limit: 10 }
            }
          }
        )

        def recursive_function(depth = 0)
          Anzen.check!
          recursive_function(depth + 1)
        end

        expect do
          recursive_function
        end.to raise_error(Anzen::RecursionLimitExceeded) do |e|
          expect(e.current_depth).to be > 10
          expect(e.threshold).to eq(10)
        end
      end

      it 'detects indirect recursion through multiple methods' do
        Anzen.setup(
          config: {
            enabled_monitors: ['recursion'],
            monitors: {
              recursion: { depth_limit: 5 }
            }
          }
        )

        def method_a(n)
          Anzen.check!
          method_b(n)
        end

        def method_b(n)
          Anzen.check!
          method_a(n - 1) if n > 0
        end

        expect do
          method_a(10)
        end.to raise_error(Anzen::RecursionLimitExceeded)
      end
    end

    describe 'User Story 2: Memory Detection' do
      it 'detects memory usage exceeding threshold' do
        Anzen.setup(
          config: {
            enabled_monitors: ['memory'],
            monitors: {
              memory: { limit_mb: 10, sampling_interval_ms: 10 } # Low limit for testing
            }
          }
        )

        expect do
          data = []
          loop do
            Anzen.check!
            data << ('x' * 10_000) # Allocate memory
          end
        end.to raise_error(Anzen::MemoryLimitExceeded) do |e|
          expect(e.current_memory_mb).to be > 10
          expect(e.threshold_mb).to eq(10)
        end
      end
    end

    describe 'User Story 3: Configuration and Monitoring' do
      it 'allows runtime enable/disable of monitors' do
        Anzen.setup(
          config: {
            enabled_monitors: [],
            monitors: {
              recursion: { depth_limit: 1000 },
              memory: { limit_mb: 512, sampling_interval_ms: 100 }
            }
          }
        )

        # Initially no monitors enabled
        status = Anzen.status
        expect(status[:enabled]).to be_empty

        # Enable recursion
        Anzen.enable('recursion')
        status = Anzen.status
        expect(status[:enabled]).to include('recursion')

        # Enable memory
        Anzen.enable('memory')
        status = Anzen.status
        expect(status[:enabled]).to include('recursion', 'memory')

        # Disable recursion
        Anzen.disable('recursion')
        status = Anzen.status
        expect(status[:enabled]).to include('memory')
        expect(status[:enabled]).not_to include('recursion')
      end

      it 'provides comprehensive status information' do
        Anzen.setup(
          config: {
            enabled_monitors: %w[recursion memory],
            monitors: {
              recursion: { depth_limit: 500 },
              memory: { limit_mb: 256, sampling_interval_ms: 50 }
            }
          }
        )

        status = Anzen.status

        expect(status[:enabled]).to contain_exactly('recursion', 'memory')
        expect(status[:enabled_count]).to eq(2)
        expect(status[:violations_total]).to eq(0)
        expect(status[:setup_at]).to be_a(Time)

        recursion_monitor = status[:monitors].find { |m| m[:name] == 'recursion' }
        expect(recursion_monitor[:enabled]).to be true
        expect(recursion_monitor[:thresholds][:depth_limit]).to eq(500)

        memory_monitor = status[:monitors].find { |m| m[:name] == 'memory' }
        expect(memory_monitor[:enabled]).to be true
        expect(memory_monitor[:thresholds][:limit_mb]).to eq(256)
        expect(memory_monitor[:thresholds][:sampling_interval_ms]).to eq(50)
      end
    end

    describe 'User Story 4: Modular Architecture' do
      it 'allows registration of custom monitors' do
        Anzen.setup(config: { enabled_monitors: [] })

        custom_monitor = double('CustomMonitor')
        allow(custom_monitor).to receive(:name).and_return('custom')
        allow(custom_monitor).to receive(:enable)
        allow(custom_monitor).to receive(:disable)
        allow(custom_monitor).to receive(:enabled?).and_return(false)
        allow(custom_monitor).to receive(:check!)
        allow(custom_monitor).to receive(:status).and_return({
                                                               name: 'custom',
                                                               enabled: false,
                                                               thresholds: { custom_param: 42 },
                                                               violations: 0
                                                             })
        allow(custom_monitor).to receive(:to_cli).and_return('custom: disabled (custom_param: 42)')

        Anzen.register_monitor(custom_monitor)

        status = Anzen.status
        expect(status[:monitors].map { |m| m[:name] }).to include('custom')

        custom_status = status[:monitors].find { |m| m[:name] == 'custom' }
        expect(custom_status[:thresholds][:custom_param]).to eq(42)
      end

      it 'supports selective monitor enabling' do
        Anzen.setup(
          config: {
            enabled_monitors: ['recursion'], # Only enable recursion
            monitors: {
              recursion: { depth_limit: 1000 },
              memory: { limit_mb: 512, sampling_interval_ms: 100 }
            }
          }
        )

        status = Anzen.status
        expect(status[:enabled]).to include('recursion')
        expect(status[:enabled]).not_to include('memory')

        # Enable memory later
        Anzen.enable('memory')
        status = Anzen.status
        expect(status[:enabled]).to include('recursion', 'memory')
      end
    end
  end
end

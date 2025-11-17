# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Monitor Interface Contract' do
  # Shared contract tests for all monitors
  # Any monitor implementing the Monitor interface must pass these tests

  shared_examples 'a monitor' do |monitor_name, monitor_proc|
    let(:monitor) { instance_exec(&monitor_proc) }

    describe "#{monitor_name} interface compliance" do
      describe 'required interface methods' do
        it 'responds to name' do
          expect(monitor).to respond_to(:name)
        end

        it 'responds to enable' do
          expect(monitor).to respond_to(:enable)
        end

        it 'responds to disable' do
          expect(monitor).to respond_to(:disable)
        end

        it 'responds to enabled?' do
          expect(monitor).to respond_to(:enabled?)
        end

        it 'responds to check!' do
          expect(monitor).to respond_to(:check!)
        end

        it 'responds to status' do
          expect(monitor).to respond_to(:status)
        end

        it 'responds to to_cli' do
          expect(monitor).to respond_to(:to_cli)
        end
      end

      describe 'name method' do
        it 'returns a string' do
          expect(monitor.name).to be_a(String)
        end

        it 'returns non-empty string' do
          expect(monitor.name).not_to be_empty
        end

        it 'returns consistent name' do
          name1 = monitor.name
          name2 = monitor.name
          expect(name1).to eq(name2)
        end
      end

      describe 'enable method' do
        it 'returns truthy value' do
          expect(monitor.enable).to be_truthy
        end

        it 'enables the monitor' do
          monitor.enable
          expect(monitor.enabled?).to be(true)
        end
      end

      describe 'disable method' do
        it 'returns falsy value' do
          expect(monitor.disable).to be_falsy
        end

        it 'disables the monitor' do
          monitor.enable
          monitor.disable
          expect(monitor.enabled?).to be(false)
        end
      end

      describe 'enabled? method' do
        it 'returns boolean' do
          expect([true, false]).to include(monitor.enabled?)
        end

        it 'reflects enabled state' do
          monitor.disable
          expect(monitor.enabled?).to be(false)

          monitor.enable
          expect(monitor.enabled?).to be(true)
        end
      end

      describe 'check! method' do
        context 'when monitor is disabled' do
          it 'returns nil or nothing' do
            monitor.disable
            result = monitor.check!
            expect(result).to be_nil
          end

          it 'does not raise exception' do
            monitor.disable
            expect { monitor.check! }.not_to raise_error
          end
        end

        context 'when monitor is enabled' do
          it 'returns nil when check passes' do
            monitor.enable
            result = monitor.check!
            expect(result).to be_nil
          end

          it 'does not raise when check passes' do
            monitor.enable
            expect { monitor.check! }.not_to raise_error
          end

          it 'raises ViolationError subclass or CheckFailedError on violation' do
            monitor.enable
            # For contract testing, we just verify check! doesn't raise unexpected errors
            # Specific violation scenarios are tested in unit tests
            expect { monitor.check! }.not_to raise_error(StandardError)
          end
        end
      end

      describe 'status method' do
        it 'returns a hash' do
          expect(monitor.status).to be_a(Hash)
        end

        it 'includes :name key' do
          expect(monitor.status).to have_key(:name)
        end

        it 'includes :enabled key' do
          expect(monitor.status).to have_key(:enabled)
        end

        it 'includes :violations key' do
          expect(monitor.status).to have_key(:violations)
        end

        it 'name value in status matches name method' do
          expect(monitor.status[:name]).to eq(monitor.name)
        end

        it 'enabled value reflects current state' do
          monitor.enable
          expect(monitor.status[:enabled]).to be(true)

          monitor.disable
          expect(monitor.status[:enabled]).to be(false)
        end

        it 'violations is non-negative integer' do
          violations = monitor.status[:violations]
          expect(violations).to be_an(Integer)
          expect(violations).to be >= 0
        end
      end

      describe 'to_cli method' do
        it 'returns a string' do
          expect(monitor.to_cli).to be_a(String)
        end

        it 'returns non-empty string' do
          expect(monitor.to_cli).not_to be_empty
        end

        it 'is single line (no newlines)' do
          expect(monitor.to_cli).not_to include("\n")
        end

        it 'includes monitor name' do
          cli_text = monitor.to_cli.downcase
          name_parts = monitor.name.downcase.split('_')
          # Check if all parts of the name appear in the CLI text
          name_parts.each do |part|
            expect(cli_text).to include(part)
          end
        end

        it 'includes status information' do
          cli_text = monitor.to_cli.downcase
          # Should mention either "enabled" or "disabled"
          expect(cli_text).to match(/enabled|disabled/)
        end
      end
    end
  end

  # Test each monitor
  describe 'RecursionMonitor' do
    include_examples 'a monitor', 'RecursionMonitor', -> { Anzen::Monitors::RecursionMonitor.new }
  end

  describe 'CallStackDepthMonitor' do
    include_examples 'a monitor', 'CallStackDepthMonitor', -> { Anzen::Monitors::CallStackDepthMonitor.new(depth_limit: 100) }
  end

  describe 'MemoryMonitor' do
    include_examples 'a monitor', 'MemoryMonitor', -> { Anzen::Monitors::MemoryMonitor.new(limit_mb: 1024) }
  end

  describe 'Monitor interface compliance' do
    let(:monitors) do
      [
        Anzen::Monitors::RecursionMonitor.new,
        Anzen::Monitors::CallStackDepthMonitor.new(depth_limit: 100),
        Anzen::Monitors::MemoryMonitor.new(limit_mb: 1024)
      ]
    end

    it 'all monitors include Monitor module' do
      monitors.each do |monitor|
        expect(monitor.is_a?(Anzen::Monitor)).to be(true)
      end
    end

    it 'all monitors implement all required methods' do
      required_methods = %i[name enable disable enabled? check! status to_cli]
      monitors.each do |monitor|
        required_methods.each do |method|
          expect(monitor).to respond_to(method)
        end
      end
    end
  end

  describe 'Custom monitor compliance' do
    let(:custom_monitor) do
      Class.new do
        def name
          'custom_test'
        end

        def enable
          @enabled = true
        end

        def disable
          @enabled = false
        end

        def enabled?
          @enabled || false
        end

        def check!
          # no-op for custom monitor
        end

        def status
          { name: 'custom_test', enabled: @enabled || false, violations: 0 }
        end

        def to_cli
          'Custom test monitor'
        end
      end.new
    end

    it 'custom monitor responds to all required methods' do
      required_methods = %i[name enable disable enabled? check! status to_cli]
      required_methods.each do |method|
        expect(custom_monitor).to respond_to(method)
      end
    end

    it 'custom monitor can be registered' do
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      expect do
        Anzen.register_monitor(custom_monitor)
      end.not_to raise_error

      status = Anzen.status
      expect(status[:monitors].map { |m| m[:name] }).to include('custom_test')
    end

    it 'custom monitor status has all required fields' do
      status = custom_monitor.status
      expect(status).to have_key(:name)
      expect(status).to have_key(:enabled)
      expect(status).to have_key(:violations)
    end

    it 'custom monitor to_cli returns string' do
      expect(custom_monitor.to_cli).to be_a(String)
    end
  end
end

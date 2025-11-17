# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Monitor Interface Contract' do
  # Shared contract tests for all monitors
  # Any monitor implementing the Monitor interface must pass these tests

  let(:recursion_monitor) { Anzen::Monitors::RecursionMonitor.new }

  describe 'required interface methods' do
    it 'RecursionMonitor responds to name' do
      expect(recursion_monitor).to respond_to(:name)
    end

    it 'RecursionMonitor responds to enable' do
      expect(recursion_monitor).to respond_to(:enable)
    end

    it 'RecursionMonitor responds to disable' do
      expect(recursion_monitor).to respond_to(:disable)
    end

    it 'RecursionMonitor responds to enabled?' do
      expect(recursion_monitor).to respond_to(:enabled?)
    end

    it 'RecursionMonitor responds to check!' do
      expect(recursion_monitor).to respond_to(:check!)
    end

    it 'RecursionMonitor responds to status' do
      expect(recursion_monitor).to respond_to(:status)
    end

    it 'RecursionMonitor responds to to_cli' do
      expect(recursion_monitor).to respond_to(:to_cli)
    end
  end

  describe 'name method' do
    it 'returns a string' do
      expect(recursion_monitor.name).to be_a(String)
    end

    it 'returns non-empty string' do
      expect(recursion_monitor.name).not_to be_empty
    end

    it 'returns consistent name' do
      name1 = recursion_monitor.name
      name2 = recursion_monitor.name
      expect(name1).to eq(name2)
    end
  end

  describe 'enable method' do
    it 'returns truthy value' do
      expect(recursion_monitor.enable).to be_truthy
    end

    it 'enables the monitor' do
      recursion_monitor.enable
      expect(recursion_monitor.enabled?).to be(true)
    end
  end

  describe 'disable method' do
    it 'returns falsy value' do
      expect(recursion_monitor.disable).to be_falsy
    end

    it 'disables the monitor' do
      recursion_monitor.enable
      recursion_monitor.disable
      expect(recursion_monitor.enabled?).to be(false)
    end
  end

  describe 'enabled? method' do
    it 'returns boolean' do
      expect([true, false]).to include(recursion_monitor.enabled?)
    end

    it 'reflects enabled state' do
      recursion_monitor.disable
      expect(recursion_monitor.enabled?).to be(false)

      recursion_monitor.enable
      expect(recursion_monitor.enabled?).to be(true)
    end
  end

  describe 'check! method' do
    context 'when monitor is disabled' do
      it 'returns nil or nothing' do
        recursion_monitor.disable
        result = recursion_monitor.check!
        expect(result).to be_nil
      end

      it 'does not raise exception' do
        recursion_monitor.disable
        expect { recursion_monitor.check! }.not_to raise_error
      end
    end

    context 'when monitor is enabled' do
      it 'returns nil when check passes' do
        recursion_monitor.enable
        result = recursion_monitor.check!
        expect(result).to be_nil
      end

      it 'does not raise when check passes' do
        recursion_monitor.enable
        expect { recursion_monitor.check! }.not_to raise_error
      end

      it 'raises ViolationError subclass on violation' do
        # RecursionMonitor raises RecursionLimitExceeded on violation
        recursion_monitor.enable
        recursion_monitor.instance_variable_set(:@depth_limit, 5)

        def deep_call(depth, &block)
          return yield if depth <= 0

          deep_call(depth - 1, &block)
        end

        expect do
          deep_call(20) { recursion_monitor.check! }
        end.to raise_error(Anzen::ViolationError)
      end

      it 'raises specific ViolationError subclass' do
        recursion_monitor.enable
        recursion_monitor.instance_variable_set(:@depth_limit, 5)

        def another_deep_call(depth, &block)
          return yield if depth <= 0

          another_deep_call(depth - 1, &block)
        end

        expect do
          another_deep_call(20) { recursion_monitor.check! }
        end.to raise_error(Anzen::RecursionLimitExceeded)
      end
    end
  end

  describe 'status method' do
    it 'returns a hash' do
      expect(recursion_monitor.status).to be_a(Hash)
    end

    it 'includes :name key' do
      expect(recursion_monitor.status).to have_key(:name)
    end

    it 'includes :enabled key' do
      expect(recursion_monitor.status).to have_key(:enabled)
    end

    it 'includes :violations key' do
      expect(recursion_monitor.status).to have_key(:violations)
    end

    it 'name value in status matches name method' do
      expect(recursion_monitor.status[:name]).to eq(recursion_monitor.name)
    end

    it 'enabled value reflects current state' do
      recursion_monitor.enable
      expect(recursion_monitor.status[:enabled]).to be(true)

      recursion_monitor.disable
      expect(recursion_monitor.status[:enabled]).to be(false)
    end

    it 'violations is non-negative integer' do
      violations = recursion_monitor.status[:violations]
      expect(violations).to be_an(Integer)
      expect(violations).to be >= 0
    end
  end

  describe 'to_cli method' do
    it 'returns a string' do
      expect(recursion_monitor.to_cli).to be_a(String)
    end

    it 'returns non-empty string' do
      expect(recursion_monitor.to_cli).not_to be_empty
    end

    it 'is single line (no newlines)' do
      expect(recursion_monitor.to_cli).not_to include("\n")
    end

    it 'includes monitor name' do
      name = recursion_monitor.name
      expect(recursion_monitor.to_cli.downcase).to include(name.downcase)
    end

    it 'includes status information' do
      cli_text = recursion_monitor.to_cli.downcase
      # Should mention either "enabled" or "disabled"
      expect(cli_text).to match(/enabled|disabled/)
    end
  end

  describe 'Monitor interface compliance' do
    it 'RecursionMonitor includes Monitor module' do
      expect(recursion_monitor.is_a?(Anzen::Monitor)).to be(true)
    end

    it 'all required methods are implemented' do
      required_methods = %i[name enable disable enabled? check! status to_cli]
      required_methods.each do |method|
        expect(recursion_monitor).to respond_to(method)
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

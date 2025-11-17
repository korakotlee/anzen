# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Anzen do
  # Reset Anzen state before each test
  before do
    # Use reflection to reset class variables
    Anzen.class_variable_set(:@@initialized, false)
    Anzen.class_variable_set(:@@registry, nil)
  end

  describe '.setup' do
    it 'initializes Anzen with configuration' do
      config = {
        enabled_monitors: ['recursion'],
        monitors: { recursion: { depth_limit: 500 } }
      }

      expect { Anzen.setup(config: config) }.not_to raise_error
    end

    it 'raises InitializationError if called twice' do
      config = { enabled_monitors: ['recursion'] }

      Anzen.setup(config: config)

      expect do
        Anzen.setup(config: config)
      end.to raise_error(Anzen::InitializationError)
    end

    it 'registers recursion monitor' do
      config = { enabled_monitors: ['recursion'] }
      Anzen.setup(config: config)

      status = Anzen.status
      expect(status[:monitors].map { |m| m[:name] }).to include('recursion')
    end

    it 'enables specified monitors' do
      config = { enabled_monitors: ['recursion'] }
      Anzen.setup(config: config)

      status = Anzen.status
      enabled_names = status[:monitors].select { |m| m[:enabled] }.map { |m| m[:name] }
      expect(enabled_names).to include('recursion')
    end

    it 'uses default depth_limit if not configured' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      status = Anzen.status
      recursion_status = status[:monitors].find { |m| m[:name] == 'recursion' }
      # Default is 1000
      expect(recursion_status[:thresholds][:depth_limit]).to eq(1000)
    end

    it 'uses configured depth_limit' do
      config = {
        enabled_monitors: [],
        monitors: { recursion: { depth_limit: 500 } }
      }
      Anzen.setup(config: config)

      status = Anzen.status
      recursion_status = status[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_status[:thresholds][:depth_limit]).to eq(500)
    end
  end

  describe '.enable' do
    before do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)
    end

    it 'enables a monitor' do
      Anzen.enable('recursion')

      status = Anzen.status
      recursion_status = status[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_status[:enabled]).to be(true)
    end

    it 'raises InitializationError if Anzen not initialized' do
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      expect do
        Anzen.enable('recursion')
      end.to raise_error(Anzen::InitializationError)
    end

    it 'raises MonitorNotFoundError if monitor not found' do
      expect do
        Anzen.enable('nonexistent')
      end.to raise_error(Anzen::MonitorNotFoundError)
    end
  end

  describe '.disable' do
    before do
      config = { enabled_monitors: ['recursion'] }
      Anzen.setup(config: config)
    end

    it 'disables a monitor' do
      Anzen.disable('recursion')

      status = Anzen.status
      recursion_status = status[:monitors].find { |m| m[:name] == 'recursion' }
      expect(recursion_status[:enabled]).to be(false)
    end

    it 'raises InitializationError if Anzen not initialized' do
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      expect do
        Anzen.disable('recursion')
      end.to raise_error(Anzen::InitializationError)
    end

    it 'raises MonitorNotFoundError if monitor not found' do
      expect do
        Anzen.disable('nonexistent')
      end.to raise_error(Anzen::MonitorNotFoundError)
    end
  end

  describe '.check!' do
    it 'raises InitializationError if Anzen not initialized' do
      expect do
        Anzen.check!
      end.to raise_error(Anzen::InitializationError)
    end

    it 'returns nil when no checks needed' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      expect(Anzen.check!).to be_nil
    end

    it 'raises violation from enabled monitor' do
      config = { enabled_monitors: ['recursion'], monitors: { recursion: { depth_limit: 20 } } }
      Anzen.setup(config: config)

      # Create deep recursion to trigger violation
      deep_recursion = lambda { |depth|
        if depth > 0
          deep_recursion.call(depth - 1)
        else
          Anzen.check!
        end
      }

      expect do
        deep_recursion.call(25)
      end.to raise_error(Anzen::RecursionLimitExceeded)
    end

    it 'skips disabled monitors' do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)

      expect { Anzen.check! }.not_to raise_error
    end
  end

  describe '.status' do
    before do
      config = { enabled_monitors: ['recursion'] }
      Anzen.setup(config: config)
    end

    it 'returns status hash with required keys' do
      status = Anzen.status
      expect(status).to have_key(:monitors)
      expect(status).to have_key(:enabled_count)
      expect(status).to have_key(:violations_total)
    end

    it 'includes all monitors in status' do
      status = Anzen.status
      expect(status[:monitors]).not_to be_empty
      expect(status[:monitors].first).to have_key(:name)
    end

    it 'includes enabled count' do
      status = Anzen.status
      expect(status[:enabled_count]).to eq(1)
    end

    it 'includes violations total' do
      status = Anzen.status
      expect(status[:violations_total]).to be_a(Integer)
    end

    it 'raises InitializationError if Anzen not initialized' do
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      expect do
        Anzen.status
      end.to raise_error(Anzen::InitializationError)
    end
  end

  describe '.register_monitor' do
    before do
      config = { enabled_monitors: [] }
      Anzen.setup(config: config)
    end

    let(:custom_monitor) do
      # Create a minimal valid monitor
      Class.new do
        def initialize
          @enabled = false
          @violations = 0
        end

        def name
          'custom'
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
          # no-op
        end

        def status
          { name: 'custom', enabled: @enabled, violations: @violations }
        end

        def to_cli
          'custom monitor'
        end
      end.new
    end

    it 'registers a custom monitor' do
      Anzen.register_monitor(custom_monitor)

      status = Anzen.status
      expect(status[:monitors].map { |m| m[:name] }).to include('custom')
    end

    it 'raises InvalidMonitorError if monitor lacks required method' do
      invalid_monitor = Object.new

      expect do
        Anzen.register_monitor(invalid_monitor)
      end.to raise_error(Anzen::InvalidMonitorError)
    end

    it 'raises MonitorNameConflictError if name already registered' do
      Anzen.register_monitor(custom_monitor)

      expect do
        Anzen.register_monitor(custom_monitor)
      end.to raise_error(Anzen::MonitorNameConflictError)
    end

    it 'raises InitializationError if Anzen not initialized' do
      Anzen.class_variable_set(:@@initialized, false)
      Anzen.class_variable_set(:@@registry, nil)

      expect do
        Anzen.register_monitor(custom_monitor)
      end.to raise_error(Anzen::InitializationError)
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'anzen/registry'

RSpec.describe Anzen::Registry do
  subject(:registry) { described_class.new }

  let(:mock_monitor) do
    instance_double(Anzen::Monitor,
                    name: 'test_monitor',
                    enable: true,
                    disable: false,
                    enabled?: false,
                    check!: nil,
                    status: { name: 'test_monitor', enabled: false, violations: 0 },
                    to_cli: 'test monitor')
  end

  describe 'initialization' do
    it 'creates empty registry' do
      expect(registry.list).to be_empty
    end

    it 'has no enabled monitors' do
      expect(registry.list_enabled).to be_empty
    end
  end

  describe '#register' do
    it 'registers a valid monitor' do
      registry.register(mock_monitor)
      expect(registry.list).to include(mock_monitor)
    end

    it 'stores monitor by name' do
      registry.register(mock_monitor)
      expect(registry.get('test_monitor')).to eq(mock_monitor)
    end

    it 'raises InvalidMonitorError if monitor lacks required method' do
      invalid_monitor = Object.new
      expect do
        registry.register(invalid_monitor)
      end.to raise_error(Anzen::InvalidMonitorError)
    end

    it 'raises MonitorNameConflictError if name already registered' do
      registry.register(mock_monitor)

      other_monitor = instance_double(Anzen::Monitor,
                                      name: 'test_monitor',
                                      enable: true,
                                      disable: false,
                                      enabled?: false,
                                      check!: nil,
                                      status: {},
                                      to_cli: 'other')

      expect do
        registry.register(other_monitor)
      end.to raise_error(Anzen::MonitorNameConflictError)
    end
  end

  describe '#unregister' do
    before { registry.register(mock_monitor) }

    it 'unregisters a monitor' do
      registry.unregister('test_monitor')
      expect(registry.list).not_to include(mock_monitor)
    end

    it 'raises MonitorNotFoundError if monitor not registered' do
      expect do
        registry.unregister('nonexistent')
      end.to raise_error(Anzen::MonitorNotFoundError)
    end

    it 'raises InvalidMonitorError if monitor is enabled' do
      registry.enable('test_monitor')
      expect do
        registry.unregister('test_monitor')
      end.to raise_error(Anzen::InvalidMonitorError)
    end
  end

  describe '#get' do
    before { registry.register(mock_monitor) }

    it 'returns monitor by name' do
      expect(registry.get('test_monitor')).to eq(mock_monitor)
    end

    it 'raises MonitorNotFoundError if not found' do
      expect do
        registry.get('nonexistent')
      end.to raise_error(Anzen::MonitorNotFoundError)
    end
  end

  describe '#list' do
    it 'returns empty array initially' do
      expect(registry.list).to eq([])
    end

    it 'returns all registered monitors' do
      monitor2 = instance_double(Anzen::Monitor,
                                 name: 'monitor2',
                                 enable: true,
                                 disable: false,
                                 enabled?: false,
                                 check!: nil,
                                 status: { name: 'monitor2' },
                                 to_cli: 'monitor2')

      registry.register(mock_monitor)
      registry.register(monitor2)

      expect(registry.list).to contain_exactly(mock_monitor, monitor2)
    end
  end

  describe '#list_enabled' do
    it 'returns empty array initially' do
      expect(registry.list_enabled).to be_empty
    end

    it 'returns only enabled monitors' do
      monitor2 = instance_double(Anzen::Monitor,
                                 name: 'monitor2',
                                 enable: true,
                                 disable: false,
                                 enabled?: false,
                                 check!: nil,
                                 status: { name: 'monitor2' },
                                 to_cli: 'monitor2')

      registry.register(mock_monitor)
      registry.register(monitor2)
      registry.enable('test_monitor')

      expect(registry.list_enabled).to contain_exactly(mock_monitor)
    end
  end

  describe '#enable' do
    before { registry.register(mock_monitor) }

    it 'enables a monitor' do
      expect(mock_monitor).to receive(:enable)
      registry.enable('test_monitor')
      expect(registry.list_enabled).to include(mock_monitor)
    end

    it 'raises MonitorNotFoundError if monitor not found' do
      expect do
        registry.enable('nonexistent')
      end.to raise_error(Anzen::MonitorNotFoundError)
    end
  end

  describe '#disable' do
    before { registry.register(mock_monitor) }

    before do
      registry.enable('test_monitor')
    end

    it 'disables a monitor' do
      expect(mock_monitor).to receive(:disable)
      registry.disable('test_monitor')
      expect(registry.list_enabled).not_to include(mock_monitor)
    end

    it 'raises MonitorNotFoundError if monitor not found' do
      expect do
        registry.disable('nonexistent')
      end.to raise_error(Anzen::MonitorNotFoundError)
    end
  end

  describe '#check_all!' do
    it 'returns nil when no monitors registered' do
      expect(registry.check_all!).to be_nil
    end

    it 'skips disabled monitors' do
      registry.register(mock_monitor)
      expect(mock_monitor).not_to receive(:check!)
      registry.check_all!
    end

    it 'calls check! on enabled monitors' do
      registry.register(mock_monitor)
      registry.enable('test_monitor')

      expect(mock_monitor).to receive(:check!)
      registry.check_all!
    end

    it 'raises first violation immediately (fail-fast)' do
      monitor1 = instance_double(Anzen::Monitor,
                                 name: 'monitor1',
                                 enable: true,
                                 disable: false,
                                 enabled?: true,
                                 check!: nil,
                                 status: { name: 'monitor1' },
                                 to_cli: 'monitor1')

      monitor2 = instance_double(Anzen::Monitor,
                                 name: 'monitor2',
                                 enable: true,
                                 disable: false,
                                 enabled?: true,
                                 status: { name: 'monitor2' },
                                 to_cli: 'monitor2')

      allow(monitor2).to receive(:check!).and_raise(Anzen::RecursionLimitExceeded.new(100, 50))

      registry.register(monitor1)
      registry.register(monitor2)
      registry.enable('monitor1')
      registry.enable('monitor2')

      expect do
        registry.check_all!
      end.to raise_error(Anzen::RecursionLimitExceeded)
    end

    it 'calls check! on multiple enabled monitors' do
      monitor2 = instance_double(Anzen::Monitor,
                                 name: 'monitor2',
                                 enable: true,
                                 disable: false,
                                 enabled?: true,
                                 check!: nil,
                                 status: { name: 'monitor2' },
                                 to_cli: 'monitor2')

      registry.register(mock_monitor)
      registry.register(monitor2)
      registry.enable('test_monitor')
      registry.enable('monitor2')

      expect(mock_monitor).to receive(:check!)
      expect(monitor2).to receive(:check!)

      registry.check_all!
    end
  end

  describe '#status' do
    it 'returns status hash with required keys' do
      status = registry.status
      expect(status).to have_key(:monitors)
      expect(status).to have_key(:enabled_count)
      expect(status).to have_key(:violations_total)
    end

    it 'returns empty monitors array when no monitors' do
      expect(registry.status[:monitors]).to eq([])
    end

    it 'includes all registered monitors in status' do
      registry.register(mock_monitor)

      status = registry.status
      expect(status[:monitors]).to include(mock_monitor.status)
    end

    it 'returns correct enabled_count' do
      registry.register(mock_monitor)
      registry.enable('test_monitor')

      expect(registry.status[:enabled_count]).to eq(1)
    end

    it 'returns zero violations initially' do
      registry.register(mock_monitor)

      expect(registry.status[:violations_total]).to eq(0)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent monitor registration' do
      threads = 5.times.map do |i|
        Thread.new do
          monitor = instance_double(Anzen::Monitor,
                                    name: "monitor#{i}",
                                    enable: true,
                                    disable: false,
                                    enabled?: false,
                                    check!: nil,
                                    status: { name: "monitor#{i}" },
                                    to_cli: "monitor#{i}")
          registry.register(monitor)
        end
      end

      threads.each(&:join)
      expect(registry.list.length).to eq(5)
    end

    it 'handles concurrent enable/disable' do
      registry.register(mock_monitor)

      threads = 10.times.map do
        Thread.new do
          if rand > 0.5
            begin
              registry.enable('test_monitor')
            rescue Anzen::MonitorNotFoundError
              # ignore
            end
          else
            begin
              registry.disable('test_monitor')
            rescue Anzen::MonitorNotFoundError
              # ignore
            end
          end
        end
      end

      threads.each(&:join)
      # Should complete without deadlock or error
    end
  end
end

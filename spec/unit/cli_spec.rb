# frozen_string_literal: true

require 'spec_helper'
require 'anzen/cli'

RSpec.describe Anzen::CLI do
  let(:cli) { described_class.new }

  before do
    # Setup Anzen with test configuration (only if not already initialized)

    Anzen.setup(
      config: {
        enabled_monitors: %w[recursion memory],
        monitors: {
          recursion: { depth_limit: 1000 },
          memory: { limit_mb: 512, sampling_interval_ms: 100 }
        }
      }
    )
  rescue Anzen::InitializationError
    # Already initialized, skip setup
  end

  describe '#status' do
    context 'with text format' do
      it 'generates correct text output' do
        output = cli.status(format: :text)

        expect(output).to include('Anzen Safety Protection Status')
        expect(output).to include('Enabled Monitors: recursion, memory')
        expect(output).to include('Monitor: recursion')
        expect(output).to include('Status: enabled')
        expect(output).to include('depth_limit: 1000')
        expect(output).to include('Monitor: memory')
        expect(output).to include('Status: enabled')
        expect(output).to include('limit_mb: 512')
        expect(output).to include('sampling_interval_ms: 100')
        expect(output).to include('Total Violations: 0')
      end
    end

    context 'with json format' do
      it 'generates correct JSON output' do
        output = cli.status(format: :json)
        data = JSON.parse(output, symbolize_names: true)

        expect(data).to have_key(:monitors)
        expect(data).to have_key(:enabled)
        expect(data).to have_key(:violations_total)
        expect(data).to have_key(:setup_at)

        expect(data[:enabled]).to include('recursion', 'memory')
        expect(data[:violations_total]).to eq(0)

        recursion_monitor = data[:monitors].find { |m| m[:name] == 'recursion' }
        expect(recursion_monitor).not_to be_nil
        expect(recursion_monitor[:enabled]).to be true
        expect(recursion_monitor[:thresholds][:depth_limit]).to eq(1000)

        memory_monitor = data[:monitors].find { |m| m[:name] == 'memory' }
        expect(memory_monitor).not_to be_nil
        expect(memory_monitor[:enabled]).to be true
        expect(memory_monitor[:thresholds][:limit_mb]).to eq(512)
      end
    end

    context 'with invalid format' do
      it 'raises ArgumentError' do
        expect { cli.status(format: :invalid) }.to raise_error(ArgumentError, /Invalid format/)
      end
    end
  end

  describe '#config' do
    context 'with specific monitor' do
      context 'with text format' do
        it 'generates correct text output for recursion monitor' do
          output = cli.config(monitor_name: 'recursion', format: :text)

          expect(output).to include('Monitor: recursion')
          expect(output).to include('Enabled: yes')
          expect(output).to include('depth_limit: 1000')
        end

        it 'generates correct text output for memory monitor' do
          output = cli.config(monitor_name: 'memory', format: :text)

          expect(output).to include('Monitor: memory')
          expect(output).to include('Enabled: yes')
          expect(output).to include('limit_mb: 512')
          expect(output).to include('sampling_interval_ms: 100')
        end
      end

      context 'with json format' do
        it 'generates correct JSON output' do
          output = cli.config(monitor_name: 'recursion', format: :json)
          data = JSON.parse(output, symbolize_names: true)

          expect(data[:monitor]).to eq('recursion')
          expect(data[:enabled]).to be true
          expect(data[:config][:depth_limit]).to eq(1000)
        end
      end

      context 'with non-existent monitor' do
        it 'raises MonitorNotFoundError' do
          expect { cli.config(monitor_name: 'nonexistent', format: :text) }
            .to raise_error(Anzen::MonitorNotFoundError, /Monitor 'nonexistent' not found/)
        end
      end
    end

    context 'without specific monitor (all configs)' do
      context 'with text format' do
        it 'generates correct text output' do
          output = cli.config(format: :text)

          expect(output).to include('Anzen Configuration')
          expect(output).to include('Monitor: recursion')
          expect(output).to include('Monitor: memory')
          expect(output).to include('Enabled: yes')
        end
      end

      context 'with json format' do
        it 'generates correct JSON output' do
          output = cli.config(format: :json)
          data = JSON.parse(output, symbolize_names: true)

          expect(data).to have_key(:monitors)
          expect(data[:monitors]).to have_key(:recursion)
          expect(data[:monitors]).to have_key(:memory)

          expect(data[:monitors][:recursion][:enabled]).to be true
          expect(data[:monitors][:recursion][:config][:depth_limit]).to eq(1000)
        end
      end
    end

    context 'with invalid format' do
      it 'raises ArgumentError' do
        expect { cli.config(format: :invalid) }.to raise_error(ArgumentError, /Invalid format/)
      end
    end
  end

  describe '#info' do
    context 'with text format' do
      it 'generates correct text output' do
        output = cli.info(format: :text)

        expect(output).to include('Anzen Gem Information')
        expect(output).to include('Version:')
        expect(output).to include('Ruby Version:')
        expect(output).to include('Platform:')
        expect(output).to include('Available Monitors: recursion, memory')
        expect(output).to include('License: MIT')
      end
    end

    context 'with json format' do
      it 'generates correct JSON output' do
        output = cli.info(format: :json)
        data = JSON.parse(output, symbolize_names: true)

        expect(data[:name]).to eq('anzen')
        expect(data[:version]).to eq(Anzen::VERSION)
        expect(data[:monitors_available]).to include('recursion', 'memory')
        expect(data[:license]).to eq('MIT')
      end
    end

    context 'with invalid format' do
      it 'raises ArgumentError' do
        expect { cli.info(format: :invalid) }.to raise_error(ArgumentError, /Invalid format/)
      end
    end
  end

  describe '#help' do
    context 'without specific command' do
      it 'generates general help text' do
        output = cli.help

        expect(output).to include('Anzen Safety Protection - Command Line Interface')
        expect(output).to include('Usage: anzen [command] [options]')
        expect(output).to include('Commands:')
        expect(output).to include('status')
        expect(output).to include('config')
        expect(output).to include('info')
        expect(output).to include('help')
        expect(output).to include('Examples:')
      end
    end

    context 'with specific command' do
      it 'generates help for status command' do
        output = cli.help(command: 'status')

        expect(output).to include('anzen status - Display protection status')
        expect(output).to include('Usage: anzen status [options]')
        expect(output).to include('--format FORMAT')
      end

      it 'generates help for config command' do
        output = cli.help(command: 'config')

        expect(output).to include('anzen config - Display monitor configuration')
        expect(output).to include('Usage: anzen config [monitor_name] [options]')
      end

      it 'generates help for info command' do
        output = cli.help(command: 'info')

        expect(output).to include('anzen info - Display gem installation information')
        expect(output).to include('Usage: anzen info [options]')
      end

      it 'handles unknown command' do
        output = cli.help(command: 'unknown')

        expect(output).to include("Unknown command 'unknown'")
      end
    end
  end
end

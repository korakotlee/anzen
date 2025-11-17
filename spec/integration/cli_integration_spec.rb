# frozen_string_literal: true

require 'spec_helper'
require 'open3'

RSpec.describe 'CLI Integration' do
  let(:anzen_bin) { File.expand_path('../../bin/anzen', __dir__) }

  describe 'anzen status' do
    it 'displays current state in text format by default' do
      output, status = run_command('status')

      expect(status.exitstatus).to eq(0)
      expect(output).to include('Anzen Safety Protection Status')
      expect(output).to include('Enabled Monitors: recursion, memory')
      expect(output).to include('Monitor: recursion')
      expect(output).to include('Status: enabled')
      expect(output).to include('Monitor: memory')
      expect(output).to include('Status: enabled')
    end

    it 'displays current state in JSON format' do
      output, status = run_command('status --format json')

      expect(status.exitstatus).to eq(0)
      data = JSON.parse(output, symbolize_names: true)
      expect(data).to have_key(:monitors)
      expect(data).to have_key(:enabled)
      expect(data[:enabled]).to include('recursion', 'memory')
    end

    it 'returns correct exit code for invalid format' do
      output, status = run_command('status --format invalid')

      expect(status.exitstatus).to eq(2) # EXIT_INVALID_ARGUMENTS
      expect(output).to include('Error: Invalid format')
    end
  end

  describe 'anzen config' do
    it 'shows configuration for all monitors in text format' do
      output, status = run_command('config')

      expect(status.exitstatus).to eq(0)
      expect(output).to include('Anzen Configuration')
      expect(output).to include('Monitor: recursion')
      expect(output).to include('Monitor: memory')
      expect(output).to include('Enabled: yes')
    end

    it 'shows configuration for specific monitor' do
      output, status = run_command('config recursion')

      expect(status.exitstatus).to eq(0)
      expect(output).to include('Monitor: recursion')
      expect(output).to include('Enabled: yes')
      expect(output).to include('depth_limit: 1000')
      expect(output).not_to include('Monitor: memory')
    end

    it 'shows configuration in JSON format' do
      output, status = run_command('config --format json')

      expect(status.exitstatus).to eq(0)
      data = JSON.parse(output, symbolize_names: true)
      expect(data).to have_key(:monitors)
      expect(data[:monitors][:recursion][:enabled]).to be true
    end

    it 'returns error for non-existent monitor' do
      output, status = run_command('config nonexistent')

      expect(status.exitstatus).to eq(3) # EXIT_MONITOR_NOT_FOUND
      expect(output).to include("Error: Monitor 'nonexistent' not found")
    end
  end

  describe 'anzen info' do
    it 'shows gem details in text format' do
      output, status = run_command('info')

      expect(status.exitstatus).to eq(0)
      expect(output).to include('Anzen Gem Information')
      expect(output).to include('Version:')
      expect(output).to include('Ruby Version:')
      expect(output).to include('Available Monitors: recursion, memory')
      expect(output).to include('License: MIT')
    end

    it 'shows gem details in JSON format' do
      output, status = run_command('info --format json')

      expect(status.exitstatus).to eq(0)
      data = JSON.parse(output, symbolize_names: true)
      expect(data[:name]).to eq('anzen')
      expect(data[:version]).to eq(Anzen::VERSION)
      expect(data[:monitors_available]).to include('recursion', 'memory')
    end
  end

  describe 'anzen help' do
    it 'shows general help text' do
      output, status = run_command('help')

      expect(status.exitstatus).to eq(0)
      expect(output).to include('Anzen Safety Protection - Command Line Interface')
      expect(output).to include('Usage: anzen [command] [options]')
      expect(output).to include('Commands:')
      expect(output).to include('status')
      expect(output).to include('config')
      expect(output).to include('info')
    end

    it 'shows help for specific command' do
      output, status = run_command('help status')

      expect(status.exitstatus).to eq(0)
      expect(output).to include('anzen status - Display protection status')
      expect(output).to include('Usage: anzen status [options]')
    end

    it 'shows help for config command' do
      output, status = run_command('help config')

      expect(status.exitstatus).to eq(0)
      expect(output).to include('anzen config - Display monitor configuration')
    end
  end

  describe 'anzen --version' do
    it 'shows gem version' do
      output, status = run_command('--version')

      expect(status.exitstatus).to eq(0)
      expect(output.strip).to eq("anzen #{Anzen::VERSION}")
    end

    it 'shows gem version with -v flag' do
      output, status = run_command('-v')

      expect(status.exitstatus).to eq(0)
      expect(output.strip).to eq("anzen #{Anzen::VERSION}")
    end
  end

  describe 'anzen (no command)' do
    it 'shows help by default' do
      output, status = run_command('')

      expect(status.exitstatus).to eq(0)
      expect(output).to include('Anzen Safety Protection - Command Line Interface')
    end
  end

  describe 'anzen (unknown command)' do
    it 'returns error for unknown command' do
      output, status = run_command('unknown')

      expect(status.exitstatus).to eq(2) # EXIT_INVALID_ARGUMENTS
      expect(output).to include("Error: Unknown command 'unknown'")
    end
  end

  private

  def run_command(args)
    command = "#{RbConfig.ruby} #{anzen_bin} --test-init #{args}"
    output, status = Open3.capture2e(command)
    [output, status]
  end
end

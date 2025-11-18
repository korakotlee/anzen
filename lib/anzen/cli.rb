# frozen_string_literal: true

require 'json'
require 'time'

module Anzen
  # Command-line interface for Anzen safety monitoring
  #
  # Provides operator-facing commands to query protection status,
  # configuration, and monitor state without code changes.
  #
  # @api public
  class CLI
    # Display current protection configuration and monitor state
    #
    # @param format [Symbol] Output format (:json or :text)
    # @return [String] Formatted output
    # @api public
    def status(format: :text)
      status_data = Anzen.status

      case format
      when :json
        JSON.pretty_generate(status_data)
      when :text
        format_status_text(status_data)
      else
        raise ArgumentError, "Invalid format: #{format}. Use :json or :text"
      end
    end

    # Display detailed configuration for all monitors or specific monitor
    #
    # @param monitor_name [String, nil] Specific monitor name, or nil for all
    # @param format [Symbol] Output format (:json or :text)
    # @return [String] Formatted output
    # @api public
    def config(monitor_name: nil, format: :text)
      if monitor_name
        monitor_config = get_monitor_config(monitor_name)
        case format
        when :json
          JSON.pretty_generate(monitor_config)
        when :text
          format_monitor_config_text(monitor_name, monitor_config)
        else
          raise ArgumentError, "Invalid format: #{format}. Use :json or :text"
        end
      else
        all_configs = get_all_configs
        case format
        when :json
          JSON.pretty_generate(all_configs)
        when :text
          format_all_configs_text(all_configs)
        else
          raise ArgumentError, "Invalid format: #{format}. Use :json or :text"
        end
      end
    end

    # Display general information about the Anzen gem installation
    #
    # @param format [Symbol] Output format (:json or :text)
    # @return [String] Formatted output
    # @api public
    def info(format: :text)
      info_data = {
        name: 'anzen',
        version: Anzen::VERSION,
        ruby_version: RUBY_VERSION,
        platform: RUBY_PLATFORM,
        monitors_available: %w[recursion memory],
        license: 'MIT',
        documentation_url: 'https://github.com/[org]/anzen'
      }

      case format
      when :json
        JSON.pretty_generate(info_data)
      when :text
        format_info_text(info_data)
      else
        raise ArgumentError, "Invalid format: #{format}. Use :json or :text"
      end
    end

    # Display help documentation and command reference
    #
    # @param command [String, nil] Specific command name, or nil for general help
    # @return [String] Help text
    # @api public
    def help(command: nil)
      if command
        format_command_help(command)
      else
        format_general_help
      end
    end

    private

    def get_monitor_config(monitor_name)
      status_data = Anzen.status
      monitor = status_data[:monitors].find { |m| m[:name] == monitor_name }

      raise Anzen::MonitorNotFoundError.new(monitor_name) unless monitor

      {
        monitor: monitor_name,
        enabled: monitor[:enabled],
        config: monitor[:thresholds]
      }
    end

    def get_all_configs
      status_data = Anzen.status
      {
        monitors: status_data[:monitors].each_with_object({}) do |monitor, hash|
          hash[monitor[:name]] = {
            enabled: monitor[:enabled],
            config: monitor[:thresholds]
          }
        end
      }
    end

    def format_status_text(status_data)
      output = []
      output << 'Anzen Safety Protection Status'
      output << ('=' * 40)
      output << ''
      output << "Enabled Monitors: #{status_data[:enabled].join(", ")}"
      output << ''

      status_data[:monitors].each do |monitor|
        output << "Monitor: #{monitor[:name]}"
        output << "  Status: #{monitor[:enabled] ? "enabled" : "disabled"}"
        output << '  Thresholds:'

        monitor[:thresholds].each do |key, value|
          output << "    #{key}: #{value}"
        end

        last_check = monitor[:last_check]
        output << if last_check
                    "  Last Check: #{last_check.strftime("%Y-%m-%d %H:%M:%S %Z")}"
                  else
                    '  Last Check: never'
                  end

        output << "  Violations Detected: #{monitor[:violations]}"
        output << ''
      end

      output << "Total Violations: #{status_data[:violations_total]}"
      output << "Setup Time: #{status_data[:setup_at].strftime("%Y-%m-%d %H:%M:%S %Z")}"

      output.join("\n")
    end

    def format_monitor_config_text(monitor_name, config)
      output = []
      output << "Monitor: #{monitor_name}"
      output << "  Enabled: #{config[:enabled] ? "yes" : "no"}"
      output << '  Configuration:'

      config[:config].each do |key, value|
        output << "    #{key}: #{value}"
      end

      output.join("\n")
    end

    def format_all_configs_text(configs)
      output = []
      output << 'Anzen Configuration'
      output << ('=' * 20)
      output << ''

      configs[:monitors].each do |name, config|
        output << "Monitor: #{name}"
        output << "  Enabled: #{config[:enabled] ? "yes" : "no"}"
        output << '  Configuration:'

        config[:config].each do |key, value|
          output << "    #{key}: #{value}"
        end

        output << ''
      end

      output.join("\n")
    end

    def format_info_text(info_data)
      output = []
      output << 'Anzen Gem Information'
      output << ('=' * 25)
      output << ''
      output << "Version: #{info_data[:version]}"
      output << "Installed Location: #{Gem.loaded_specs["anzen"]&.full_gem_path || "Not installed as gem"}"
      output << "Ruby Version: #{info_data[:ruby_version]}"
      output << "Platform: #{info_data[:platform]}"
      output << "Available Monitors: #{info_data[:monitors_available].join(", ")}"
      output << "License: #{info_data[:license]}"
      output << "Documentation: #{info_data[:documentation_url]}"

      output.join("\n")
    end

    def format_general_help
      <<~HELP
        Anzen Safety Protection - Command Line Interface

        Usage: anzen [command] [options]

        Commands:
          status        Display protection status and monitor state
          config        Display monitor configuration details
          info          Display gem installation information
          help          Show this help message

        Options:
          --format      Output format: json, text (default: text)
          --help        Show command help
          -v, --version Show gem version

        Examples:
          anzen status                    # Show status
          anzen config memory --format json  # Show memory config as JSON
          anzen info                      # Show gem info

        For more information, see: https://github.com/[org]/anzen
      HELP
    end

    def format_command_help(command)
      case command
      when 'status'
        <<~HELP
          anzen status - Display protection status and monitor state

          Usage: anzen status [options]

          Options:
            --format FORMAT   Output format: json, text (default: text)

          Examples:
            anzen status
            anzen status --format json

          Output includes:
            - Monitor names and enabled/disabled state
            - Configured thresholds for each monitor
            - Last check timestamp
            - Total violations detected
        HELP
      when 'config'
        <<~HELP
          anzen config - Display monitor configuration details

          Usage: anzen config [monitor_name] [options]

          Arguments:
            monitor_name      Optional: Show config for specific monitor

          Options:
            --format FORMAT   Output format: json, text (default: text)

          Examples:
            anzen config
            anzen config memory
            anzen config --format json

          Shows configuration for all monitors or specific monitor.
        HELP
      when 'info'
        <<~HELP
          anzen info - Display gem installation information

          Usage: anzen info [options]

          Options:
            --format FORMAT   Output format: json, text (default: text)

          Examples:
            anzen info
            anzen info --format json

          Shows gem version, Ruby version, platform, and other metadata.
        HELP
      else
        "Unknown command '#{command}'. Use 'anzen help' for available commands."
      end
    end
  end
end

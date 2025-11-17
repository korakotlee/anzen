# frozen_string_literal: true

require 'json'
require 'yaml'

module Anzen
  # Configuration manager for Anzen
  #
  # Loads and validates configuration from various sources.
  # Supports dot-notation for accessing nested config values.
  #
  # @api public
  class Configuration
    # Load configuration from environment variable
    #
    # Expects ANZEN_CONFIG to contain JSON or YAML config.
    #
    # @return [Configuration] configuration instance
    # @raise [ConfigurationError] if config is invalid
    def self.from_env
      config_str = ENV['ANZEN_CONFIG']
      raise Anzen::ConfigurationError, 'ANZEN_CONFIG not set' unless config_str

      begin
        # Try JSON first
        config = JSON.parse(config_str)
      rescue JSON::ParserError
        # Fall back to YAML
        config = YAML.safe_load(config_str)
      end

      new(config)
    end

    # Load configuration from file
    #
    # @param path [String] path to config file (JSON or YAML)
    # @return [Configuration] configuration instance
    # @raise [ConfigurationError] if file doesn't exist or is invalid
    def self.from_file(path)
      raise Anzen::ConfigurationError, "Config file not found: #{path}" unless File.exist?(path)

      content = File.read(path)
      config = if path.end_with?('.json')
                 JSON.parse(content)
               else
                 YAML.safe_load(content)
               end

      new(config)
    end

    # Create configuration from hash (programmatic)
    #
    # @param config [Hash] configuration hash
    # @return [Configuration] configuration instance
    def self.programmatic(config = {})
      new(config)
    end

    # Initialize Configuration
    #
    # @param config [Hash] configuration hash
    def initialize(config = {})
      @config = normalize_keys(config)
      validate!
    end

    # Get configuration value by dot-notation path
    #
    # @param path [String] dot-notation path (e.g., "monitors.recursion.depth_limit")
    # @return [Object] configuration value
    # @raise [ConfigurationError] if path doesn't exist
    def get(path)
      keys = path.split('.')
      value = @config

      keys.each do |key|
        case value
        when Hash
          value = value[key] || value[key.to_sym]
        else
          raise Anzen::ConfigurationError, "Cannot access '#{key}' in non-hash value"
        end

        raise Anzen::ConfigurationError, "Config path not found: #{path}" if value.nil?
      end

      value
    end

    # Check if monitor is enabled
    #
    # @param name [String] monitor name
    # @return [Boolean] true if monitor is in enabled_monitors list
    def monitor_enabled?(name)
      enabled = begin
        get('enabled_monitors')
      rescue StandardError
        []
      end
      enabled.include?(name)
    end

    # Get configuration for specific monitor
    #
    # @param name [String] monitor name
    # @return [Hash] monitor configuration
    # @raise [ConfigurationError] if monitor config not found
    def monitor_config(name)
      get("monitors.#{name}")
    end

    # Validate configuration schema
    #
    # @return [Boolean] true if valid
    # @raise [ConfigurationError] if invalid
    def validate!
      # Normalize keys to strings for consistent access
      normalized = normalize_keys(@config)

      # enabled_monitors should be array if present and non-nil
      if normalized.key?('enabled_monitors') && !normalized['enabled_monitors'].nil? && !normalized['enabled_monitors'].is_a?(Array)
        raise Anzen::ConfigurationError, 'enabled_monitors must be an array'
      end

      # monitors should be hash if present and non-nil
      if normalized.key?('monitors') && !normalized['monitors'].nil? && !normalized['monitors'].is_a?(Hash)
        raise Anzen::ConfigurationError, 'monitors must be a hash'
      end

      # Validate monitor configs
      monitors = normalized['monitors'] || {}
      monitors.each do |name, config|
        validate_monitor_config(name, config)
      end

      true
    end

    # Return raw configuration hash
    #
    # @return [Hash]
    def to_h
      deep_dup(@config)
    end

    private

    # Deep copy of a hash
    #
    # @param obj [Object] object to deep copy
    # @return [Object] deep copy
    def deep_dup(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), hash|
          hash[k] = deep_dup(v)
        end
      when Array
        obj.map { |item| deep_dup(item) }
      else
        begin
          obj.dup
        rescue StandardError
          obj
        end
      end
    end

    # Normalize hash keys from symbols to strings (recursively)
    #
    # @param hash [Hash] hash to normalize
    # @return [Hash] hash with string keys
    def normalize_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), new_hash|
        string_key = key.is_a?(Symbol) ? key.to_s : key
        new_hash[string_key] = value.is_a?(Hash) ? normalize_keys(value) : value
      end
    end

    # Validate individual monitor configuration
    #
    # @param name [String] monitor name
    # @param config [Hash] monitor configuration
    # @raise [ConfigurationError] if invalid
    def validate_monitor_config(name, config)
      return unless config.is_a?(Hash)

      case name
      when 'recursion'
        validate_recursion_config(config)
      when 'memory'
        validate_memory_config(config)
      end
    end

    # Validate recursion monitor config
    #
    # @param config [Hash] recursion config
    # @raise [ConfigurationError] if invalid
    def validate_recursion_config(config)
      normalized = normalize_keys(config)

      if normalized['depth_limit'] && !normalized['depth_limit'].is_a?(Numeric)
        raise Anzen::ConfigurationError, 'recursion.depth_limit must be numeric'
      end

      return unless normalized['depth_limit'] && normalized['depth_limit'] <= 0

      raise Anzen::ConfigurationError, 'recursion.depth_limit must be positive'
    end

    # Validate memory monitor config
    #
    # @param config [Hash] memory config
    # @raise [ConfigurationError] if invalid
    def validate_memory_config(config)
      normalized = normalize_keys(config)

      if normalized['limit_mb'] && !normalized['limit_mb'].is_a?(Numeric)
        raise Anzen::ConfigurationError, 'memory.limit_mb must be numeric'
      end

      if normalized['limit_mb'] && normalized['limit_mb'] <= 0
        raise Anzen::ConfigurationError, 'memory.limit_mb must be positive'
      end

      if normalized['limit_percent'] && !normalized['limit_percent'].is_a?(Numeric)
        raise Anzen::ConfigurationError, 'memory.limit_percent must be numeric'
      end

      if normalized['limit_percent'] && (normalized['limit_percent'] <= 0 || normalized['limit_percent'] > 100)
        raise Anzen::ConfigurationError, 'memory.limit_percent must be between 0 and 100'
      end
    end
  end
end

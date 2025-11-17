# Anzen Ruby API Reference

This document provides comprehensive API reference for the Anzen runtime safety protection gem.

## Table of Contents

- [Core Module](#core-module)
- [Configuration](#configuration)
- [Monitors](#monitors)
- [Exceptions](#exceptions)
- [CLI Interface](#cli-interface)

## Core Module

The `Anzen` module provides the main public API for runtime safety protection.

### Setup and Initialization

#### `Anzen.setup(config: {})`

Initializes the Anzen safety protection system with the specified configuration.

**Parameters:**
- `config` (Hash): Configuration hash with the following structure:
  - `enabled_monitors` (Array<String>): Array of monitor names to enable initially
  - `monitors` (Hash): Monitor-specific configuration

**Example:**
```ruby
Anzen.setup(config: {
  enabled_monitors: ['recursion', 'memory'],
  monitors: {
    recursion: { depth_limit: 1000 },
    memory: { limit_mb: 512, sampling_interval_ms: 100 }
  }
})
```

**Raises:**
- `Anzen::InitializationError`: If Anzen is already initialized
- `Anzen::ConfigurationError`: If configuration is invalid

**Returns:** `nil`

### Runtime Control

#### `Anzen.enable(name)`

Enables a registered monitor by name.

**Parameters:**
- `name` (String): Name of the monitor to enable

**Example:**
```ruby
Anzen.enable('recursion')
Anzen.enable('memory')
```

**Raises:**
- `Anzen::MonitorNotFoundError`: If monitor is not registered

**Returns:** `true` if enabled, `false` if already enabled

#### `Anzen.disable(name)`

Disables a registered monitor by name.

**Parameters:**
- `name` (String): Name of the monitor to disable

**Example:**
```ruby
Anzen.disable('memory')
```

**Raises:**
- `Anzen::MonitorNotFoundError`: If monitor is not registered

**Returns:** `true` if disabled, `false` if already disabled

#### `Anzen.check!`

Performs safety checks on all enabled monitors. Raises the first violation detected.

**Example:**
```ruby
begin
  Anzen.check!
  puts "All checks passed"
rescue Anzen::RecursionLimitExceeded => e
  puts "Recursion violation: #{e.current_depth} > #{e.threshold}"
rescue Anzen::MemoryLimitExceeded => e
  puts "Memory violation: #{e.current_memory_mb}MB > #{e.memory_limit_mb}MB"
end
```

**Raises:**
- `Anzen::ViolationError`: Subclass for safety violations
- `Anzen::CheckFailedError`: For infrastructure errors

**Returns:** `nil` if all checks pass

### Status and Information

#### `Anzen.status`

Returns the current status of all monitors and the system.

**Returns:** Hash with the following structure:
```ruby
{
  enabled_monitors: ['recursion', 'memory'],
  setup_time: Time,  # When Anzen was initialized
  monitors: {
    'recursion' => {
      status: 'enabled',  # or 'disabled'
      thresholds: { depth_limit: 1000 },
      last_check: Time,   # or nil
      violations_detected: 0
    },
    'memory' => {
      status: 'enabled',
      thresholds: { limit_mb: 512, sampling_interval_ms: 100 },
      last_check: Time,
      violations_detected: 0
    }
  }
}
```

**Example:**
```ruby
status = Anzen.status
puts "Enabled monitors: #{status[:enabled_monitors].join(', ')}"
puts "Setup time: #{status[:setup_time]}"
```

### Custom Monitor Registration

#### `Anzen.register_monitor(monitor_instance)`

Registers a custom monitor instance with the system.

**Parameters:**
- `monitor_instance`: Object implementing the Monitor interface

**Example:**
```ruby
class CustomMonitor
  def name; 'custom'; end
  def enable; @enabled = true; end
  def disable; @enabled = false; end
  def enabled?; @enabled; end
  def check!; # custom safety check; end
  def status; { status: enabled? ? 'enabled' : 'disabled' }; end
  def to_cli; "Custom monitor: #{enabled? ? 'enabled' : 'disabled'}"; end
end

Anzen.register_monitor(CustomMonitor.new)
```

**Raises:**
- `Anzen::InvalidMonitorError`: If monitor doesn't implement required interface
- `Anzen::MonitorNameConflictError`: If monitor name already registered

**Returns:** `true` if registered successfully

## Configuration

Configuration can be loaded from multiple sources with the following precedence (highest to lowest):

1. Programmatic configuration (passed to `Anzen.setup`)
2. Environment variable `ANZEN_CONFIG` (JSON/YAML)
3. Configuration file (anzen.yml, anzen.json)

### Configuration Schema

```yaml
anzen:
  enabled_monitors:
    - recursion
    - memory
  monitors:
    recursion:
      depth_limit: 1000
    memory:
      limit_mb: 512
      sampling_interval_ms: 100
```

### Environment Variable Configuration

```bash
export ANZEN_CONFIG='{
  "enabled_monitors": ["recursion", "memory"],
  "monitors": {
    "recursion": {"depth_limit": 500},
    "memory": {"limit_mb": 1024}
  }
}'
```

### File-based Configuration

Create `anzen.yml` or `anzen.json` in your project root:

```yaml
# anzen.yml
anzen:
  enabled_monitors: [recursion, memory]
  monitors:
    recursion:
      depth_limit: 1000
    memory:
      limit_mb: 512
```

## Monitors

Anzen includes built-in monitors for common safety concerns. All monitors implement the same interface.

### Monitor Interface

All monitors must implement these methods:

- `name` (String): Unique monitor identifier
- `enable`: Enable the monitor
- `disable`: Disable the monitor
- `enabled?` (Boolean): Check if monitor is enabled
- `check!`: Perform safety check, raise ViolationError if unsafe
- `status` (Hash): Return monitor status information
- `to_cli` (String): Return human-readable status for CLI

### Built-in Monitors

#### RecursionMonitor

Detects recursive method calls and raises immediately on first detection.

**Configuration:**
- No thresholds - blocks all recursion

**Status Fields:**
- `status`: 'enabled' or 'disabled'
- `violations_detected`: Number of recursion violations detected

#### CallStackDepthMonitor

Limits call stack depth to prevent stack overflow.

**Configuration:**
- `depth_limit` (Integer): Maximum allowed stack depth (default: 1000)

**Status Fields:**
- `status`: 'enabled' or 'disabled'
- `thresholds`: { depth_limit: Integer }
- `last_check`: Time of last check or nil
- `violations_detected`: Number of depth violations

#### MemoryMonitor

Monitors process memory usage with sampling to prevent OOM conditions.

**Configuration:**
- `limit_mb` (Integer): Memory limit in MB
- `sampling_interval_ms` (Integer): Minimum time between checks (default: 100)

**Status Fields:**
- `status`: 'enabled' or 'disabled'
- `thresholds`: { limit_mb: Integer, sampling_interval_ms: Integer }
- `last_check`: Time of last check or nil
- `violations_detected`: Number of memory violations

## Exceptions

Anzen uses a structured exception hierarchy for different types of errors.

### Violation Errors

Raised when safety violations are detected during `check!` calls.

#### `Anzen::ViolationError`

Base class for all safety violations. Inherits from `StandardError`.

**Attributes:**
- `monitor_name` (String): Name of the monitor that detected the violation

#### `Anzen::RecursionLimitExceeded`

Raised when recursion limits are exceeded.

**Attributes:**
- `current_depth` (Integer): Current call stack depth
- `threshold` (Integer): Configured depth limit

**Example:**
```ruby
rescue Anzen::RecursionLimitExceeded => e
  puts "Recursion limit exceeded: #{e.current_depth} > #{e.threshold}"
end
```

#### `Anzen::MemoryLimitExceeded`

Raised when memory limits are exceeded.

**Attributes:**
- `current_memory_mb` (Float): Current memory usage in MB
- `memory_limit_mb` (Integer): Configured memory limit in MB

**Example:**
```ruby
rescue Anzen::MemoryLimitExceeded => e
  puts "Memory limit exceeded: #{e.current_memory_mb}MB > #{e.memory_limit_mb}MB"
end
```

### Infrastructure Errors

Raised for configuration and operational issues.

#### `Anzen::CheckFailedError`

Raised when a monitor check fails due to infrastructure issues.

**Attributes:**
- `monitor_name` (String): Name of the monitor that failed
- `reason` (String): Description of the failure
- `original_error` (Exception): The underlying error that caused the failure

#### `Anzen::ConfigurationError`

Raised when configuration is invalid.

**Attributes:**
- `field` (String): Configuration field that is invalid
- `value`: The invalid value
- `reason` (String): Why the value is invalid

#### `Anzen::MonitorNotFoundError`

Raised when trying to enable/disable a monitor that doesn't exist.

**Attributes:**
- `monitor_name` (String): Name of the monitor that was not found

#### `Anzen::InvalidMonitorError`

Raised when registering a monitor that doesn't implement the required interface.

**Attributes:**
- `monitor_class`: The invalid monitor class
- `missing_methods` (Array<String>): Methods that are missing from the interface

#### `Anzen::MonitorNameConflictError`

Raised when trying to register a monitor with a name that already exists.

**Attributes:**
- `monitor_name` (String): The conflicting monitor name

#### `Anzen::InitializationError`

Raised when trying to initialize Anzen multiple times.

**Attributes:**
- `reason` (String): Why initialization failed

## CLI Interface

The Anzen CLI provides command-line access to system status and configuration.

### Commands

#### `anzen status [--format json|text]`

Displays the current status of all monitors and the system.

**Options:**
- `--format`: Output format ('json' or 'text', default: 'text')

**Exit Codes:**
- 0: Success
- 1: General error
- 2: Monitor not found
- 3: Configuration error
- 4: Initialization error

**Example Output (text):**
```
Anzen Safety Protection Status
========================================

Enabled Monitors: recursion, memory

Monitor: recursion
  Status: enabled
  Thresholds:
    depth_limit: 1000
  Last Check: never
  Violations Detected: 0

Monitor: memory
  Status: enabled
  Thresholds:
    limit_mb: 512
    sampling_interval_ms: 100
  Last Check: never
  Violations Detected: 0

Total Violations: 0
Setup Time: 2025-11-17 17:05:02 EST
```

#### `anzen config [monitor_name] [--format json|text]`

Displays configuration information.

**Parameters:**
- `monitor_name` (optional): Show config for specific monitor only

**Options:**
- `--format`: Output format ('json' or 'text', default: 'text')

**Example:**
```bash
anzen config memory
anzen config --format json
```

#### `anzen info [--format json|text]`

Displays system and gem information.

**Options:**
- `--format`: Output format ('json' or 'text', default: 'text')

**Example Output:**
```
Anzen Runtime Safety Protection
Version: 0.1.0
Ruby Version: 3.2.2
Platform: x86_64-darwin22
Process ID: 12345
Memory Usage: 45.2 MB
```

#### `anzen help [command]`

Displays help information.

**Parameters:**
- `command` (optional): Show help for specific command

**Example:**
```bash
anzen help
anzen help status
```

### Global Options

- `--version`: Show version information
- `--help`: Show help information

### Exit Codes

All CLI commands return standardized exit codes:

- `0`: Success
- `1`: General error (unexpected exceptions)
- `2`: Monitor not found
- `3`: Configuration error
- `4`: Initialization error (Anzen not set up)

## Integration Patterns

### Rails Application

```ruby
# config/initializers/anzen.rb
require 'anzen'

Anzen.setup(config: {
  enabled_monitors: ['recursion', 'memory'],
  monitors: {
    recursion: { depth_limit: 1000 },
    memory: { limit_mb: 512 }
  }
})
```

### Rack Middleware

```ruby
# config.ru
require 'anzen'

use Anzen::Middleware

Anzen.setup(config: {
  enabled_monitors: ['recursion']
})
```

### Standalone Ruby Script

```ruby
#!/usr/bin/env ruby
require 'anzen'

Anzen.setup(config: {
  enabled_monitors: ['memory'],
  monitors: {
    memory: { limit_mb: 1024 }
  }
})

# Your application code here
# Anzen automatically checks safety limits
```

### Error Handling

```ruby
begin
  # Risky operation
  process_large_dataset(data)
rescue Anzen::RecursionLimitExceeded => e
  logger.error("Recursion limit exceeded: #{e.current_depth} > #{e.threshold}")
  # Handle gracefully - retry with smaller chunks
rescue Anzen::MemoryLimitExceeded => e
  logger.error("Memory limit exceeded: #{e.current_memory_mb}MB > #{e.memory_limit_mb}MB")
  # Clean up resources and exit gracefully
rescue Anzen::CheckFailedError => e
  logger.error("Monitor check failed: #{e.monitor_name} - #{e.reason}")
  # Infrastructure issue - may need to disable monitor
end
```

### Custom Monitors

```ruby
class DatabaseConnectionMonitor
  def name; 'database_connections'; end

  def initialize(config = {})
    @max_connections = config.fetch('max_connections', 100)
    @enabled = false
    @violations = 0
  end

  def enable; @enabled = true; end
  def disable; @enabled = false; end
  def enabled?; @enabled; end

  def check!
    return unless enabled?

    current_connections = ActiveRecord::Base.connection_pool.connections.size
    if current_connections > @max_connections
      raise Anzen::ViolationError.new(
        "Database connections exceeded: #{current_connections} > #{@max_connections}",
        monitor_name: name
      )
    end
  end

  def status
    {
      status: enabled? ? 'enabled' : 'disabled',
      thresholds: { max_connections: @max_connections },
      violations_detected: @violations
    }
  end

  def to_cli
    "#{name}: #{enabled? ? 'enabled' : 'disabled'} (max: #{@max_connections})"
  end
end

# Register the custom monitor
Anzen.register_monitor(DatabaseConnectionMonitor.new(max_connections: 50))
Anzen.enable('database_connections')
```

## Performance Considerations

- **Sampling Intervals**: Memory monitor uses sampling to reduce overhead
- **Selective Enabling**: Only enable monitors you need
- **Check Frequency**: Call `check!` strategically, not on every operation
- **Error Handling**: Use rescue blocks to handle violations gracefully

## Thread Safety

Anzen is designed to be thread-safe:
- Monitor state is protected with mutexes
- Status queries are atomic
- Configuration is immutable after setup

## Version Compatibility

- **Ruby**: 3.0+
- **Platforms**: Linux, macOS, Windows (with limitations)
- **Dependencies**: Zero external runtime dependencies</content>
<parameter name="filePath">/Users/korakot-air/dev/anzen/lib/anzen/README_API.md

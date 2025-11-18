# Anzen

**Runtime Safety Protection for Ruby Applications**

Anzen prevents catastrophic crashes from recursive call stacks and memory overflow conditions. Deploy with confidence knowing your Ruby applications (Rails, microservices, background jobs) are protected from common runtime failures that can bring down production systems.

**Key Benefits:**
- 🚀 **Zero Code Changes**: Drop-in protection with single initialization
- 🔧 **Enterprise Ready**: Production-tested safety monitoring
- 📊 **Observable**: CLI tools for status monitoring and debugging
- 🧩 **Extensible**: Built-in monitors + custom safety checks
- ⚡ **Low Overhead**: Sampling-based monitoring with minimal performance impact
- 🔄 **Real-Time Protection**: Automatic interception without manual checks

## Installation

Add Anzen to your Gemfile:

```ruby
gem 'anzen', '~> 0.1.0'
```

Install the gem:

```bash
bundle install
```

## Quick Start

### Basic Setup (Initializer Pattern)

```ruby
# config/initializers/anzen.rb (Rails)
# or lib/anzen.rb (standalone)

require 'anzen'

Anzen.setup(
  config: {
    enabled_monitors: ['recursion', 'memory'],
    monitors: {
      recursion: { depth_limit: 1000 },
      memory: { limit_mb: 512, sampling_interval_ms: 100 }
    }
  }
)

# Your application is now protected!
```

### Protection in Action

```ruby
def risky_algorithm(n)
  return n if n <= 1
  # Anzen automatically monitors and prevents excessive recursion and memory usage
  risky_algorithm(n - 1) + risky_algorithm(n - 2)
end

# Monitoring happens in real-time
begin
  result = risky_algorithm(50)  # Safe with Anzen's automatic protection
rescue Anzen::RecursionLimitExceeded => e
  puts "Recursion limit exceeded: #{e.current_depth} > #{e.threshold}"
  # Handle gracefully instead of crashing
rescue Anzen::MemoryLimitExceeded => e
  puts "Memory limit exceeded: #{e.current_memory_mb}MB > #{e.memory_limit_mb}MB"
  # Clean up and retry with smaller dataset
end
```

## Configuration

Anzen supports multiple configuration sources:

### Environment Variables

```bash
export ANZEN_CONFIG='{
  "enabled_monitors": ["recursion", "memory"],
  "monitors": {
    "recursion": {"depth_limit": 500},
    "memory": {"limit_mb": 1024}
  }
}'
```

### Configuration File

```yaml
# config/anzen.yml
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

### Programmatic Setup

```ruby
Anzen.setup(config: {
  enabled_monitors: ['recursion'],
  monitors: {
    recursion: { depth_limit: 500 }
  }
})
```

## CLI Commands

Anzen provides command-line tools for monitoring and debugging:

```bash
# Show protection status
anzen status

# View configuration
anzen config
anzen config memory --format json

# System information
anzen info

# Help and version
anzen help
anzen --version
```

### Example CLI Output

```bash
$ anzen status
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

## Integration Patterns

Anzen integrates cleanly with any Ruby application:

### Rails Applications
- **Initializer**: `config/initializers/anzen.rb`
- **Middleware**: Automatic request-level protection
- **Background Jobs**: Sidekiq/Resque job protection

### Rack Applications
- **Middleware**: `use Anzen::Middleware`
- **Config.ru**: Centralized setup

### Standalone Scripts
- **Direct Setup**: `Anzen.setup()` at script start
- **Error Handling**: Rescue `Anzen::ViolationError`

## API Reference

### Core Methods

```ruby
# Initialize protection
Anzen.setup(config: {...})

# Runtime control
Anzen.enable('recursion')
Anzen.disable('memory')

# Status and monitoring (optional - monitoring happens automatically)
status = Anzen.status
Anzen.check!  # Manual check if needed

# Custom monitors
Anzen.register_monitor(my_monitor)
```

### Exception Types

```ruby
begin
  Anzen.check!
rescue Anzen::RecursionLimitExceeded => e
  # Recursion violation
rescue Anzen::MemoryLimitExceeded => e
  # Memory violation
rescue Anzen::CheckFailedError => e
  # Infrastructure error
end
```

## Troubleshooting

### Common Issues

**"Anzen not initialized"**
- Ensure `Anzen.setup()` is called before using CLI or API
- Check that the gem is properly required

**High Memory Usage**
- Adjust `sampling_interval_ms` to reduce monitoring frequency
- Memory monitor only samples, doesn't cause overhead

**Recursion Detection Too Sensitive**
- Increase `depth_limit` for applications with deep call stacks
- Recursion monitor tracks all method calls including framework code

**CLI Commands Not Found**
- Ensure `bin/anzen` is in PATH or use `bundle exec anzen`
- Check that the gem is installed: `gem list anzen`

### Debug Mode

Enable verbose logging:

```ruby
Anzen.setup(config: {
  # ... normal config ...
  debug: true  # Future enhancement
})
```

### Performance Tuning

```ruby
# Reduce monitoring overhead
Anzen.setup(config: {
  enabled_monitors: ['recursion'],  # Only enable needed monitors
  monitors: {
    memory: {
      sampling_interval_ms: 500  # Check less frequently
    }
  }
})
```

## Development

### Prerequisites

- Ruby 3.0+
- Bundler

### Setup

```bash
git clone https://github.com/korakotlee/anzen
cd anzen
bin/setup
```

### Testing

```bash
# Run all tests
bundle exec rspec

# Run with coverage
bundle exec rspec --coverage

# Run specific test
bundle exec rspec spec/unit/cli_spec.rb
```

### Code Quality

```bash
# Lint code
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a

# Run all checks
bundle exec rake
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Write tests for your changes
4. Ensure all tests pass: `bundle exec rspec`
5. Check code quality: `bundle exec rubocop`
6. Submit a pull request

### Development Guidelines

- **Test-First**: Write specs before implementation
- **Code Quality**: RuboCop strict compliance required
- **Documentation**: Update docs for public API changes
- **Backwards Compatibility**: Maintain API stability

## License

Copyright (c) 2025 Korakot Lee. Released under the MIT License. See [LICENSE](./LICENSE) for details.

## Code of Conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md). We are committed to providing a welcoming and inclusive environment for all contributors.

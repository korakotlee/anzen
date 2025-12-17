# Anzen

**Runtime Safety Protection for Ruby Applications**

A large codebase is like a giant Boeing 737 Max. You have unit tests and integration tests, but when the production run is in-flight and everyone clearly sees it losing altitude fast without any intention of landing, something is wrong. The captain should be alerted, and the system should self-correct right away.

Anzen acts as that automated safety system. It checks for anomalies during runtime, monitors system integrity, and activates self-healing mechanisms to prevent catastrophic crashes from recursive call stacks and memory overflow conditions. Deploy with confidence knowing your Ruby applications (Rails, microservices, background jobs) are protected from common runtime failures that can bring down production systems.

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

## Protection in Action

See Rails example in [Rails test](doc/rails_test.md)

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

## Fun Fact

Anzen mean `safety` in Japanese

## License

Copyright (c) 2025 Korakot Leemakdej. Released under the MIT License. See [LICENSE](./LICENSE) for details.

## Code of Conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md). We are committed to providing a welcoming and inclusive environment for all contributors.

# Anzen

**Runtime safety protection gem for Ruby applications**

Anzen detects recursive call stacks and memory overflow conditions before they crash your application. Protect enterprise Ruby applications with zero code pollution using configurable monitors and clean integration patterns.

## Features

- **Recursion Detection**: Detects recursive call stacks including indirect recursion (A→B→C→A)
- **Memory Overflow Detection**: Samples process memory and alerts before OOM conditions
- **Framework-Agnostic**: Works with any Ruby code (Rails, microservices, standalone scripts)
- **Modular Architecture**: Built-in monitors + extensible plugin system for custom checks
- **Zero Code Pollution**: Single initialization point (initializer/middleware/config file)
- **CLI Tools**: Monitor status, view configuration, system information
- **Production Ready**: Minimal overhead, sampling-based, process-wide monitoring

## Installation

Add to your Gemfile:

```ruby
gem "anzen"
```

Then run:

```bash
bundle install
```

## Quick Start

### Rails Initializer

```ruby
# config/initializers/anzen.rb
require "anzen"

Anzen.setup do |config|
  config.enable :recursion, threshold: 500
  config.enable :memory, threshold: 1024  # MB
end
```

### Middleware (Rack/Rails)

```ruby
# config/application.rb
config.middleware.use Anzen::Middleware
```

### Standalone Ruby

```ruby
require "anzen"

Anzen.setup do |config|
  config.enable :recursion, threshold: 100
end

# Your code now protected automatically
begin
  recursive_function(0)
rescue Anzen::ViolationError => e
  puts "Safety violation detected: #{e.message}"
end
```

## Configuration

See [quickstart.md](./specs/001-safety-protection/quickstart.md) for complete integration patterns and examples.

## Development

After checking out the repo, run `bin/setup` to install dependencies.

### Running Tests

```bash
bundle exec rspec
```

### Running Linter

```bash
bundle exec rubocop
```

### Running All Checks

```bash
bundle exec rake
```

### Interactive Console

```bash
bin/console
```

## Documentation

- **API Documentation**: See [ruby_api.md](./specs/001-safety-protection/contracts/ruby_api.md)
- **CLI Reference**: See [cli_commands.md](./specs/001-safety-protection/contracts/cli_commands.md)
- **Exception Types**: See [exceptions.md](./specs/001-safety-protection/contracts/exceptions.md)
- **Integration Guide**: See [quickstart.md](./specs/001-safety-protection/quickstart.md)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/korakotlee/anzen. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](./CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Anzen project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](./CODE_OF_CONDUCT.md).

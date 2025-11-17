# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.0] - 2025-11-17

### Added
- Initial gem structure and scaffolding
- Monitor interface and base classes for extensible safety monitoring
- Recursion detection monitor with call stack depth and pattern-based detection
- Memory overflow detection monitor with configurable thresholds and sampling
- Modular registry system for monitor lifecycle management
- CLI tools (status, config, info, help) for operator monitoring and debugging
- Configuration management supporting programmatic, environment variable, and file-based setup
- Comprehensive exception hierarchy with specific violation and infrastructure errors
- Integration patterns for Rails initializers, Rack middleware, and standalone applications
- Complete RSpec test suite with 80%+ coverage minimum and integration tests
- RuboCop linting with strict mode compliance
- GitHub Actions CI/CD workflows for automated testing and linting
- Comprehensive YARD documentation for all public APIs
- Production-ready error handling and graceful degradation patterns

### Changed

### Deprecated

### Removed

### Fixed

### Security

[Unreleased]: https://github.com/korakotlee/anzen/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/korakotlee/anzen/releases/tag/v0.1.0

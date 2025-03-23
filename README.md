# Dotfiles Manager

A flexible and powerful dotfiles management system that supports templating, host-specific configurations, and package-based organization.

## Features

- Template-based configuration files with variable substitution
- Host-specific package overrides
- Package-based organization of dotfiles
- Dry-run mode for safe testing
- Support for multiple package selection
- Built on GNU Stow for reliable symlink management

## Prerequisites

- GNU Stow
- BATS (Bash Automated Testing System) - for running tests
- Light-weight shell templating engine (https://github.com/arcaartem/template)

### Installation

```bash
# On macOS with Homebrew
brew install stow bats

# On Ubuntu/Debian
sudo apt-get install stow bats
```

## Usage

### Basic Commands

```bash
# Build packages (render templates) to ./tmp/build
./manage.sh build

# Render packages directly to dotfiles directory
./manage.sh render

# Preview changes (dry-run)
./manage.sh stow

# Apply changes
./manage.sh stow --apply

# Remove symlinks (dry-run)
./manage.sh unstow

# Remove and reapply symlinks (dry-run)
./manage.sh restow
```

### Package Selection

```bash
# Process all available packages
./manage.sh stow --apply

# Process a single package
./manage.sh stow --apply my-package

# Process multiple packages
./manage.sh stow --apply package1 package2
```

### Host-Specific Configuration

```bash
# Use host-specific packages and config
./manage.sh stow --apply -H my-hostname
```

## Directory Structure

```
.
├── config/                    # Configuration files
│   ├── defaults              # Default template variables
│   └── hostname.conf         # Host-specific template variables
├── packages/
│   ├── common/               # Common packages
│   │   └── package-name/     # Package contents
│   └── host-specific/        # Host-specific packages
│       └── hostname/         # Host-specific overrides
│           └── package-name/ # Override contents
└── src/
    ├── manage.sh            # Main script
    └── template.sh          # Template processing script
```

## Template Syntax

Templates support variable substitution using `${VARIABLE}` syntax:

```bash
# Example template file
export PATH="${HOME}/.local/bin:${PATH}"
```

Variables can be defined in:
- `config/defaults` - Default values
- `config/hostname.conf` - Host-specific values

## Development

### Running Tests

```bash
# Run all tests
bats test/manage.bats

# Run specific test
bats test/manage.bats -f "test name"
```

### Adding New Tests

Tests are written using BATS. See the existing tests in `test/manage.bats` for examples.

### Adding New Packages

1. Create a new directory under `packages/common/`
2. Add your dotfiles
3. Use templates with `${VARIABLE}` syntax as needed
4. Add host-specific overrides in `packages/host-specific/hostname/` if needed

## License

MIT License 
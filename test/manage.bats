#!/usr/bin/env bats

setup() {
    # Create temporary test directories
    TEST_DIR="$(mktemp -d)"
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    
    # Copy the scripts to the test directory
    cp "$SCRIPT_DIR/src/manage.sh" "$TEST_DIR/"
    cp "$SCRIPT_DIR/src/template.sh" "$TEST_DIR/"
    
    # Create test package structure
    mkdir -p "$TEST_DIR/packages/common/test-package"
    mkdir -p "$TEST_DIR/packages/common/another-package"
    mkdir -p "$TEST_DIR/packages/host-specific/example-host/test-package"
    mkdir -p "$TEST_DIR/config"
    
    # Create test files for first package
    echo "common content" > "$TEST_DIR/packages/common/test-package/test.txt"
    echo "host specific content" > "$TEST_DIR/packages/host-specific/example-host/test-package/test.txt"
    
    # Create test files for second package
    echo "another package content" > "$TEST_DIR/packages/common/another-package/another.txt"
    
    # Create template files
    echo "template content with variable: \${TEST_VAR}" > "$TEST_DIR/packages/common/test-package/test.tmpl"
    echo "template content with variable: \${TEST_VAR}" > "$TEST_DIR/packages/host-specific/example-host/test-package/test.tmpl"
    
    # Create config files
    echo "TEST_VAR=test_value" > "$TEST_DIR/config/defaults"
    echo "TEST_VAR=host_specific_value" > "$TEST_DIR/config/example-host.conf"
    
    # Make scripts executable
    chmod +x "$TEST_DIR/manage.sh"
    chmod +x "$TEST_DIR/template.sh"
    
    # Set up test environment
    export XDG_DATA_HOME="$TEST_DIR/.local/share"
    export HOME="$TEST_DIR/home"
    mkdir -p "$HOME"
    
    # Change to test directory
    cd "$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "renders templated and regular packages to target directory" {
    run ./manage.sh build
    
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/tmp/build/test-package/test.txt" ]
    [ -f "$TEST_DIR/tmp/build/test-package/test" ]
    [ "$(cat "$TEST_DIR/tmp/build/test-package/test")" = "template content with variable: test_value" ]
}

@test "stows common package to home directory" {
    # First build and stow
    ./manage.sh stow --apply
    
    [ -L "$HOME/test.txt" ]
    [ "$(readlink -f "$HOME/test.txt")" = "$(readlink -f "$XDG_DATA_HOME/dotfiles/test-package/test.txt")" ]
    [ "$(cat "$HOME/test.txt")" = "common content" ]
}

@test "stows host specific package when available" {
    # Set hostname for testing
    export HOSTNAME="example-host"
    
    # Build and stow with explicit hostname
    ./manage.sh stow --apply -H example-host
    
    [ -L "$HOME/test.txt" ]
    [ "$(readlink -f "$HOME/test.txt")" = "$(readlink -f "$XDG_DATA_HOME/dotfiles/test-package/test.txt")" ]
    [ "$(cat "$HOME/test.txt")" = "host specific content" ]
}

@test "prefers host specific package over common package" {
    # Set hostname for testing
    export HOSTNAME="example-host"
    
    # Build and stow with explicit hostname
    ./manage.sh stow --apply -H example-host
    
    [ -L "$HOME/test.txt" ]
    [ "$(readlink -f "$HOME/test.txt")" = "$(readlink -f "$XDG_DATA_HOME/dotfiles/test-package/test.txt")" ]
    [ "$(cat "$HOME/test.txt")" = "host specific content" ]
}

@test "uses host specific config values for templates" {
    # Set hostname for testing
    export HOSTNAME="example-host"
    
    # Build and stow with explicit hostname
    ./manage.sh stow --apply -H example-host
    
    [ -L "$HOME/test" ]
    [ "$(readlink -f "$HOME/test")" = "$(readlink -f "$XDG_DATA_HOME/dotfiles/test-package/test")" ]
    [ "$(cat "$HOME/test")" = "template content with variable: host_specific_value" ]
}

@test "installs all available packages when none specified" {
    # Build and stow all packages
    ./manage.sh stow --apply
    
    # Check first package
    [ -L "$HOME/test.txt" ]
    [ "$(readlink -f "$HOME/test.txt")" = "$(readlink -f "$XDG_DATA_HOME/dotfiles/test-package/test.txt")" ]
    [ "$(cat "$HOME/test.txt")" = "common content" ]
    
    # Check second package
    [ -L "$HOME/another.txt" ]
    [ "$(readlink -f "$HOME/another.txt")" = "$(readlink -f "$XDG_DATA_HOME/dotfiles/another-package/another.txt")" ]
    [ "$(cat "$HOME/another.txt")" = "another package content" ]
}

@test "installs only specified package" {
    # Build and stow only test-package
    ./manage.sh stow --apply test-package
    
    # Check specified package is installed
    [ -L "$HOME/test.txt" ]
    [ "$(readlink -f "$HOME/test.txt")" = "$(readlink -f "$XDG_DATA_HOME/dotfiles/test-package/test.txt")" ]
    [ "$(cat "$HOME/test.txt")" = "common content" ]
    
    # Check other package is not installed
    [ ! -L "$HOME/another.txt" ]
}

@test "installs multiple specified packages" {
    # Build and stow multiple packages
    ./manage.sh stow --apply test-package another-package
    
    # Check first package
    [ -L "$HOME/test.txt" ]
    [ "$(readlink -f "$HOME/test.txt")" = "$(readlink -f "$XDG_DATA_HOME/dotfiles/test-package/test.txt")" ]
    [ "$(cat "$HOME/test.txt")" = "common content" ]
    
    # Check second package
    [ -L "$HOME/another.txt" ]
    [ "$(readlink -f "$HOME/another.txt")" = "$(readlink -f "$XDG_DATA_HOME/dotfiles/another-package/another.txt")" ]
    [ "$(cat "$HOME/another.txt")" = "another package content" ]
} 
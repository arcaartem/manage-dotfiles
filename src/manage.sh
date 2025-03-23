#!/bin/sh

# Strict error handling
set -e

# Default values
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/tmp/build"
DOTFILES_DIR="$XDG_DATA_HOME/dotfiles"
CONFIG_DIR="$SCRIPT_DIR/config"
DEFAULT_CONFIG="$CONFIG_DIR/defaults"
TEMPLATE_SCRIPT="$SCRIPT_DIR/template.sh"

# Parse command line arguments
HOSTNAME_OVERRIDE=""
PACKAGES=""
TARGET_DIR="$BUILD_DIR"
DRY_RUN=true

# Logging functions
log_info() {
    echo "INFO: $1"
}

log_error() {
    echo "ERROR: $1" >&2
}

log_success() {
    echo "SUCCESS: $1"
}

# Load template variables
load_template_vars() {
    vars=""
    
    # Load default variables if they exist
    if [ -f "$DEFAULT_CONFIG" ]; then
        while IFS='=' read -r key value; do
            [ -n "$key" ] && vars="$vars \"$key=$value\""
        done < "$DEFAULT_CONFIG"
    fi

    # Override with host-specific variables if they exist
    if [ -f "$HOST_CONFIG" ]; then
        while IFS='=' read -r key value; do
            [ -n "$key" ] && vars="$vars \"$key=$value\""
        done < "$HOST_CONFIG"
    fi

    echo "$vars"
}

# Process a single file
process_file() {
    src_file="$1"
    target_path="$2"
    vars="$3"

    # Create target directory if needed
    mkdir -p "$(dirname "$target_path")"

    # Check if this is a template file
    if echo "$src_file" | grep -q "\.tmpl$"; then
        log_info "Processing template: $src_file"
        # Remove .tmpl extension for target
        target_path="${target_path%.tmpl}"
        
        # Process template
        eval "sh \"$TEMPLATE_SCRIPT\" \"$src_file\" $vars" > "$target_path"
    else
        log_info "Copying file: $src_file"
        cp "$src_file" "$target_path"
    fi
}

# Process a single package
process_package() {
    package="$1"
    package_dir="$2"
    target_dir="$TARGET_DIR/$package"

    [ -d "$package_dir" ] || { log_error "Package directory not found: $package_dir"; return 1; }
    mkdir -p "$target_dir"

    # Load template variables once for all files
    vars="$(load_template_vars)"

    # Process each file in the package directory
    find "$package_dir" -type f -print | while read -r src_file; do
        # Get relative path from package directory
        rel_path="${src_file#$package_dir/}"
        target_path="$target_dir/$rel_path"
        process_file "$src_file" "$target_path" "$vars"
    done
}

# Process a single package name, preferring host-specific version
process_package_name() {
    package="$1"
    
    log_info "Checking for host-specific package: $package in $HOST_PACKAGES"
    # Check for host-specific package first
    if [ -d "$HOST_PACKAGES/$package" ]; then
        log_info "Found host-specific package: $package"
        process_package "$package" "$HOST_PACKAGES/$package"
    # Fall back to common package if no host-specific version exists
    elif [ -d "$COMMON_PACKAGES/$package" ]; then
        log_info "Using common package: $package"
        process_package "$package" "$COMMON_PACKAGES/$package"
    else
        log_error "Package not found: $package"
    fi
}

# Process all packages
process_all_packages() {
    # First process all host-specific packages
    if [ -d "$HOST_PACKAGES" ]; then
        for package_dir in "$HOST_PACKAGES"/*; do
            [ -d "$package_dir" ] || continue
            package="${package_dir##*/}"
            log_info "Processing host-specific package: $package"
            process_package "$package" "$package_dir"
        done
    fi

    # Then process common packages that don't have host-specific versions
    for package_dir in "$COMMON_PACKAGES"/*; do
        [ -d "$package_dir" ] || continue
        package="${package_dir##*/}"
        # Skip if there's a host-specific version
        [ -d "$HOST_PACKAGES/$package" ] && continue
        log_info "Processing common package: $package"
        process_package "$package" "$package_dir"
    done
}

# Execute stow command
execute_stow() {
    operation="$1"
    stow_args="$2"
    target_dir="$3"
    message="$4"

    log_info "$message"
    cd "$target_dir" || { log_error "Failed to change to directory: $target_dir"; return 1; }
    
    if [ -z "$PACKAGES" ]; then
        # If no packages specified, process all packages
        for package in *; do
            [ -d "$package" ] || continue
            log_info "$operation package: $package"
            if [ "$DRY_RUN" = true ]; then
                stow --dotfiles -v -n $stow_args -t "$HOME" "$package"
            else
                stow --dotfiles -v $stow_args -t "$HOME" "$package"
            fi
        done
    else
        # Process only specified packages
        for package in $PACKAGES; do
            if [ ! -d "$package" ]; then
                log_error "Package not found: $package"
                continue
            fi
            log_info "$operation package: $package"
            if [ "$DRY_RUN" = true ]; then
                stow --dotfiles -v -n $stow_args -t "$HOME" "$package"
            else
                stow --dotfiles -v $stow_args -t "$HOME" "$package"
            fi
        done
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "Dry run completed. Use --apply to actually $message."
    else
        log_success "$message completed successfully"
    fi
}

usage() {
    cat << EOF
Usage: $0 COMMAND [OPTIONS] [PACKAGES...]

Commands:
    build              Render templates to ./tmp/build directory
    stow              Apply changes using stow (dry-run by default)
    unstow            Remove stow symlinks (dry-run by default)
    restow            Remove and reapply stow symlinks (dry-run by default)
    help              Show this help message

Options:
    -H, --hostname HOST     Override hostname (default: $(hostname))
    --apply               Actually apply stow commands (default: dry-run)
    
If no packages are specified, all packages will be processed.
EOF
    exit 1
}

# Require at least one argument
if [ $# -eq 0 ]; then
    usage
fi

# Parse command
COMMAND="$1"
shift

# Parse remaining arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -H|--hostname)
            shift
            HOSTNAME_OVERRIDE="$1"
            shift
            ;;
        --apply)
            DRY_RUN=false
            shift
            ;;
        *)
            # Store package names in an array-like string with a delimiter
            if [ -z "$PACKAGES" ]; then
                PACKAGES="$1"
            else
                PACKAGES="$PACKAGES $1"
            fi
            shift
            ;;
    esac
done

# Set hostname and package directories early
if [ -n "$HOSTNAME_OVERRIDE" ]; then
    HOSTNAME="$HOSTNAME_OVERRIDE"
else
    HOSTNAME="$(hostname)"
fi

log_info "Using hostname: $HOSTNAME"
HOST_CONFIG="$CONFIG_DIR/$HOSTNAME.conf"
COMMON_PACKAGES="$SCRIPT_DIR/packages/common"
HOST_PACKAGES="$SCRIPT_DIR/packages/host-specific/$HOSTNAME"

log_info "Host config: $HOST_CONFIG"
log_info "Common packages directory: $COMMON_PACKAGES"
log_info "Host packages directory: $HOST_PACKAGES"

# Create necessary directories
mkdir -p "$TARGET_DIR"

# Process packages based on command
case "$COMMAND" in
    build)
        # For build command, use BUILD_DIR
        TARGET_DIR="$BUILD_DIR"
        if [ -z "$PACKAGES" ]; then
            process_all_packages
        else
            # Process each package
            for package in $PACKAGES; do
                process_package_name "$package"
            done
        fi
        log_success "Build completed. Files were rendered to: $TARGET_DIR"
        ;;
    stow)
        log_info "Preparing files for stow..."
        # For stow command, use DOTFILES_DIR
        TARGET_DIR="$DOTFILES_DIR"
        mkdir -p "$TARGET_DIR"
        
        # Process packages again to DOTFILES_DIR
        if [ -z "$PACKAGES" ]; then
            process_all_packages
        else
            # Process each package
            for package in $PACKAGES; do
                process_package_name "$package"
            done
        fi

        execute_stow "Stowing" "" "$DOTFILES_DIR" "Applying changes using stow"
        ;;
    unstow)
        execute_stow "Unstowing" "-D" "$DOTFILES_DIR" "Removing stow symlinks"
        ;;
    restow)
        execute_stow "Restowing" "-R" "$DOTFILES_DIR" "Restowing packages"
        ;;
    help)
        usage
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        ;;
esac 

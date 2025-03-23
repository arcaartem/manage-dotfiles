#!/bin/sh

# Configuration
set -e
INCLUDE_PREFIX="@include"
IF_PREFIX="@if"
ENDIF_TOKEN="@endif"
ELSE_TOKEN="@else"

# Error handling
die() {
    echo "Error: $1" >&2
    exit 1
}

show_usage() {
    echo "Usage: $0 template_file [var1=value1 var2=value2 ...]"
    exit 1
}

# Variable handling
process_variables() {
    for arg in "$@"; do
        case "$arg" in
            *=*) eval "export $arg" ;;
        esac
    done
}

# String manipulation utilities
trim() {
    trim_str="$1"
    trim_str="${trim_str#"${trim_str%%[![:space:]]*}"}"  # trim leading
    trim_str="${trim_str%"${trim_str##*[![:space:]]}"}"  # trim trailing
    printf '%s' "$trim_str"
}

starts_with() {
    case "$1" in
        "$2"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Template processing functions
process_subshell() {
    process_subshell_cmd="$1"
    eval "$process_subshell_cmd"
}

process_variable() {
    process_variable_name="$1"
    eval "printf '%s' \"\$$process_variable_name\""
}

expand_vars() {
    expand_vars_line="$1"
    expand_vars_result=""
    expand_vars_in_var=0
    expand_vars_in_subshell=0
    expand_vars_var_name=""
    expand_vars_subshell_cmd=""
    
    while [ -n "$expand_vars_line" ]; do
        case "$expand_vars_line" in
            '$('*)
                expand_vars_in_subshell=1
                expand_vars_subshell_cmd=""
                expand_vars_line="${expand_vars_line#\$\(}"
                ;;
            ')'*)
                if [ $expand_vars_in_subshell -eq 1 ]; then
                    expand_vars_in_subshell=0
                    expand_vars_result="$expand_vars_result$(process_subshell "$expand_vars_subshell_cmd")"
                    expand_vars_line="${expand_vars_line#\)}"
                fi
                ;;
            '${'*)
                if [ $expand_vars_in_subshell -eq 0 ]; then
                    expand_vars_in_var=1
                    expand_vars_var_name=""
                    expand_vars_line="${expand_vars_line#\$\{}"
                fi
                ;;
            '}'*)
                if [ $expand_vars_in_subshell -eq 0 ] && [ $expand_vars_in_var -eq 1 ]; then
                    expand_vars_in_var=0
                    expand_vars_result="$expand_vars_result$(process_variable "$expand_vars_var_name")"
                    expand_vars_line="${expand_vars_line#\}}"
                fi
                ;;
            *)
                if [ $expand_vars_in_var -eq 1 ]; then
                    expand_vars_var_name="$expand_vars_var_name${expand_vars_line%"${expand_vars_line#?}"}"
                elif [ $expand_vars_in_subshell -eq 1 ]; then
                    expand_vars_subshell_cmd="$expand_vars_subshell_cmd${expand_vars_line%"${expand_vars_line#?}"}"
                else
                    expand_vars_result="$expand_vars_result${expand_vars_line%"${expand_vars_line#?}"}"
                fi
                expand_vars_line="${expand_vars_line#?}"
                ;;
        esac
    done
    
    printf '%s\n' "$expand_vars_result"
}

process_include() {
    process_include_file="$1"
    process_include_current_dir="$(dirname "$current_template")"
    process_include_full_path="$process_include_current_dir/$process_include_file"
    [ -f "$process_include_full_path" ] || { echo "Warning: Include file '$process_include_full_path' not found" >&2; return 1; }
    process_template "$process_include_full_path"
}

process_conditional() {
    process_conditional_condition="$1"
    eval "$process_conditional_condition"
}

# Initialize condition stack array (using a delimiter that won't appear in conditions)
init_stacks() {
    CONDITION_DEPTH=0
    CONDITION_STATES=""
    ELSE_STATES=""
}

push_condition() {
    CONDITION_DEPTH=$((CONDITION_DEPTH + 1))
    CONDITION_STATES="$CONDITION_STATES|$1"
    ELSE_STATES="$ELSE_STATES|$2"
}

pop_condition() {
    [ "$CONDITION_DEPTH" -gt 0 ] || return
    CONDITION_DEPTH=$((CONDITION_DEPTH - 1))
    CONDITION_STATES="${CONDITION_STATES%|*}"
    ELSE_STATES="${ELSE_STATES%|*}"
}

get_current_state() {
    if [ "$CONDITION_DEPTH" -eq 0 ]; then
        echo "true"
        return
    fi
    current="${CONDITION_STATES##*|}"
    echo "$current"
}

should_process_line() {
    # Check all parent conditions
    remaining_states="$CONDITION_STATES"
    while [ -n "$remaining_states" ]; do
        current="${remaining_states##*|}"
        if [ "$current" = "false" ]; then
            echo "false"
            return
        fi
        remaining_states="${remaining_states%|*}"
    done
    echo "true"
}

process_line() {
    process_line_line="$1"
    
    # Handle includes
    if starts_with "$process_line_line" "$INCLUDE_PREFIX "; then
        process_line_include_file=$(trim "${process_line_line#$INCLUDE_PREFIX }")
        if [ "$(should_process_line)" = "true" ]; then
            process_include "$process_line_include_file"
        fi
        return
    fi

    # Handle conditionals
    if starts_with "$process_line_line" "$IF_PREFIX "; then
        process_line_condition="${process_line_line#$IF_PREFIX }"
        if [ "$(should_process_line)" = "true" ]; then
            if process_conditional "$process_line_condition"; then
                push_condition "true" "false"
            else
                push_condition "false" "false"
            fi
        else
            # Parent condition is false, just push false
            push_condition "false" "false"
        fi
        return
    fi

    if [ "$process_line_line" = "$ELSE_TOKEN" ]; then
        if [ "$CONDITION_DEPTH" -gt 0 ]; then
            current_state="${CONDITION_STATES##*|}"
            current_else="${ELSE_STATES##*|}"
            parent_states="${CONDITION_STATES%|*}"
            
            # Only process else if we haven't seen it before and parent conditions are true
            if [ "$current_else" = "false" ]; then
                pop_condition
                if [ -z "$parent_states" ] || [ "$(should_process_line)" = "true" ]; then
                    if [ "$current_state" = "true" ]; then
                        push_condition "false" "true"
                    else
                        push_condition "true" "true"
                    fi
                else
                    push_condition "false" "true"
                fi
            fi
        fi
        return
    fi

    if [ "$process_line_line" = "$ENDIF_TOKEN" ]; then
        pop_condition
        return
    fi

    # Process normal line
    if [ "$(should_process_line)" = "true" ]; then
        expand_vars "$process_line_line"
    fi
}

process_template() {
    process_template_file="$1"
    current_template="$process_template_file"
    IFS=''
    
    # Initialize condition tracking
    init_stacks
    
    while read -r line || [ -n "$line" ]; do
        process_line "$line"
    done < "$process_template_file"
}

main() {
    # Argument validation
    [ $# -ge 1 ] || show_usage
    main_template_file="$1"
    shift
    [ -f "$main_template_file" ] || die "Template file not found: $main_template_file"

    # Initialize state
    continue_processing=true

    # Process command line variables
    process_variables "$@"

    # Process the template
    process_template "$main_template_file"
}

main "$@" 

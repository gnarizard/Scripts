#!/bin/bash

# ================================================
# Description: Automates Nmap port scanning process.
# ================================================

# Function to validate IPv4 address format
validate_ip() {
    local ip=$1
    # Regular expression for IPv4 validation
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"

    if [[ $ip =~ $regex ]]; then
        # Split IP into octets and verify each is <= 255
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if (( octet < 0 || octet > 255 )); then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to check if nmap is installed
check_dependencies() {
    if ! command -v nmap &> /dev/null; then
        echo "Error: nmap is not installed. Please install it and try again."
        exit 1
    fi
}

# Function to perform initial port scan
initial_scan() {
    local target=$1
    echo "Scanning for open ports on $target..."
    
    # Run Nmap to scan all ports with high speed
    ports=$(nmap -p- --min-rate=1000 -T5 "$target" | \
            grep '^[0-9]' | \
            cut -d '/' -f1 | \
            tr '\n' ',' | \
            sed 's/,$//')

    if [[ -z "$ports" ]]; then
        echo "No open ports found or failed to retrieve ports."
        exit 1
    fi

    echo "Open ports found: $ports"
}

# Function to perform detailed scan on discovered ports
detailed_scan() {
    local target=$1
    local ports=$2
    local output_path=$3
    echo "Performing scan on ports: $ports"

    # Run detailed Nmap scan with service detection and default scripts
    nmap -p"$ports" -sC -sV -oN "$output_path" -T5 -v "$target"

    echo "Scan completed. Results saved to $output_path"
}

# Main script execution starts here

# Check for dependencies
check_dependencies

# Prompt user for target IP address
read -rp "Enter the target IP address: " target_ip

# Validate the entered IP address
if ! validate_ip "$target_ip"; then
    echo "Error: Invalid IP address format. Please enter a valid IPv4 address."
    exit 1
fi

# Prompt user for the directory to save scan.txt
read -rp "Enter the directory to save the scan results (e.g., /path/to/directory): " output_dir

# Validate the directory path
if [[ ! -d "$output_dir" ]]; then
    echo "Error: The directory '$output_dir' does not exist."
    exit 1
fi

# Define the full path for scan.txt within the provided directory
output_path="$output_dir/scan.txt"

# Perform initial port scan
initial_scan "$target_ip"

# Extract ports from the initial scan
# (Reusing the 'ports' variable from initial_scan function)
# To make 'ports' accessible outside the function, declare it globally
ports=$(nmap -p- --min-rate=1000 -T5 "$target_ip" | \
        grep '^[0-9]' | \
        cut -d '/' -f1 | \
        tr '\n' ',' | \
        sed 's/,$//')

# Perform detailed scan on discovered ports
detailed_scan "$target_ip" "$ports" "$output_path"

# End of script

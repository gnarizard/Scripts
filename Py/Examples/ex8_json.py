#!/usr/bin/env python3  # Shebang allows the script to be run directly (./script.py) on Unix-like systems.

# Use venv to isolate dependencies for this script:
# python3 -m venv myenv
# source myenv/bin/activate
# pip install --upgrade pip

# Output Example
# 1. Writing Configuration to JSON:
# Configuration saved to config.json

# 2. Reading Configuration from JSON:
# Configuration loaded:
# {
#     "user": "Gnar",
#     "role": "Cybersecurity"
# }

# 3. Handling Environment Variables:
# --- Environment Variable Handling ---
# USER environment variable: gnar
# MY_CUSTOM_VAR set to: CustomValue

import json  # For handling JSON configuration files
import os    # For accessing environment variables

# File paths
CONFIG_FILE = "config.json"

# Function to write configuration to a JSON file
def write_config(user, role):
    config = {"user": user, "role": role}
    with open(CONFIG_FILE, "w") as file:
        json.dump(config, file, indent=4)  # Write JSON with indentation for readability
    print(f"Configuration saved to {CONFIG_FILE}")

# Function to read configuration from a JSON file
def read_config():
    if not os.path.exists(CONFIG_FILE):
        print(f"Configuration file '{CONFIG_FILE}' not found.")
        return None
    with open(CONFIG_FILE, "r") as file:
        config = json.load(file)  # Load JSON data as a dictionary
    print("Configuration loaded:")
    print(json.dumps(config, indent=4))  # Pretty-print JSON
    return config

# Function to demonstrate environment variable usage
def handle_environment():
    print("\n--- Environment Variable Handling ---")
    # Get an environment variable (returns None if not set)
    user_var = os.getenv("USER", "DefaultUser")
    print(f"USER environment variable: {user_var}")

    # Set a custom environment variable
    os.environ["MY_CUSTOM_VAR"] = "CustomValue"
    print(f"MY_CUSTOM_VAR set to: {os.environ['MY_CUSTOM_VAR']}")

if __name__ == "__main__":
    # Write and read configuration
    write_config(user="Ryan", role="Cybersecurity")
    read_config()

    # Handle environment variables
    handle_environment()

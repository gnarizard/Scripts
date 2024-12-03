# Input:
# python sys_example.py hello world

# Output:
# Python Version: 3.10.6 (main, Oct 3 2022, 16:56:58) [GCC 11.2.0]
# Command-line arguments received:
# Argument 0: sys_example.py
# Argument 1: hello
# Argument 2: world
# Script executed successfully.


# Access command-line arguments or control Python’s runtime environment.
import sys

def main():
    # Display Python version
    print(f"Python Version: {sys.version}")

    # Check if any arguments are provided
    if len(sys.argv) > 1:
        print("Command-line arguments received:")
        for index, arg in enumerate(sys.argv):
            print(f"Argument {index}: {arg}")
    else:
        print("No command-line arguments were provided.")
    
    # Simulate an error condition
    if len(sys.argv) == 2 and sys.argv[1] == "--exit":
        print("Exiting the script based on user request.")
        sys.exit(0)  # Exit script with code 0 (success)
    elif len(sys.argv) == 2 and sys.argv[1] == "--error":
        print("Simulating an error condition.")
        sys.exit(1)  # Exit script with code 1 (error)

    # Default message if no special argument is passed
    print("Script executed successfully.")

if __name__ == "__main__":
    main()

# Sample Output
# Raw Output:
# Active Connections

#   Proto  Local Address          Foreign Address        State
#   TCP    0.0.0.0:80             0.0.0.0:0              LISTENING
#   TCP    127.0.0.1:3306         0.0.0.0:0              LISTENING
#   TCP    192.168.1.10:5000      192.168.1.15:52345     ESTABLISHED
# Filtered Open Ports:
#   TCP    0.0.0.0:80             0.0.0.0:0              LISTENING
#   TCP    127.0.0.1:3306         0.0.0.0:0              LISTENING
#   TCP    192.168.1.10:5000      192.168.1.15:52345     ESTABLISHED

# A more robust way to run shell commands and capture their output.
import subprocess

def scan_open_ports():
    print("Scanning for open network ports...")
    
    # Run the 'netstat' command to list active connections
    try:
        # Execute the command with subprocess
        result = subprocess.run(
            ["netstat", "-an"],  # Command and arguments
            capture_output=True,  # Capture stdout and stderr
            text=True  # Get output as a string
        )
        
        # Check if the command executed successfully
        if result.returncode != 0:
            print("Error executing netstat:")
            print(result.stderr)  # Print the error message
            return
        
        # Process the output
        output = result.stdout
        print("\nRaw Output:\n")
        print(output)  # Display raw output for context

        print("\nFiltered Open Ports:\n")
        for line in output.splitlines():
            # Look for lines with "LISTENING" or "ESTABLISHED" to identify active ports
            if "LISTENING" in line or "ESTABLISHED" in line:
                print(line)
    except FileNotFoundError:
        print("The 'netstat' command is not available on this system.")
    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    scan_open_ports()

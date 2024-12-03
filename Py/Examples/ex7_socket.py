# Example input:
# Enter network range to scan (e.g., 192.168.1.0/24): 192.168.1.0/24

# Example Output:
# System Information:
# Hostname: MyDevice, Local IP: 192.168.1.10

# Scanning Results:
# Scanning network: 192.168.1.0/24
# [+] Active device found: 192.168.1.1
# [+] Active device found: 192.168.1.20
# [+] Active device found: 192.168.1.30

import socket  # Provides networking capabilities
import ipaddress  # For handling IP ranges

def scan_network(network_range):
    """
    Scans the specified network range for active devices.

    Args:
        network_range (str): CIDR notation for the network (e.g., '192.168.1.0/24').

    Returns:
        None
    """
    try:
        # Convert the range to an IP network object
        network = ipaddress.ip_network(network_range, strict=False) # Automatically calculates the correct network address based on the given prefix
        print(f"Scanning network: {network}")
        
        for ip in network.hosts():
            try:
                # Try to connect to the IP address on port 80 (HTTP)
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.settimeout(0.5)  # Timeout for responsiveness
                    result = s.connect_ex((str(ip), 80))
                    if result == 0:  # Port 80 is open
                        print(f"[+] Active device found: {ip}")
            except Exception as e:
                print(f"[-] Error scanning {ip}: {e}")
    except ValueError:
        print(f"Invalid network range: {network_range}")

if __name__ == "__main__":
    # Get the hostname and IP address of the current device
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    print(f"Hostname: {hostname}, Local IP: {local_ip}")

    # Define the local network range to scan
    network_to_scan = input("Enter network range to scan (e.g., 192.168.1.0/24): ").strip()
    scan_network(network_to_scan)

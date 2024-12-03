# Example Commands:
# Check a File with SHA256 (default):
# Input:
# python file_integrity_checker.py sample.txt

# Output:
# SHA256 checksum for 'sample.txt': e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855

# Check a File with MD5:
# Input:
# python file_integrity_checker.py sample.txt --algorithm md5

# Output:
# MD5 checksum for 'sample.txt': d41d8cd98f00b204e9800998ecf8427e

# Unsupported Algorithm:
# Input:
# python file_integrity_checker.py sample.txt --algorithm invalid

# Output:
# Error: Unsupported hashing algorithm 'invalid'.

import argparse # For creating user-friendly CLI tools.
import hashlib  # For secure hash and message digest algorithms.

def calculate_checksum(file_path, algorithm):
    """
    Calculate the checksum of the given file using the specified hashing algorithm.
    """
    try:
        hash_func = hashlib.new(algorithm)  # Create a hash object
        with open(file_path, "rb") as f:  # Open the file in binary mode
            for chunk in iter(lambda: f.read(4096), b""):  # Read file in chunks
                hash_func.update(chunk)  # Update the hash object with the chunk
        return hash_func.hexdigest()  # Return the hex digest of the hash
    except FileNotFoundError:
        print(f"Error: The file '{file_path}' does not exist.")
    except ValueError:
        print(f"Error: Unsupported hashing algorithm '{algorithm}'.")
    return None

def main():
    # Set up argument parsing
    parser = argparse.ArgumentParser(description="File Integrity Checker")
    parser.add_argument("file", help="Path to the file to process")
    parser.add_argument(
        "--algorithm", "-a",
        default="sha256",
        help="Hashing algorithm to use (default: sha256)",
        choices=hashlib.algorithms_available
    )
    args = parser.parse_args()
    
    # Calculate and display the checksum
    checksum = calculate_checksum(args.file, args.algorithm)
    if checksum:
        print(f"{args.algorithm.upper()} checksum for '{args.file}': {checksum}")

if __name__ == "__main__":
    main()

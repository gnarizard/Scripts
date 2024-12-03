# Enter the path to the source directory: ./logs
# Enter the path to the backup directory: ./backup

# Created backup directory: ./backup
# Backing up files from './logs' to './backup':
# Copied: log1.txt
# Copied: log2.txt
# Backup completed.

import shutil  # Copy, move, or delete files and directories.
import os

def backup_logs(source_dir, backup_dir):
    # Ensure the source directory exists
    if not os.path.exists(source_dir):
        print(f"Source directory '{source_dir}' does not exist.")
        return
    
    # Create the backup directory if it doesn't exist
    if not os.path.exists(backup_dir):
        os.makedirs(backup_dir)
        print(f"Created backup directory: {backup_dir}")
    
    # Get a list of all files in the source directory
    files = os.listdir(source_dir)
    
    if not files:
        print("No files found in the source directory to backup.")
        return
    
    print(f"Backing up files from '{source_dir}' to '{backup_dir}':")
    for file_name in files:
        full_source_path = os.path.join(source_dir, file_name)
        full_backup_path = os.path.join(backup_dir, file_name)
        
        try:
            # Copy each file to the backup directory
            shutil.copy(full_source_path, full_backup_path)
            print(f"Copied: {file_name}")
        except Exception as e:
            print(f"Failed to copy {file_name}: {e}")

    print("Backup completed.")

if __name__ == "__main__":
    # Example source and backup directories
    source_directory = input("Enter the path to the source directory: ").strip()
    backup_directory = input("Enter the path to the backup directory: ").strip()

    backup_logs(source_directory, backup_directory)

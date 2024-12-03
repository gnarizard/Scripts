# os: Interact with the Operating System
# navigate the file system, run commands, 
# or manage environment variables.
import os  # Import the os module for interacting with the operating system

# Main function that provides a menu-driven file and directory manager
def main():
    while True:  # Infinite loop to keep the program running until the user exits
        # Display the menu
        print("\n--- File and Directory Manager ---")
        print("1. Show Current Working Directory")  # Option to display the current working directory
        print("2. List Files in a Directory")       # Option to list files in a specified directory
        print("3. Create a New Directory")          # Option to create a new directory
        print("4. Delete a File or Directory")      # Option to delete a file or directory
        print("5. Exit")                            # Option to exit the program

        # Get the user's choice
        # strip() removes leading and trailing whitespace characters (spaces, tabs, newlines) from a string. 
        # Can also pass a string of characters to .strip() to specify which characters should be removed.
        choice = input("Enter your choice (1-5): ").strip()

        if choice == "1":  # Option 1: Show the current working directory
            print("Current Working Directory:", os.getcwd())  # os.getcwd() retrieves the current directory

        elif choice == "2":  # Option 2: List files in a directory
            # Prompt the user for a directory path; use the current directory if left blank
            path = input("Enter directory path (leave blank for current): ").strip() or os.getcwd()
            if os.path.exists(path):  # Check if the directory exists
                print("Files and Directories in", path)
                print("\n".join(os.listdir(path)))  # List all files and directories in the given path
            else:
                print("Invalid path.")  # Error message if the directory does not exist

        elif choice == "3":  # Option 3: Create a new directory
            # Prompt the user for the new directory name
            dir_name = input("Enter the name of the new directory: ").strip()
            try:
                os.makedirs(dir_name)  # Create the directory (creates intermediate directories if needed)
                print(f"Directory '{dir_name}' created.")  # Success message
            except Exception as e:
                print(f"Error creating directory: {e}")  # Error message if something goes wrong

        elif choice == "4":  # Option 4: Delete a file or directory
            # Prompt the user for the target to delete
            target = input("Enter the file or directory to delete: ").strip()
            if os.path.exists(target):  # Check if the target exists
                try:
                    if os.path.isfile(target):  # Check if the target is a file
                        os.remove(target)  # Delete the file
                        print(f"File '{target}' deleted.")  # Success message for file deletion
                    elif os.path.isdir(target):  # Check if the target is a directory
                        os.rmdir(target)  # Delete the directory (only if it is empty)
                        print(f"Directory '{target}' deleted.")  # Success message for directory deletion
                except Exception as e:
                    print(f"Error deleting target: {e}")  # Error message if something goes wrong
            else:
                print("Target not found.")  # Error message if the file or directory does not exist

        elif choice == "5":  # Option 5: Exit the program
            print("Exiting the program.")  # Exit message
            break  # Break the loop to exit

        else:  # Handle invalid choices
            print("Invalid choice. Please select 1-5.")  # Error message for invalid input

# Entry point for the script
if __name__ == "__main__":
    main()  # Run the main function

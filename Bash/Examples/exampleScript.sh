#!/bin/bash

# 1. $ (Variable/Command Substitution)
# Accesses variables or substitutes command output.
# my_var="Hello"
# echo $my_var  # Output: Hello

# current_dir=$(pwd)
# echo $current_dir  # Output: Current directory path

# 2. @ (All Arguments)
# Represents all arguments as separate strings.
# ./script.sh arg1 "arg2 with spaces"
# for arg in "$@"; do echo $arg; done
# # Output: arg1
# #         arg2 with spaces

# 3. * (Wildcard or All Arguments)
# Matches all files or combines all arguments into one string.
# ls *.txt  # Lists all `.txt` files
# ./script.sh arg1 arg2
# echo "$*"  # Output: arg1 arg2

# 4. # (Comment or Argument Count)
# Comments out a line or shows the number of arguments.
# # This is a comment
# echo $#  # Output: Number of arguments

# 5. ? (Exit Status)
# Holds the exit status of the last executed command.
# ls nonexistent_file
# echo $?  # Output: Non-zero (error code)

# 6. $$ (Process ID)
# Represents the current script’s process ID.
# echo $$  # Output: Process ID

# 7. $! (Last Background PID)
# Gets the process ID of the last background command.
# sleep 10 &
# echo $!  # Output: PID of `sleep` command

# 8. ${} (Variable Expansion)
# Expands variable values, useful for string manipulation.
# my_var="Hello"
# echo ${my_var}World  # Output: HelloWorld

# 9. > and >> (Redirection)
# Redirect output to a file (> overwrites, >> appends).
# echo "Hello" > file.txt   # Overwrite file.txt
# echo "World" >> file.txt  # Append to file.txt

# 10. | (Pipe)
# Sends output of one command as input to another.
# ls | grep ".txt"  # Finds `.txt` files

# 11. & (Background Process)
# Runs a command in the background.
# sleep 10 &


# Demonstrating chmod to change permissions
echo "Changing permissions of 'testfile' to 775 (if it exists)..."
touch testfile
chmod 775 testfile
echo "Permissions updated."
# Changing permissions of 'testfile' to 775 (if it exists)...
# Permissions updated.

# Viewing environment variables
echo "The value of the HOME environment variable is: $HOME"
echo "The current shell is: $SHELL"
# The value of the HOME environment variable is: /home/user
# The current shell is: /bin/bash

# Grabbing command output
current_dir=$(pwd)
echo "The current directory is: $current_dir"
# The current directory is: /home/user/scripts

# Using CLI arguments
echo "You provided these command-line arguments: $@"
if [ -n "$1" ]; then
    echo "First argument: $1"
else
    echo "No first argument provided."
fi
# You provided these command-line arguments: arg1 arg2
# First argument: arg1

# Reading user input
echo "Enter a filename to create: "
read user_file
touch "$user_file"
echo "File '$user_file' created."
# Enter a filename to create: 
# example.txt
# File 'example.txt' created.

# Demonstrating conditional checks
echo "Checking if '$user_file' exists..."
if [ -f "$user_file" ]; then
    echo "File '$user_file' exists!"
else
    echo "File '$user_file' does not exist."
fi
# Checking if 'example.txt' exists...
# File 'example.txt' exists!


# Using loops to process a list
echo "Processing a list of files in the current directory:"
for file in $(ls); do
    echo " - $file"
done
# Processing a list of files in the current directory:
#  - exampleScript.sh
#  - testfile
#  - example.txt

# Reading and writing to files
echo "Writing some data to '$user_file'..."
echo "This is a test file created on $(date)" > "$user_file"
echo "Contents of '$user_file':"
cat "$user_file"
# Writing some data to 'example.txt'...
# Contents of 'example.txt':
# This is a test file created on Tue Dec  3 16:00:00 2024

# String manipulation
echo "Enter a string to manipulate: "
read user_string
echo "Original string: $user_string"
echo "String in uppercase: ${user_string^^}"
echo "String in lowercase: ${user_string,,}"
# Enter a string to manipulate: 
# Hello World
# Original string: Hello World
# String in uppercase: HELLO WORLD
# String in lowercase: hello world

# Creating and cleaning up temporary files
temp_file=$(mktemp)
echo "Temporary file created: $temp_file"
echo "Cleaning up..."
rm -f "$temp_file"
echo "Temporary file deleted."
# Temporary file created: /tmp/tmp.xYz12345
# Cleaning up...
# Temporary file deleted.

# Demonstrating nested conditionals
echo "Checking for the presence of common directories:"
if [ -d /etc ]; then
    echo "/etc exists."
    if [ -d /etc/sysconfig ]; then
        echo "/etc/sysconfig also exists."
    else
        echo "/etc/sysconfig does not exist."
    fi
else
    echo "/etc does not exist."
fi
# Checking for the presence of common directories:
# /etc exists.
# /etc/sysconfig also exists.

# Exit status
echo "Exiting the script with a status of 0 (success)."
exit 0
# Exiting the script with a status of 0 (success).
#!/bin/bash

# Exit script if any command fails
set -e

# Ensure a README.md file exists
if [ ! -f "README.md" ]; then
    echo "README.md not found. Creating an empty README.md file..."
    touch README.md
fi

# Prompt for the remote repository URL
read -p "Enter the remote repository URL (e.g., https://github.com/username/repo.git): " REPO_URL

# Check if the user provided a URL
if [ -z "$REPO_URL" ]; then
    echo "No repository URL provided. Exiting."
    exit 1
fi

# Initialize Git repository
git init

# Add README.md to staging
git add README.md

# Commit with a message
git commit -m "first commit"

# Set the branch name to 'main'
git branch -M main

# Add the remote repository
git remote add origin "$REPO_URL"

# Push to the remote repository
git push -u origin main

echo "Repository initialized and pushed successfully to $REPO_URL."

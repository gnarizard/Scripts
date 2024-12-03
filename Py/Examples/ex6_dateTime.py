# Example Output
# Console Output:
# [2024-12-03 15:45:00] ALERT: Unauthorized login attempt detected.
# [2024-12-03 15:45:01] INFO: System scan completed successfully.
# [2024-12-03 15:45:02] ERROR: Failed to connect to the database.
# File Output (activity_log.txt):
# [2024-12-03 15:45:00] ALERT: Unauthorized login attempt detected.
# [2024-12-03 15:45:01] INFO: System scan completed successfully.
# [2024-12-03 15:45:02] ERROR: Failed to connect to the database.

from datetime import datetime  # Provides functions to work with dates and times

def log_activity(activity_type, description):
    """
    Logs an activity with a timestamp.
    
    Args:
        activity_type (str): Type of activity (e.g., 'ALERT', 'INFO', 'ERROR').
        description (str): Description of the activity.
    """
    # Get the current date and time
    current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # Format the log entry
    log_entry = f"[{current_time}] {activity_type}: {description}"
    
    # Print the log entry to the console
    print(log_entry)
    
    # Append the log entry to a file
    with open("activity_log.txt", "a") as log_file:
        log_file.write(log_entry + "\n")

if __name__ == "__main__":
    # Example log entries
    log_activity("ALERT", "Unauthorized login attempt detected.")
    log_activity("INFO", "System scan completed successfully.")
    log_activity("ERROR", "Failed to connect to the database.")

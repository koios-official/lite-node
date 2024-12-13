#!/bin/bash

# Set the working directory to the directory containing the rpc folder
cd /scripts/sql/rpc
SCHEMA_NAME=${RPC_SCHEMA}

# Files to log successful and unsuccessful executions
OK_FILE="Ok.txt"
NOT_OK_FILE="NotOk.txt"

# Empty the log files if they already exist
> "$OK_FILE"
> "$NOT_OK_FILE"

# Loop through all .sql files in the rpc folder and its subfolders
find /scripts/sql/rpc -name '*.sql' | sort | while read -r sql_file; do
  # Create a temporary SQL file
  TEMP_SQL_FILE="temp_$(basename "$sql_file")"

  # Replace the placeholder with the actual schema name
  sed "s/{{SCHEMA}}/$SCHEMA_NAME/g" "$sql_file" > "$TEMP_SQL_FILE"

  # Execute the SQL file and capture the output
  SQL_OUTPUT=$(psql -qt < "$TEMP_SQL_FILE" 2>&1)

  # Check for "ERROR:" in the SQL output
  if echo "$SQL_OUTPUT" | grep -q "ERROR:"; then
    # If error is found, append the file name to NotOk.txt
    echo "$sql_file: ${SQL_OUTPUT}" >> "$NOT_OK_FILE"
  else
    # If no error, append the file name to Ok.txt
    echo "$sql_file" >> "$OK_FILE"
  fi

  # Remove the temporary file
  #echo "$TEMP_SQL_FILE"
  rm "$TEMP_SQL_FILE"
done

psql -qt -c "NOTIFY pgrst, 'reload schema'" >/dev/null

# echo "Execution complete. Check $OK_FILE and $NOT_OK_FILE for results."
echo -e "SQL scripts have finished processing, following scripts were executed successfully:\n"
cat /scripts/sql/rpc/Ok.txt
echo -e "\n\nThe following errors were encountered during processing:\n"
cat /scripts/sql/rpc/NotOk.txt

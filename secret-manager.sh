#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 [environment] [operation] [key or input_file] [options]"
    echo "Environment: dev, prod (default: dev)"
    echo "Operation: list, get, update, batch (default: list)"
    echo "Key: For 'get' operation, the key to retrieve"
    echo "Input_file: For 'batch' operation, path to file with key=value pairs"
    echo "Options:"
    echo "  --dry-run    Show what would be updated without making changes"
    echo "  --show-values  When listing keys, also show their plaintext values"
    echo ""
    echo "Example:"
    echo "  $0 dev list                      - List all keys in backend-secrets-dev.yaml"
    echo "  $0 dev list --show-values        - List all keys with their plaintext values"
    echo "  $0 dev get DATABASE_URL          - Show the plaintext value of DATABASE_URL"
    echo "  $0 dev update                    - Interactive: Update or add a key in backend-secrets-dev.yaml"
    echo "  $0 dev batch secrets.txt         - Batch: Update multiple keys from a file"
    echo "  $0 dev batch secrets.txt --dry-run - Batch: Preview changes without applying them"
    echo "  $0 dev batch                     - Batch: Read key=value pairs from stdin"
    exit 1
}

# Parse arguments
ENVIRONMENT=${1:-dev}
OPERATION=${2:-list}
KEY_OR_FILE=$3
DRY_RUN=false
SHOW_VALUES=false

# Check for options
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    elif [[ "$arg" == "--show-values" ]]; then
        SHOW_VALUES=true
    fi
done

# If dry-run is the third argument, clear KEY_OR_FILE
if [[ "$3" == "--dry-run" || "$3" == "--show-values" ]]; then
    KEY_OR_FILE=""
fi

# Check if the file exists
SECRETS_FILE="secrets/backend-secrets-$ENVIRONMENT.yaml"
if [ ! -f "$SECRETS_FILE" ]; then
    echo "Error: $SECRETS_FILE does not exist"
    exit 1
fi

# Function to extract keys from the secrets file
get_keys() {
    # Skip metadata fields (name, namespace) and focus on data section
    grep -E '^\s+[A-Z0-9_]+:' "$SECRETS_FILE" | awk '{print $1}' | sed 's/:$//'
}

# Function to base64 encode a string
encode_base64() {
    echo -n "$1" | base64
}

# Function to base64 decode a string
decode_base64() {
    echo -n "$1" | base64 --decode
}

# Function to get current value for a key
get_current_value() {
    local key=$1
    grep -E "^\s+$key:" "$SECRETS_FILE" | awk '{print $2}'
}

# Function to get current plaintext value for a key
get_plaintext_value() {
    local key=$1
    local encoded_value=$(get_current_value "$key")
    if [ -n "$encoded_value" ]; then
        decode_base64 "$encoded_value"
    else
        echo "Key not found: $key"
        return 1
    fi
}

# Create a temporary file
create_temp_file() {
    mktemp
}

# Function to update or add a key-value pair
update_key() {
    local key=$1
    local value=$2
    local encoded_value=$(encode_base64 "$value")
    local temp_file=$(create_temp_file)
    
    # Check if key already exists
    if grep -q "^\s*$key:" "$SECRETS_FILE"; then
        # Get the current value
        local current_encoded=$(get_current_value "$key")
        
        if [ "$DRY_RUN" = true ]; then
            echo "Would update key: $key"
            echo "  From: $current_encoded"
            echo "  To:   $encoded_value"
            echo "  Plain value: $value"
        else
            # Create a new file with the updated key
            awk -v key="$key" -v value="$encoded_value" -v plaintext="$value" '
            {
                if ($1 == key":") {
                    print "  # " plaintext;
                    print "  " key ": " value;
                } else {
                    print $0;
                }
            }' "$SECRETS_FILE" > "$temp_file"
            
            # Replace the original file
            mv "$temp_file" "$SECRETS_FILE"
            echo "Updated key: $key"
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            echo "Would add new key: $key"
            echo "  Value: $encoded_value"
            echo "  Plain value: $value"
        else
            # Add new key to the data section
            awk -v key="$key" -v value="$encoded_value" -v plaintext="$value" '
            {
                print $0;
                if ($0 ~ /^data:/) {
                    print "  # " plaintext;
                    print "  " key ": " value;
                }
            }' "$SECRETS_FILE" > "$temp_file"
            
            # Replace the original file
            mv "$temp_file" "$SECRETS_FILE"
            echo "Added new key: $key"
        fi
    fi
}

# Function to process batch input
process_batch() {
    local source=$1
    local count=0
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN MODE: No changes will be made"
        echo "-----------------------------------"
    fi
    
    # Process each line in the form KEY=VALUE
    while IFS='=' read -r key value; do
        # Skip empty lines or lines starting with #
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        if [[ -n "$key" && -n "$value" ]]; then
            update_key "$key" "$value"
            ((count++))
        fi
    done < "$source"
    
    if [ "$DRY_RUN" = true ]; then
        echo "-----------------------------------"
        echo "Would process $count keys"
    else
        echo "Processed $count keys"
    fi
}

# Main logic
if [ "$OPERATION" = "list" ]; then
    echo "Keys in $SECRETS_FILE:"
    if [ "$SHOW_VALUES" = true ]; then
        echo "------------------------------------"
        echo "KEY                     | VALUE"
        echo "------------------------------------"
        for key in $(get_keys); do
            value=$(get_plaintext_value "$key")
            # Truncate value if too long
            if [ ${#value} -gt 50 ]; then
                value="${value:0:47}..."
            fi
            printf "%-24s | %s\n" "$key" "$value"
        done
        echo "------------------------------------"
    else
        get_keys
    fi
elif [ "$OPERATION" = "get" ]; then
    if [ -z "$KEY_OR_FILE" ]; then
        echo "Error: Key not specified"
        usage
    fi
    
    echo -n "Value for $KEY_OR_FILE: "
    get_plaintext_value "$KEY_OR_FILE"
    echo # Add newline after the value
elif [ "$OPERATION" = "update" ]; then
    echo "Available keys in $SECRETS_FILE:"
    get_keys
    echo ""
    
    # Ask for key and value
    read -p "Enter key to update/add (or type 'q' to quit): " KEY
    if [ "$KEY" = "q" ]; then
        exit 0
    fi
    
    read -p "Enter value for $KEY: " VALUE
    if [ -z "$VALUE" ]; then
        echo "Error: Value cannot be empty"
        exit 1
    fi
    
    update_key "$KEY" "$VALUE"
elif [ "$OPERATION" = "batch" ]; then
    if [ -n "$KEY_OR_FILE" ]; then
        # Check if input file exists
        if [ ! -f "$KEY_OR_FILE" ]; then
            echo "Error: Input file $KEY_OR_FILE does not exist"
            exit 1
        fi
        
        echo "Processing batch updates from $KEY_OR_FILE..."
        process_batch "$KEY_OR_FILE"
    else
        # Read from stdin
        echo "Enter key=value pairs (one per line, Ctrl+D to finish):"
        TEMP_FILE=$(create_temp_file)
        cat > "$TEMP_FILE"
        process_batch "$TEMP_FILE"
        rm "$TEMP_FILE"
    fi
else
    echo "Invalid operation: $OPERATION"
    usage
fi

exit 0 
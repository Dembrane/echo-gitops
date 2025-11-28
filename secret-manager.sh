#!/bin/bash

# Function to display usage information
usage() {
    echo "Usage: $0 [environment] [operation] [key or input_file] [options]"
    echo "Environment: dev, testing, prod (default: dev)"
    echo "Operation: list, get, update, batch, compare (default: list)"
    echo "Key: For 'get' operation, the key to retrieve"
    echo "Input_file: For 'batch' operation, path to file with key=value pairs"
    echo "Options:"
    echo "  --dry-run        Show what would be updated without making changes"
    echo "  --show-values    When listing keys, also show their plaintext values"
    echo "  --live           Fetch current values from the Kubernetes Secret instead of local file (list/get only)"
    echo ""
    echo "Example:"
    echo "  $0 dev list                      - List all keys in backend-secrets-dev.yaml"
    echo "  $0 dev list --show-values        - List all keys with their plaintext values"
    echo "  $0 dev get DATABASE_URL          - Show the plaintext value of DATABASE_URL"
    echo "  $0 dev update                    - Interactive: Update or add a key in backend-secrets-dev.yaml"
    echo "  $0 dev batch secrets.txt         - Batch: Update multiple keys from a file"
    echo "  $0 dev batch secrets.txt --dry-run - Batch: Preview changes without applying them"
    echo "  $0 dev batch                     - Batch: Read key=value pairs from stdin"
    echo "  $0 compare                       - Compare secrets between dev and prod environments"
    exit 1
}

# Parse arguments
# Handle special case where first argument is 'compare'
if [[ "$1" == "compare" ]]; then
    ENVIRONMENT="dev"  # Default, but not used for compare
    OPERATION="compare"
    KEY_OR_FILE=$2
else
    ENVIRONMENT=${1:-dev}
    OPERATION=${2:-list}
    KEY_OR_FILE=$3
fi

SUPPORTED_ENVIRONMENTS=(dev testing prod)

TEMP_SECRETS_FILE=""

cleanup() {
    if [[ -n "$TEMP_SECRETS_FILE" && -f "$TEMP_SECRETS_FILE" ]]; then
        rm -f "$TEMP_SECRETS_FILE"
    fi
}

trap cleanup EXIT

DRY_RUN=false
SHOW_VALUES=false
LIVE_MODE=false

# Check for options
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    elif [[ "$arg" == "--show-values" ]]; then
        SHOW_VALUES=true
    elif [[ "$arg" == "--live" ]]; then
        LIVE_MODE=true
    fi
done

# If dry-run is the third argument, clear KEY_OR_FILE
if [[ "$3" == "--dry-run" || "$3" == "--show-values" ]]; then
    KEY_OR_FILE=""
fi

ensure_valid_environment() {
    local env=$1
    for allowed in "${SUPPORTED_ENVIRONMENTS[@]}"; do
        if [[ "$env" == "$allowed" ]]; then
            return 0
        fi
    done
    echo "Error: Unsupported environment '$env'. Supported: ${SUPPORTED_ENVIRONMENTS[*]}"
    exit 1
}

namespace_for_env() {
    local env=$1
    case "$env" in
        dev) echo "echo-dev" ;;
        testing) echo "echo-testing" ;;
        prod) echo "echo-prod" ;;
        *) echo "echo-$env" ;;
    esac
}

context_for_env() {
    local env=$1
    case "$env" in
        dev) echo "do-ams3-dbr-echo-dev-k8s-cluster" ;;
        testing) echo "do-ams3-dbr-echo-testing-k8s-cluster" ;;
        prod) echo "do-ams3-dbr-echo-prod-k8s-cluster" ;;
        *) echo "" ;;
    esac
}

ensure_secrets_file() {
    if [ -f "$SECRETS_FILE" ]; then
        return
    fi

    local namespace=$(namespace_for_env "$ENVIRONMENT")

    cat <<EOF > "$SECRETS_FILE"
apiVersion: v1
kind: Secret
metadata:
  name: echo-backend-secrets
  namespace: $namespace
type: Opaque
data:
EOF

    echo "Initialized $SECRETS_FILE for $ENVIRONMENT environment"
}

# Check if the file exists (skip for compare operation)
if [[ "$LIVE_MODE" = true && "$OPERATION" != "list" && "$OPERATION" != "get" ]]; then
    echo "Error: --live is only supported with list/get operations"
    exit 1
fi

if [[ "$LIVE_MODE" = true && "$OPERATION" == "compare" ]]; then
    echo "Error: --live cannot be used with compare operation"
    exit 1
fi

if [[ "$OPERATION" != "compare" ]]; then
    ensure_valid_environment "$ENVIRONMENT"
    if [[ "$LIVE_MODE" = true ]]; then
        if ! command -v kubectl >/dev/null 2>&1; then
            echo "Error: kubectl is required for --live mode"
            exit 1
        fi
        namespace=$(namespace_for_env "$ENVIRONMENT")
        ctx_value=$(context_for_env "$ENVIRONMENT")
        if [[ -z "$ctx_value" ]]; then
            echo "Error: no kubernetes context configured for environment '$ENVIRONMENT'"
            exit 1
        fi
        TEMP_SECRETS_FILE=$(mktemp)
        if ! kubectl --context="$ctx_value" get secret echo-backend-secrets -n "$namespace" -o yaml > "$TEMP_SECRETS_FILE"; then
            echo "Error: failed to fetch kubernetes secret 'echo-backend-secrets' in namespace '$namespace' using context '$ctx_value'"
            exit 1
        fi
        SECRETS_FILE="$TEMP_SECRETS_FILE"
    else
        SECRETS_FILE="secrets/backend-secrets-$ENVIRONMENT.yaml"
        ensure_secrets_file
    fi
fi

# Function to extract keys from the secrets file
get_keys() {
    local file=${1:-$SECRETS_FILE}
    # Skip metadata fields (name, namespace) and focus on data section
    grep -E '^\s+[A-Z0-9_]+:' "$file" | awk '{print $1}' | sed 's/:$//'
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

# Function to compare secrets between dev and prod
compare_secrets() {
    local dev_file="secrets/backend-secrets-dev.yaml"
    local prod_file="secrets/backend-secrets-prod.yaml"
    
    # Check if both files exist
    if [ ! -f "$dev_file" ]; then
        echo "Error: $dev_file does not exist"
        exit 1
    fi
    
    if [ ! -f "$prod_file" ]; then
        echo "Error: $prod_file does not exist"
        exit 1
    fi
    
    # Get keys from both environments
    local dev_keys=$(get_keys "$dev_file" | sort)
    local prod_keys=$(get_keys "$prod_file" | sort)
    
    # Create temporary files for comparison
    local temp_dev=$(create_temp_file)
    local temp_prod=$(create_temp_file)
    
    echo "$dev_keys" > "$temp_dev"
    echo "$prod_keys" > "$temp_prod"
    
    # Get all unique keys
    local all_keys=$(cat "$temp_dev" "$temp_prod" | sort -u)
    
    # Print table header
    printf "%-40s | %-6s | %-6s\n" "SECRET KEY" "DEV" "PROD"
    printf "%-40s-+--------+-------\n" "----------------------------------------"
    
    # Check each key's presence in both environments
    for key in $all_keys; do
        local dev_status="❌"
        local prod_status="❌"
        
        if grep -q "^$key$" "$temp_dev"; then
            dev_status="✅"
        fi
        
        if grep -q "^$key$" "$temp_prod"; then
            prod_status="✅"
        fi
        
        printf "%-40s | %-6s | %-6s\n" "$key" "$dev_status" "$prod_status"
    done
    
    # Summary statistics
    local total_dev=$(echo "$dev_keys" | wc -l)
    local total_prod=$(echo "$prod_keys" | wc -l)
    local total_unique=$(echo "$all_keys" | wc -l)
    local common=$(comm -12 "$temp_dev" "$temp_prod" | wc -l)
    local dev_only=$(comm -23 "$temp_dev" "$temp_prod" | wc -l)
    local prod_only=$(comm -13 "$temp_dev" "$temp_prod" | wc -l)
    
    echo ""
    echo "Summary:"
    echo "  Total secrets in DEV:  $total_dev"
    echo "  Total secrets in PROD: $total_prod"
    echo "  Common secrets:        $common"
    echo "  DEV only:              $dev_only"
    echo "  PROD only:             $prod_only"
    
    # Clean up temporary files
    rm "$temp_dev" "$temp_prod"
}

# Main logic
if [ "$OPERATION" = "list" ]; then
    echo "Keys in $SECRETS_FILE:"
    if [ "$SHOW_VALUES" = true ]; then
        echo "# .env format for $ENVIRONMENT environment"
        echo "# Generated from $SECRETS_FILE on $(date)"
        echo ""
        for key in $(get_keys); do
            value=$(get_plaintext_value "$key")
            # Escape any double quotes in the value
            value=$(echo "$value" | sed 's/"/\\"/g')
            echo "$key=\"$value\""
        done
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
elif [ "$OPERATION" = "compare" ]; then
    compare_secrets
else
    echo "Invalid operation: $OPERATION"
    usage
fi

exit 0 

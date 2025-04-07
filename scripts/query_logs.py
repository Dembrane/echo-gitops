#!/usr/bin/env python3

import requests
import json
import time
import argparse
import datetime
import sys
import os
import csv
from io import StringIO
from urllib.parse import quote
from requests.auth import HTTPBasicAuth

def setup_arg_parser():
    parser = argparse.ArgumentParser(description='Query Loki logs for echo app')
    parser.add_argument('--url', default='http://localhost:3100', help='Loki API URL')
    parser.add_argument('--username', help='Loki username for basic auth (if needed)')
    parser.add_argument('--password', help='Loki password for basic auth (if needed)')
    parser.add_argument('--hours', type=int, default=1, help='Hours of logs to fetch')
    parser.add_argument('--days', type=int, default=0, help='Days of logs to fetch')
    parser.add_argument('--from-date', help='Start date in YYYY-MM-DD format')
    parser.add_argument('--from-time', default='00:00:00', help='Start time in HH:MM:SS format (used with --from-date)')
    parser.add_argument('--to-date', help='End date in YYYY-MM-DD format')
    parser.add_argument('--to-time', default='23:59:59', help='End time in HH:MM:SS format (used with --to-date)')
    parser.add_argument('--component', default='api', help='Echo component to filter logs (e.g., api, worker, directus)')
    parser.add_argument('--namespace', default='echo-dev', help='Kubernetes namespace')
    parser.add_argument('--limit', type=int, default=1000, help='Maximum number of log lines per request')
    parser.add_argument('--max-entries', type=int, help='Maximum total log entries to retrieve (default: unlimited)')
    parser.add_argument('--output', default='json', choices=['json', 'raw', 'csv'], help='Output format')
    parser.add_argument('--debug', action='store_true', help='Enable debug output')
    parser.add_argument('--all', action='store_true', help='Get all logs regardless of component')
    parser.add_argument('--csv-file', help='CSV file to save the output (only for CSV output)')
    parser.add_argument('--text-contains', help='Filter logs to include only those containing this text')
    parser.add_argument('--text-not-contains', help='Filter logs to exclude those containing this text')
    parser.add_argument('--container', help='Container name to filter logs')
    parser.add_argument('--paginate', action='store_true', help='Use pagination to retrieve all logs within time range')
    parser.add_argument('--chunk-hours', type=int, default=11, help='Hours per time chunk for Loki queries (max 12, default: 11)')
    return parser.parse_args()

def get_time_range(args):
    """Calculate the time range based on the input arguments."""
    if args.from_date:
        # Parse from custom date/time inputs
        try:
            from_str = f"{args.from_date} {args.from_time}"
            from_dt = datetime.datetime.strptime(from_str, "%Y-%m-%d %H:%M:%S")
            
            if args.to_date:
                to_str = f"{args.to_date} {args.to_time}"
                to_dt = datetime.datetime.strptime(to_str, "%Y-%m-%d %H:%M:%S")
            else:
                # Default to current time if only from-date is specified
                to_dt = datetime.datetime.now()
                
            # Convert to nanoseconds
            start_time = int(from_dt.timestamp() * 1e9)
            end_time = int(to_dt.timestamp() * 1e9)
        except ValueError as e:
            print(f"Error parsing date/time: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        # Calculate from hours/days
        end_time = int(time.time() * 1e9)  # Current time in nanoseconds
        hours_to_fetch = args.hours + (args.days * 24)
        start_time = end_time - (hours_to_fetch * 60 * 60 * 1e9)  # N hours back in nanoseconds
    
    return start_time, end_time

def build_query(args):
    """Build the Loki query based on input arguments."""
    # Build base query
    query = f'{{namespace="{args.namespace}", app="echo"}}'
    
    # Add component filter if not getting all components
    if not args.all and args.component:
        if ',' in args.component:
            component_list = [comp.strip() for comp in args.component.split(',')]
            component_regex = '|'.join(component_list)
            query = f'{{namespace="{args.namespace}", app="echo", component=~"({component_regex})"}}'
        else:
            query = f'{{namespace="{args.namespace}", app="echo", component="{args.component}"}}'
    
    # Add container filter if specified
    if args.container:
        # Update the query to include container filter
        # Need to remove the closing brace, add the filter, and close it again
        query = query[:-1] + f', container="{args.container}"}}'
    
    # Add text filtering if specified
    if args.text_contains or args.text_not_contains:
        query_with_filter = query
        
        if args.text_contains:
            query_with_filter = f'{query} |~ "{args.text_contains}"'
        
        if args.text_not_contains:
            query_with_filter = f'{query_with_filter} !~ "{args.text_not_contains}"'
        
        return query_with_filter
    
    return query

def create_time_chunks(start_time, end_time, chunk_hours):
    """Split a time range into chunks under 12 hours to comply with Loki's limit."""
    # Convert chunk hours to nanoseconds
    chunk_size = chunk_hours * 60 * 60 * 1e9
    
    chunks = []
    current_start = start_time
    
    while current_start < end_time:
        current_end = min(current_start + chunk_size, end_time)
        chunks.append((current_start, current_end))
        current_start = current_end
    
    return chunks

def query_loki_logs_chunked(args):
    """Query Loki logs in time chunks to handle the 12-hour limit."""
    start_time, end_time = get_time_range(args)
    query = build_query(args)
    
    # Calculate time chunks (each under 12 hours)
    time_chunks = create_time_chunks(start_time, end_time, args.chunk_hours)
    
    if args.debug:
        print(f"DEBUG: Full time range - from {datetime.datetime.fromtimestamp(start_time / 1e9)} to {datetime.datetime.fromtimestamp(end_time / 1e9)}")
        print(f"DEBUG: Using query: {query}")
        print(f"DEBUG: Split into {len(time_chunks)} time chunks")
    
    # Store all results
    all_results = []
    total_entries = 0
    
    # Process each time chunk
    for chunk_index, (chunk_start, chunk_end) in enumerate(time_chunks):
        if args.debug:
            chunk_start_dt = datetime.datetime.fromtimestamp(chunk_start / 1e9)
            chunk_end_dt = datetime.datetime.fromtimestamp(chunk_end / 1e9)
            print(f"DEBUG: Processing chunk {chunk_index+1}/{len(time_chunks)}: {chunk_start_dt} to {chunk_end_dt}")
        
        # Process this time chunk
        if args.paginate:
            # Use pagination within each time chunk
            chunk_results = query_loki_logs_paginated(args, query, chunk_start, chunk_end)
        else:
            # Single query for this time chunk
            chunk_results = query_loki_batch(args, query, chunk_start, chunk_end, args.limit)
        
        if not chunk_results or "data" not in chunk_results or "result" not in chunk_results["data"]:
            if args.debug:
                print(f"DEBUG: No results for chunk {chunk_index+1}")
            continue
        
        # Add results from this chunk
        chunk_streams = chunk_results["data"]["result"]
        all_results.extend(chunk_streams)
        
        # Update counter
        this_chunk_count = sum(len(stream.get("values", [])) for stream in chunk_streams)
        total_entries += this_chunk_count
        
        if args.debug:
            print(f"DEBUG: Got {this_chunk_count} log entries from chunk {chunk_index+1}")
            print(f"DEBUG: Total entries so far: {total_entries}")
        
        # Check if we've hit the max entries limit
        if args.max_entries and total_entries >= args.max_entries:
            if args.debug:
                print(f"DEBUG: Reached maximum entries limit of {args.max_entries}")
            break
    
    # Construct a result that matches the structure expected by our existing processing code
    result = {
        "status": "success",
        "data": {
            "resultType": "streams",
            "result": all_results
        }
    }
    
    return result, total_entries

def query_loki_logs_paginated(args, query, start_time, end_time):
    """Query Loki logs with pagination within a single time chunk."""
    # Store all results
    all_results = []
    
    # For paginated requests, we need to keep track of the last timestamp
    current_start = start_time
    
    while current_start < end_time:
        if args.debug:
            print(f"DEBUG: Fetching page from {datetime.datetime.fromtimestamp(current_start / 1e9)}")
        
        # Get a batch of logs
        batch_result = query_loki_batch(args, query, current_start, end_time, args.limit)
        
        if not batch_result or "data" not in batch_result or "result" not in batch_result["data"] or not batch_result["data"]["result"]:
            if args.debug:
                print("DEBUG: No more logs found in this time range")
            break
        
        # Add this batch to our results
        batch_streams = batch_result["data"]["result"]
        
        # Find the newest timestamp to use for the next query
        newest_ts = current_start
        for stream in batch_streams:
            values = stream.get("values", [])
            if values:
                # Get timestamps from all values (first element of each value pair)
                timestamps = [int(ts) for ts, _ in values]
                if timestamps:
                    stream_newest = max(timestamps)
                    # Keep track of the overall newest
                    newest_ts = max(newest_ts, stream_newest)
        
        # Add the streams to our results
        all_results.extend(batch_streams)
        
        # Update the count
        this_batch_count = sum(len(stream.get("values", [])) for stream in batch_streams)
        
        if args.debug:
            print(f"DEBUG: Got {this_batch_count} log entries in this page")
        
        # Set the next start time slightly after the newest timestamp
        # Add 1 nanosecond to avoid getting the same log again
        current_start = newest_ts + 1
        
        # If we didn't get a full batch, we're probably at the end
        if this_batch_count < args.limit:
            break
    
    # Construct a result that matches the structure expected by our existing processing code
    result = {
        "status": "success",
        "data": {
            "resultType": "streams",
            "result": all_results
        }
    }
    
    return result

def query_loki_batch(args, query, start_time, end_time, limit):
    """Query a single batch of logs from Loki."""
    # Prepare API endpoint
    query_endpoint = f"{args.url}/loki/api/v1/query_range"
    
    # Prepare query parameters
    params = {
        "query": query,
        "start": str(int(start_time)),
        "end": str(int(end_time)),
        "limit": str(limit),
        "direction": "forward"  # Oldest first for consistent pagination
    }
    
    if args.debug:
        print(f"DEBUG: Query parameters: {params}")
    
    # Set up authentication if provided
    auth = None
    if args.username and args.password:
        auth = HTTPBasicAuth(args.username, args.password)
    
    try:
        # Make the request to Loki API
        response = requests.get(
            query_endpoint,
            params=params,
            auth=auth,
            headers={"Accept": "application/json"}
        )
        
        if args.debug:
            print(f"DEBUG: Response status code: {response.status_code}")
        
        # Check for successful response
        response.raise_for_status()
        
        # Return the JSON result
        return response.json()
        
    except requests.exceptions.RequestException as e:
        print(f"Error querying Loki: {e}", file=sys.stderr)
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response: {e.response.text}", file=sys.stderr)
        return None

def sanitize_filepath(filepath):
    """Sanitize and validate a file path."""
    if not filepath:
        return None
        
    try:
        # Expand user directory if present (e.g., ~/logs.csv)
        expanded_path = os.path.expanduser(filepath)
        
        # Get absolute path
        abs_path = os.path.abspath(expanded_path)
        
        # Check if the directory exists or can be created
        directory = os.path.dirname(abs_path)
        if directory and not os.path.exists(directory):
            try:
                # Just test if we can create it, don't actually create it yet
                test_permission = os.access(os.path.dirname(directory) or '.', os.W_OK)
                if not test_permission:
                    print(f"Warning: May not have permission to create directory: {directory}", file=sys.stderr)
            except Exception as e:
                print(f"Warning: Invalid directory path: {e}", file=sys.stderr)
        
        return abs_path
    except Exception as e:
        print(f"Error sanitizing file path: {e}", file=sys.stderr)
        return None

def query_loki_logs(args):
    # Use time-chunked querying approach (handles any time range safely)
    result, total_entries = query_loki_logs_chunked(args)
    
    # Process and output the results
    if args.debug:
        print(f"DEBUG: Response JSON keys: {result.keys()}")
        if "data" in result:
            print(f"DEBUG: Data keys: {result['data'].keys()}")
            if "result" in result["data"]:
                print(f"DEBUG: Number of results: {len(result['data']['result'])}")
                print(f"DEBUG: Total log entries: {total_entries}")
                if len(result['data']['result']) > 0:
                    # Print labels for the first result to help debug
                    first_stream = result['data']['result'][0]
                    if 'stream' in first_stream:
                        print(f"DEBUG: Sample labels: {first_stream['stream']}")
    
    # Validate CSV file path if output is CSV
    if args.output == 'csv' and args.csv_file:
        sanitized_path = sanitize_filepath(args.csv_file)
        if sanitized_path:
            args.csv_file = sanitized_path
            if args.debug:
                print(f"DEBUG: Will attempt to write CSV to {args.csv_file}")
        else:
            print("Warning: Invalid CSV file path. Will output to stdout instead.", file=sys.stderr)
            args.csv_file = None
    
    if args.output == 'json':
        print(json.dumps(result, indent=2))
    elif args.output == 'csv':
        output_as_csv(result, args.csv_file)
    else:
        # Format logs in a readable way
        if "data" in result and "result" in result["data"]:
            if len(result["data"]["result"]) == 0:
                print("No logs found for the specified criteria")
                return 0

            for stream in result["data"]["result"]:
                labels = stream.get("stream", {})
                component = labels.get("component", "unknown")
                pod = labels.get("pod", "unknown").split('/')[-1] if '/' in labels.get("pod", "unknown") else labels.get("pod", "unknown")
                
                print(f"\n=== Logs for echo-{component} pod: {pod} ===\n")
                
                for timestamp, log_entry in stream.get("values", []):
                    # Convert timestamp to human-readable format
                    ts = datetime.datetime.fromtimestamp(float(timestamp) / 1e9)
                    print(f"[{ts}] {log_entry}")
        else:
            print("No logs found for the specified criteria")
    
    return 0

def parse_log_level(log_entry):
    """Extract log level from log entry if possible."""
    # Common log level indicators
    log_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL", "WARN", "ERR", "FATAL", "TRACE"]
    
    # Try different patterns for log levels
    for level in log_levels:
        patterns = [
            f"{level}:", f"[{level}]", f"[{level.lower()}]",
            f"level={level}", f"level={level.lower()}",
            f"\"{level}\"", f"'{level}'", f"level: {level}"
        ]
        for pattern in patterns:
            if pattern in log_entry:
                return level
    
    # Check for lowercase versions
    for level in log_levels:
        if level.lower() in log_entry.lower():
            return level
    
    # Default level if none found
    return "INFO"

def output_as_csv(result, csv_file=None):
    """Output the logs in CSV format."""
    if "data" not in result or "result" not in result["data"] or not result["data"]["result"]:
        print("No logs found for the specified criteria")
        return
    
    # Prepare CSV data
    csv_data = []
    
    for stream in result["data"]["result"]:
        labels = stream.get("stream", {})
        component = labels.get("component", "unknown")
        pod = labels.get("pod", "unknown").split('/')[-1] if '/' in labels.get("pod", "unknown") else labels.get("pod", "unknown")
        container = labels.get("container", "unknown")
        
        for timestamp, log_entry in stream.get("values", []):
            try:
                # Convert timestamp to human-readable format
                ts = datetime.datetime.fromtimestamp(float(timestamp) / 1e9)
                
                # Try to extract severity/log level
                log_level = parse_log_level(log_entry)
                
                # Clean the log message to handle CSV special characters
                # This will help prevent CSV injection and formatting issues
                safe_log_entry = log_entry.replace('\r', ' ').replace('\n', ' ')
                
                csv_data.append({
                    "timestamp": ts.isoformat(),
                    "component": component,
                    "pod": pod,
                    "container": container,
                    "level": log_level,
                    "message": safe_log_entry
                })
            except Exception as e:
                print(f"Warning: Could not process log entry: {e}", file=sys.stderr)
                continue
    
    # Sort by timestamp (for paginated requests, ensure chronological order)
    csv_data.sort(key=lambda x: x["timestamp"])
    
    # Define field names for CSV
    fieldnames = ["timestamp", "component", "pod", "container", "level", "message"]
    
    if csv_file:
        try:
            # Make sure the directory exists
            directory = os.path.dirname(csv_file)
            if directory and not os.path.exists(directory):
                os.makedirs(directory)
                
            # Write to file
            with open(csv_file, 'w', newline='', encoding='utf-8') as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_ALL)
                writer.writeheader()
                writer.writerows(csv_data)
            print(f"CSV output written to {csv_file} ({len(csv_data)} entries)")
        except IOError as e:
            print(f"Error writing to CSV file: {e}", file=sys.stderr)
            print("Outputting to stdout instead:")
            # Fall back to stdout on error
            output = StringIO()
            writer = csv.DictWriter(output, fieldnames=fieldnames, quoting=csv.QUOTE_ALL)
            writer.writeheader()
            writer.writerows(csv_data)
            print(output.getvalue())
        except Exception as e:
            print(f"Unexpected error writing CSV file: {e}", file=sys.stderr)
    else:
        # Print to stdout
        output = StringIO()
        writer = csv.DictWriter(output, fieldnames=fieldnames, quoting=csv.QUOTE_ALL)
        writer.writeheader()
        writer.writerows(csv_data)
        print(output.getvalue())

if __name__ == "__main__":
    args = setup_arg_parser()
    sys.exit(query_loki_logs(args)) 
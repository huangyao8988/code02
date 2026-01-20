#!/bin/bash

# RAGFlow K8s Pod Resource Monitor Script
# Author: Claude Code
# Date: 2026-01-20

# Default parameters
MODE="basic"
WATCH=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--mode)
            MODE="$2"
            shift 2
            ;;
        -w|--watch)
            WATCH=true
            shift
            ;;
        -h|--help)
            echo "RAGFlow K8s Pod Resource Monitor Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -m, --mode <mode>    Output mode: basic, full, json, sort-cpu, sort-mem (default: basic)"
            echo "  -w, --watch          Watch mode (refresh every 5 seconds)"
            echo "  -h, --help           Show help information"
            echo ""
            echo "Examples:"
            echo "  $0                          # Basic mode"
            echo "  $0 -m full                  # Full mode"
            echo "  $0 -m json                  # JSON output"
            echo "  $0 -m sort-cpu              # Sort by CPU usage"
            echo "  $0 -m sort-mem              # Sort by memory usage"
            echo "  $0 -w                       # Watch mode"
            echo "  $0 -m full -w               # Watch mode with full info"
            exit 0
            ;;
        *)
            echo "Unknown parameter: $1"
            echo "Use -h or --help for help"
            exit 1
            ;;
    esac
done

# Set kubeconfig path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Try different kubeconfig paths
KUBECONFIG_PATH=""
for path in \
    "${SCRIPT_DIR}/../kubeconfig-sealos-ragflow-0.23.1.yaml" \
    "E:\\00_DATA_WORK_20250408\\01_OTHER\\20250420_Entrepreneuship\\20250716_Ragflow\\kubeconfig-sealos-ragflow-0.23.1.yaml" \
    "/e/00_DATA_WORK_20250408/01_OTHER/20250420_Entrepreneuship/20250716_Ragflow/kubeconfig-sealos-ragflow-0.23.1.yaml"
do
    if [ -f "$path" ]; then
        KUBECONFIG_PATH="$path"
        break
    fi
done

if [ -z "$KUBECONFIG_PATH" ]; then
    echo "Error: kubeconfig file not found" >&2
    echo "Please check: kubeconfig-sealos-ragflow-0.23.1.yaml" >&2
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found, please ensure kubectl is installed and in PATH" >&2
    exit 1
fi

# Check if jq is installed (for JSON mode only)
if [ "$MODE" = "json" ] && ! command -v jq &> /dev/null; then
    echo "Error: JSON mode requires jq tool" >&2
    echo "  Linux: sudo apt-get install jq  # Debian/Ubuntu" >&2
    echo "          sudo yum install jq     # CentOS/RHEL" >&2
    echo "  macOS: brew install jq" >&2
    echo "  Windows (Git Bash): Download jq.exe and add to PATH" >&2
    exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Helper function to parse CPU string
parse_cpu() {
    local cpu_str="$1"
    if [[ -z "$cpu_str" ]]; then
        echo "0"
        return
    fi
    if [[ $cpu_str =~ m$ ]]; then
        local val=$(echo "$cpu_str" | sed 's/m//')
        awk "BEGIN {printf \"%.3f\", $val/1000}"
    else
        awk "BEGIN {printf \"%.3f\", $cpu_str}"
    fi
}

# Helper function to parse memory string to Gi
parse_memory() {
    local mem_str="$1"
    if [[ -z "$mem_str" ]]; then
        echo "0"
        return
    fi
    if [[ $mem_str =~ Mi$ ]]; then
        local val=$(echo "$mem_str" | sed 's/Mi//')
        awk "BEGIN {printf \"%.2f\", $val/1024}"
    elif [[ $mem_str =~ Gi$ ]]; then
        echo "$mem_str" | sed 's/Gi//'
    elif [[ $mem_str =~ Ki$ ]]; then
        local val=$(echo "$mem_str" | sed 's/Ki//')
        awk "BEGIN {printf \"%.2f\", $val/1024/1024}"
    else
        echo "0"
    fi
}

# Function: Get all RAGFlow pods using kubectl
get_all_pods() {
    # Get all pods and filter by name
    kubectl get pods --no-headers 2>/dev/null | grep -E 'ragflow|web-visitor' | awk '{print $1, $2}'
}

# Function: Get pod resource information
get_pod_resources() {
    local pod_name=$1
    local namespace=$2

    # Get pod details using jsonpath
    local status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null)
    local node=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.nodeName}' 2>/dev/null)
    local creation_ts=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null)

    # Calculate age
    local age="unknown"
    if [ -n "$creation_ts" ]; then
        local created_sec=$(date -d "$creation_ts" +%s 2>/dev/null)
        if [ -n "$created_sec" ]; then
            local current_sec=$(date +%s)
            local diff=$((current_sec - created_sec))
            local days=$((diff / 86400))
            local hours=$((diff / 3600))
            local minutes=$((diff / 60))

            if [ $days -gt 0 ]; then
                age="${days}d"
            elif [ $hours -gt 0 ]; then
                age="${hours}h"
            elif [ $minutes -gt 0 ]; then
                age="${minutes}m"
            else
                age="${diff}s"
            fi
        fi
    fi

    # Get resource requests and limits
    local cpu_req=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>&1 | grep -v Warning)
    local cpu_lim=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.containers[0].resources.limits.cpu}' 2>&1 | grep -v Warning)
    local mem_req=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>&1 | grep -v Warning)
    local mem_lim=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>&1 | grep -v Warning)

    # Parse values
    local cpu_req_disp=$(parse_cpu "$cpu_req")
    local cpu_lim_disp=$(parse_cpu "$cpu_lim")
    local mem_req_disp=$(parse_memory "$mem_req")
    local mem_lim_disp=$(parse_memory "$mem_lim")

    # Get actual usage
    local metrics=$(kubectl top pod "$pod_name" -n "$namespace" --containers 2>&1 | grep -v Warning)
    local cpu_used="0"
    local mem_used="0"

    if [ -n "$metrics" ]; then
        while IFS= read -r line; do
            # Skip header and empty lines
            if [[ $line =~ ^POD ]] || [[ $line =~ ^NAME ]] || [[ -z "${line// }" ]]; then
                continue
            fi
            # Match pod name at the start of line
            if [[ $line =~ ^$pod_name[[:space:]]+ ]]; then
                # Format: POD NAME CPU(cores) MEMORY(bytes)
                # Get CPU (second to last) and Memory (last column)
                local cpu_str=$(echo "$line" | awk '{print $(NF-1)}')
                local mem_str=$(echo "$line" | awk '{print $NF}')
                cpu_used=$(parse_cpu "$cpu_str")
                mem_used=$(parse_memory "$mem_str")
                break
            fi
        done <<< "$metrics"
    fi

    # Calculate usage percentage
    local cpu_usage=$(awk "BEGIN {printf \"%.1f\", ($cpu_used / $cpu_lim_disp) * 100}")
    local mem_usage=$(awk "BEGIN {printf \"%.1f\", ($mem_used / $mem_lim_disp) * 100}")

    echo "$pod_name|$status|$node|$age|$cpu_req_disp|$cpu_lim_disp|$cpu_used|$cpu_usage|$mem_req_disp|$mem_lim_disp|$mem_used|$mem_usage"
}

# Function: Output basic table
show_basic_table() {
    local pod_list="$1"

    printf "\n${CYAN}=== RAGFlow Pods Resource Usage ===${NC}\n\n"

    printf "%-25s %-8s %-8s %-6s %6s %6s %8s %6s %6s %7s %6s\n" \
        "Pod Name" "Status" "Node" "Age" "CpuReq" "CpuLim" "CpuUsed" "Cpu%" "MemLim" "MemUsed" "Mem%"
    printf "%-25s %-8s %-8s %-6s %6s %6s %8s %6s %6s %7s %6s\n" \
        "---------" "------" "----" "---" "------" "------" "------" "-----" "------" "-------" "----"

    echo "$pod_list" | while IFS='|' read -r pod_name status node age cpu_req cpu_lim cpu_used cpu_usage mem_req mem_lim mem_used mem_usage; do
        local node_short=$(echo "$node" | tail -c 7)

        printf "%-25s %-8s %-8s %-6s %6s %6s %8s %6s %6s %7s %6s\n" \
            "$pod_name" "$status" "$node_short" "$age" \
            "$cpu_req" "$cpu_lim" "$cpu_used" "${cpu_usage}%" \
            "$mem_lim" "$mem_used" "${mem_usage}%"
    done
    echo ""
}

# Function: Output full table
show_full_table() {
    local pod_list="$1"

    printf "\n${CYAN}=== RAGFlow Pods Full Resource Details ===${NC}\n"

    echo "$pod_list" | while IFS='|' read -r pod_name status node age cpu_req cpu_lim cpu_used cpu_usage mem_req mem_lim mem_used mem_usage; do
        printf "\n${CYAN}[%s]${NC}\n" "$pod_name"
        printf "  Status: %s | Node: %s | Age: %s\n" "$status" "$node" "$age"
        printf "  CPU: Request=%s cores, Limit=%s cores, Used=%s cores (%s%%)\n" "$cpu_req" "$cpu_lim" "$cpu_used" "$cpu_usage"
        printf "  Memory: Request=%sGi, Limit=%sGi, Used=%sGi (%s%%)\n" "$mem_req" "$mem_lim" "$mem_used" "$mem_usage"
    done
    echo ""
}

# Function: Output JSON
show_json_output() {
    local pod_list="$1"

    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")

    echo "{"
    echo "  \"timestamp\": \"$timestamp\","
    echo "  \"cluster\": \"Sealos (bja.sealos.run:6443)\","
    echo "  \"pods\": ["

    local first=true
    echo "$pod_list" | while IFS='|' read -r pod_name status node age cpu_req cpu_lim cpu_used cpu_usage mem_req mem_lim mem_used mem_usage; do
        if [ "$first" = false ]; then
            echo ","
        fi
        first=false

        cat << EOF
    {
      "name": "$pod_name",
      "namespace": "ns-h8lwh4iu",
      "status": "$status",
      "node": "$node",
      "age": "$age",
      "cpu": {
        "request": $cpu_req,
        "limit": $cpu_lim,
        "used": $cpu_used,
        "usage_percent": $cpu_usage
      },
      "memory": {
        "request": $mem_req,
        "limit": $mem_lim,
        "used": $mem_used,
        "usage_percent": $mem_usage
      }
    }
EOF
    done | sed '$d'

    echo ""
    echo "  ]"
    echo "}"
}

# Function: Output sorted by resource usage
show_sorted_output() {
    local pod_list="$1"
    local sort_by="$2"

    printf "\n${CYAN}=== RAGFlow Pods Resource Usage Sorted by $sort_by ===${NC}\n\n"

    local field_index
    if [ "$sort_by" = "CPU" ]; then
        field_index=8
    else
        field_index=12
    fi

    printf "%-25s %10s %10s %12s %10s %8s\n" \
        "Pod Name" "$sort_by Req" "$sort_by Lim" "$sort_by Used" "Usage" "Status"
    printf "%-25s %10s %10s %12s %10s %8s\n" \
        "---------" "---------" "---------" "------------" "----------" "------"

    echo "$pod_list" | sort -t'|' -k${field_index} -nr | while IFS='|' read -r pod_name status node age cpu_req cpu_lim cpu_used cpu_usage mem_req mem_lim mem_used mem_usage; do
        if [ "$sort_by" = "CPU" ]; then
            req="${cpu_req}C"
            lim="${cpu_lim}C"
            used="${cpu_used}C"
            usage="${cpu_usage}%"
        else
            req="${mem_req}Gi"
            lim="${mem_lim}Gi"
            used="${mem_used}Gi"
            usage="${mem_usage}%"
        fi

        printf "%-25s %10s %10s %12s %10s %8s\n" \
            "$pod_name" "$req" "$lim" "$used" "$usage" "$status"
    done
    echo ""
}

# Main program
main() {
    # Get all pods
    local all_pods=$(get_all_pods)

    if [ -z "$all_pods" ]; then
        printf "\n${YELLOW}Warning: No RAGFlow Pods found${NC}\n\n"
        exit 0
    fi

    # Get resource information
    local pod_list=""
    while IFS= read -r line; do
        pod_name=$(echo "$line" | awk '{print $1}')
        namespace=$(echo "$line" | awk '{print $2}')
        pod_info=$(get_pod_resources "$pod_name" "$namespace")
        if [ -n "$pod_info" ]; then
            if [ -n "$pod_list" ]; then
                pod_list="$pod_list"$'\n'"$pod_info"
            else
                pod_list="$pod_info"
            fi
        fi
    done <<< "$all_pods"

    if [ -z "$pod_list" ]; then
        printf "\n${YELLOW}Warning: Unable to get pod resource information${NC}\n\n"
        exit 1
    fi

    # Output based on mode
    case $MODE in
        basic)
            show_basic_table "$pod_list"
            ;;
        full)
            show_full_table "$pod_list"
            ;;
        json)
            show_json_output "$pod_list"
            ;;
        sort-cpu)
            show_sorted_output "$pod_list" "CPU"
            ;;
        sort-mem)
            show_sorted_output "$pod_list" "Memory"
            ;;
        *)
            echo "Error: Unknown mode - $MODE" >&2
            echo "Use -h for help" >&2
            exit 1
            ;;
    esac
}

# Watch mode
if [ "$WATCH" = true ]; then
    clear
    printf "${GREEN}Watch mode enabled (refresh every 5 seconds, press Ctrl+C to exit)${NC}\n"
    printf "${GRAY}================================================${NC}\n"

    while true; do
        clear
        main
        printf "\n${GRAY}Next update: in 5 seconds... (press Ctrl+C to exit)${NC}\n"
        sleep 5
    done
else
    main
fi

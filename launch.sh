#!/bin/bash
# =============================================================================
# launch.sh - Runner for Genome Assembly Pipeline (Fixed for v10.1)
# =============================================================================

# UPDATE THIS TO MATCH YOUR RECENT BUILD TAG
IMAGE="genome-pipeline:v1.0.0.0"
THREADS=8
MINLEN=500

usage() {
    echo -e "\033[0;33mUsage:\033[0m ./launch.sh [options]"
    echo ""
    echo "Options:"
    echo "  -1, --read1 FILE     Forward reads (e.g. SRR_1.fastq.gz)"
    echo "  -2, --read2 FILE     Reverse reads (e.g. SRR_2.fastq.gz)"
    echo "  -t, --threads NUM    Number of threads (default: 8)"
    echo "  -m, --minlen NUM     Min contig length (default: 500)"
    echo "  --test               Run assembly using internal test_data/"
    echo "  -h, --help           Show this help"
    exit 1
}

run_internal_test() {
    echo -e "\033[0;34m[TEST]\033[0m Starting internal pipeline validation..."
    
    # Check for test files in your bio-gen/test_data/ folder
    if [[ ! -f "test_data/micro_R1.fastq.gz" || ! -f "test_data/micro_R2.fastq.gz" ]]; then
        echo -e "\033[0;31mError:\033[0m Test files not found in test_data/ folder."
        exit 1
    fi

    docker run --rm -it -v "$(pwd):/data" "$IMAGE" \
        -1 "test_data/micro_R1.fastq.gz" \
        -2 "test_data/micro_R2.fastq.gz" \
        -t 4
    exit 0
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -1|--read1) READ1="$2"; shift 2 ;;
        -2|--read2) READ2="$2"; shift 2 ;;
        -t|--threads) THREADS="$2"; shift 2 ;;
        -m|--minlen) MINLEN="$2"; shift 2 ;;
        --test) run_internal_test ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done

# Check if files were provided
if [[ -z "${READ1:-}" || -z "${READ2:-}" ]]; then
    echo -e "\033[0;31mError:\033[0m Missing input files."
    usage
fi

# RUN THE PIPELINE
# We use -v "$(pwd):/data" so Docker sees your files in /data
echo -e "\033[0;32m[LAUNCH]\033[0m Running $IMAGE on $READ1 and $READ2"

docker run --rm -it \
    -v "$(pwd):/data" \
    "$IMAGE" \
    -1 "$READ1" \
    -2 "$READ2" \
    -t "$THREADS" \
    -m "$MINLEN"
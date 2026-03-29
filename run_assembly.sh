#!/bin/bash
# =============================================================================
# Automated Genome Assembly Pipeline (Noble Edition)
# Version: 1.0.0.0
# Maintainer: Pavel Novitsky (lugebox@gmail.com)
# =============================================================================

set -euo pipefail

# --- Configuration & Defaults ---
PIPELINE_VER="1.0.0.0"
WORK_DIR="/data"
THREADS=8
MAX_PILON_ITERATIONS=5
MIN_CONTIG_LEN=500
READ1=""
READ2=""

# Tool Executables
PROKKA_EXE="prokka"
FASTQC_EXE="fastqc"
SPADES_EXE="spades.py"
QUAST_EXE="quast.py"
MULTIQC_EXE="multiqc"
PILON_JAR="/opt/pilon/pilon.jar"
FASTP_EXE="fastp"

# Output Formatting
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Global handle for logging
MAIN_LOG=""

# =============================================================================
# Helper Functions
# =============================================================================

log_info() { echo -e "${GREEN}[INFO]${NC} $(date +'%H:%M:%S') - $1" | tee -a "${MAIN_LOG:-/dev/null}"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date +'%H:%M:%S') - $1" | tee -a "${MAIN_LOG:-/dev/null}"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $(date +'%H:%M:%S') - $1" | tee -a "${MAIN_LOG:-/dev/null}" >&2; }

detect_mem() {
    local total_ram_gb
    total_ram_gb=$(free -g 2>/dev/null | awk '/^Mem:/ {print $2}')
    if [ -z "$total_ram_gb" ] || [ "$total_ram_gb" -le 2 ]; then echo "8"; return; fi
    if [ "$total_ram_gb" -gt 32 ]; then echo "40"
    elif [ "$total_ram_gb" -gt 16 ]; then echo "$((total_ram_gb - 4))"
    else echo "$((total_ram_gb - 2))"; fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    local required_tools=("$SPADES_EXE" "$PROKKA_EXE" "$FASTQC_EXE" "bwa" "samtools" "java")
    local missing_tools=()
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then missing_tools+=("$tool"); fi
    done
    if [ ! -f "$PILON_JAR" ]; then log_err "Pilon JAR not found at $PILON_JAR"; exit 1; fi
    if [ ${#missing_tools[@]} -gt 0 ]; then log_err "Missing tools: ${missing_tools[*]}"; exit 1; fi
    log_info "All tools verified."
}

# =============================================================================
# Pipeline Steps
# =============================================================================

run_fastqc() {
    log_info "Step 1/6: Quality Control (FastQC)..."
    $FASTQC_EXE "$READ1" "$READ2" -o "$FASTQC_DIR" -t "$THREADS" > "$LOG_DIR/fastqc.log" 2>&1
    if [ $? -eq 0 ]; then log_info "✓ FastQC completed."; else log_err "FastQC failed."; exit 1; fi
}

run_trimming() {
    log_info "Step 1.5/7: Trimming and Adapter Removal (fastp)..."
    TRIM_DIR="$RUN_DIR/trimmed"
    mkdir -p "$TRIM_DIR"

    R1_PAIRED="$TRIM_DIR/trimmed_R1.fastq.gz"
    R2_PAIRED="$TRIM_DIR/trimmed_R2.fastq.gz"
    
    $FASTP_EXE \
        --in1 "$READ1" \
        --in2 "$READ2" \
        --out1 "$R1_PAIRED" \
        --out2 "$R2_PAIRED" \
        --detect_adapter_for_pe \
        --thread "$THREADS" \
        --html "$TRIM_DIR/fastp_report.html" \
        --json "$TRIM_DIR/fastp_report.json" \
        2> "$LOG_DIR/fastp.log"

    READ1="$R1_PAIRED"
    READ2="$R2_PAIRED"
    
    log_info "✓ Trimming completed. Cleaned reads saved to: $TRIM_DIR"
}

run_spades() {
    log_info "Step 2/6: Assembly (SPAdes) | Mem: ${SPADES_MEM}G..."
    if $SPADES_EXE --careful -t "$THREADS" -m "$SPADES_MEM" \
        -1 "$READ1" -2 "$READ2" \
        -o "$ASSEMBLY_DIR" > "$LOG_DIR/spades.log" 2>&1; then
        if [ -f "$ASSEMBLY_DIR/contigs.fasta" ]; then log_info "✓ SPAdes assembly finished."; 
        else log_err "SPAdes finished but contigs.fasta missing!"; exit 1; fi
    else log_err "SPAdes failed. Check $LOG_DIR/spades.log"; exit 1; fi
}

filter_contigs() {
    log_info "Step 3/6: Filtering contigs < $MIN_CONTIG_LEN bp..."
    local input="$ASSEMBLY_DIR/contigs.fasta"
    local output="$ASSEMBLY_DIR/contigs_filtered.fasta"
    awk -v minlen="$MIN_CONTIG_LEN" '/^>/ {if (seq && length(seq) >= minlen) { print header; print seq } header = $0; seq = ""; next} {seq = seq $0} END {if (length(seq) >= minlen) { print header; print seq }}' "$input" > "$output"
    local count=$(grep -c "^>" "$output" || echo "0")
    if [ "$count" -eq 0 ]; then log_err "No contigs passed filter!"; exit 1; fi
    log_info "✓ $count contigs remaining."
}

run_pilon() {
    log_info "Step 4/6: Iterative Polishing (Pilon)..."
    local current_fasta="$ASSEMBLY_DIR/contigs_filtered.fasta"
    local pilon_mem=$(( SPADES_MEM < 12 ? SPADES_MEM : 12 ))
    for i in $(seq 1 "$MAX_PILON_ITERATIONS"); do
        log_info "--- Pilon Iteration $i ---"
        local iter_dir="$PILON_DIR/iter_$i"; mkdir -p "$iter_dir"
        bwa index "$current_fasta" > /dev/null 2>&1
        bwa mem -t "$THREADS" "$current_fasta" "$READ1" "$READ2" | samtools sort -@ "$THREADS" -o "$iter_dir/aligned.bam" -
        samtools index "$iter_dir/aligned.bam"
        if java -Xmx${pilon_mem}G -jar "$PILON_JAR" --genome "$current_fasta" --bam "$iter_dir/aligned.bam" \
             --outdir "$iter_dir" --output "polished" --changes --fix snps,indels --threads "$THREADS" > "$LOG_DIR/pilon_i$i.log" 2>&1; then
            if [[ -f "$iter_dir/polished.fasta" && -s "$iter_dir/polished.changes" ]]; then 
                current_fasta="$iter_dir/polished.fasta"; log_info "  Applied changes in iteration $i."
            elif [[ -f "$iter_dir/polished.fasta" ]]; then
                log_info "  Pilon converged (no more changes)."; current_fasta="$iter_dir/polished.fasta"; break
            else log_err "  Pilon failed in iteration $i."; exit 1; fi
        else log_err "  Pilon execution failed."; exit 1; fi
        rm -f "$iter_dir/aligned.bam" "$iter_dir/aligned.bam.bai"
    done
    cp "$current_fasta" "$PILON_DIR/final_genome.fasta"
}

run_prokka() {
    log_info "Step 5/6: Annotation (Prokka)..."
    if $PROKKA_EXE --outdir "$ANNOTATION_DIR" --prefix "genome" \
        --compliant --centre "PavelLab" \
        --kingdom Bacteria --cpus "$THREADS" --force \
        "$PILON_DIR/final_genome.fasta" > "$LOG_DIR/prokka.log" 2>&1; then
        log_info "✓ Prokka annotation finished."
    else log_err "Prokka failed. Check $LOG_DIR/prokka.log"; exit 1; fi
}

run_reports() {
    log_info "Step 6/6: Generating Reports..."
    $QUAST_EXE "$PILON_DIR/final_genome.fasta" -o "$QUAST_DIR" -t "$THREADS" > "$LOG_DIR/quast.log" 2>&1 || log_warn "QUAST failed."
    $MULTIQC_EXE "$RESULTS_DIR" -o "$REPORTS_DIR" --title "Assembly_$(basename "$RESULTS_DIR")" > "$LOG_DIR/multiqc.log" 2>&1 || log_warn "MultiQC failed."
    
    # --- FINAL TERMINAL SUMMARY ---
    local final_fasta="$PILON_DIR/final_genome.fasta"
    local gbk_file="$ANNOTATION_DIR/genome.gbk"
    local stats_file="$ANNOTATION_DIR/genome.txt"
    
    local num_contigs=$(grep -c "^>" "$final_fasta" 2>/dev/null || echo "0")
    local total_bp=$(awk '/^>/ {next} {total += length($0)} END {print total}' "$final_fasta" 2>/dev/null || echo "0")
    
    local cds_count=$(grep "CDS:" "$stats_file" 2>/dev/null | awk '{print $2}' || echo "N/A")
    
    echo -e "\n${GREEN}================================================================${NC}"
    echo -e "${GREEN}                  ASSEMBLY COMPLETE SUCCESS                     ${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${YELLOW}FINAL METRICS:${NC}"
    echo -e "  • Total Length:   $total_bp bp"
    echo -e "  • Contigs:        $num_contigs"
    echo -e "  • Predicted CDS:  $cds_count" # This will now show 4272
    echo -e "\n${YELLOW}FILES FOR SigmoID (results are inside your local folder):${NC}"
    echo -e "  1. Polished Genome:  $final_fasta"
    echo -e "  2. Annotation (GBK): $gbk_file"
    echo -e "  3. Visual Report:    $QUAST_DIR/report.html"
    echo -e "${GREEN}================================================================${NC}\n"
}

# =============================================================================
# Main Logic
# =============================================================================

main() {
    # 1. Handle Positional Arguments from launch.sh first
    if [[ $# -ge 2 ]] && [[ ! "$1" =~ ^- ]]; then
        READ1="$1"; shift
        READ2="$1"; shift
    fi

    # 2. Handle remaining flagged arguments (-t, -m, etc.)
    while [[ $# -gt 0 ]]; do
        case $1 in
            -1|--read1) READ1="$2"; shift 2 ;;
            -2|--read2) READ2="$2"; shift 2 ;;
            -t|--threads) THREADS="$2"; shift 2 ;;
            -m|--minlen) MIN_CONTIG_LEN="$2"; shift 2 ;;
            *) shift ;; # Skip unknown flags
        esac
    done

    # Validation
    if [[ -z "${READ1:-}" || -z "${READ2:-}" ]]; then
        log_err "Missing input files. Ensure READ1 and READ2 are provided."; exit 1
    fi

    # --- NESTED TIMESTAMPING LOGIC ---
    local sample_name=$(basename "$READ1" | cut -d'_' -f1)
    local timestamp=$(date +"%Y%m%d_%H%M")
    
    RESULTS_DIR="/data/results"
    RUN_DIR="$RESULTS_DIR/${sample_name}_${timestamp}"
    
    # Update sub-directories to the new RUN_DIR
    LOG_DIR="$RUN_DIR/logs"
    FASTQC_DIR="$RUN_DIR/fastqc"
    ASSEMBLY_DIR="$RUN_DIR/assembly"
    PILON_DIR="$RUN_DIR/pilon"
    ANNOTATION_DIR="$RUN_DIR/annotation"
    REPORTS_DIR="$RUN_DIR/reports"
    QUAST_DIR="$RUN_DIR/quast"

    mkdir -p "$LOG_DIR" "$FASTQC_DIR" "$ASSEMBLY_DIR" "$PILON_DIR" "$ANNOTATION_DIR" "$REPORTS_DIR" "$QUAST_DIR"
    MAIN_LOG="$LOG_DIR/pipeline_exec.log"
    touch "$MAIN_LOG"

    SPADES_MEM=$(detect_mem)
    log_info "PIPELINE START | Sample: $sample_name | Threads: $THREADS | RAM: ${SPADES_MEM}G"
    log_info "Outputs will be saved to: $RUN_DIR"

    check_prerequisites
    run_fastqc
    run_trimming
    run_spades
    filter_contigs
    run_pilon
    run_prokka
    run_reports
    
    log_info "✓ PIPELINE SUCCESSFUL!"
}

main "$@"
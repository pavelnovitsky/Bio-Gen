# ==========================================
# STAGE 1: Source Expert-Configured Tools
# ==========================================
FROM staphb/spades:4.2.0 AS spades_source
FROM staphb/prokka:1.15.6 AS prokka_source
FROM staphb/fastqc:0.12.1 AS fastqc_source

# ==========================================
# STAGE 2: Final Assembly (Ubuntu 24.04 Noble)
# ==========================================
FROM ubuntu:24.04

ARG PIPELINE_VER="1.0.0.0"

LABEL maintainer="Pavel Novitsky" \
      maintainer.email="lugebox@gmail.com" \
      software.version="${PIPELINE_VER}" \
      description="Production Genome Assembly Pipeline - Ubuntu 24.04 Noble Release"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# 1. Install all system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl git ca-certificates unzip perl bc \
    python3 python3-pip python3-setuptools \
    python3-matplotlib \
    fastp \
    default-jre-headless r-base \
    samtools bwa ncbi-blast+ hmmer prodigal parallel \
    bioperl aragorn barrnap infernal pigz libgomp1 \
    libbio-searchio-hmmer-perl libxml-simple-perl ncbi-tools-bin \
    && rm -rf /var/lib/apt/lists/*

# 2. Configure Python
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 10

# 3. Install Reporting Tools
# --break-system-packages is mandatory for global pip in Ubuntu 24.04
RUN pip3 install --no-cache-dir multiqc quast --break-system-packages

WORKDIR /opt

# 4. TELEPORT SPAdes 4.2.0
COPY --from=spades_source /SPAdes-4.2.0-Linux /opt/SPAdes-4.2.0-Linux
RUN ln -s /opt/SPAdes-4.2.0-Linux/bin/spades.py /usr/local/bin/spades.py

# 5. TELEPORT Prokka 1.15.6 & Dependencies
COPY --from=prokka_source /prokka-1.15.6 /opt/prokka-1.15.6
COPY --from=prokka_source /usr/local/bin/minced* /usr/local/bin/
# Note: Source path is /usr/bin/tbl2asn in the Prokka source image
COPY --from=prokka_source /usr/bin/tbl2asn /usr/local/bin/tbl2asn
RUN ln -sf /opt/prokka-1.15.6/bin/prokka /usr/local/bin/prokka

# 6. TELEPORT FastQC
COPY --from=fastqc_source /FastQC /opt/FastQC
RUN ln -s /opt/FastQC/fastqc /usr/local/bin/fastqc

# 7. Install Pilon (Broad Institute)
RUN mkdir -p /opt/pilon && \
    wget -q https://github.com/broadinstitute/pilon/releases/download/v1.24/pilon-1.24.jar \
    -O /opt/pilon/pilon.jar

# 8. Global Environment Configuration
ENV PATH="/opt/prokka-1.15.6/bin:${PATH}"
ENV LC_ALL=C.UTF-8
ENV PROKKA_DB_DIR="/opt/prokka-1.15.6/db"

# 9. Assembly Script Integration
COPY run_assembly.sh /usr/local/bin/run_assembly
RUN chmod +x /usr/local/bin/run_assembly

WORKDIR /data

ENTRYPOINT ["run_assembly"]
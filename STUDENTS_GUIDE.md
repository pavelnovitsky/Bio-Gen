# 🎓 Bio-Gen: Students Quick Start Guide

This guide is your "field manual" for the genomics practical. Follow these steps to transform raw sequencing data into a polished, annotated bacterial 
genome.



## 🚀 1. Verify Your Environment
Before processing real data, ensure the pipeline is healthy. Open your terminal in the `bio-gen` folder and run:

```bash
./launch.sh --test
```
* **Duration:** ~2–5 minutes.
* **Success:** You should see a message confirming `ASSEMBLY COMPLETE`. If you see this, your Docker and scripts are ready.

## 🧬 2. Prepare Your Data
Copy your assigned sequencing files into the `bio-gen` folder. 
* **Files:** You need two files (Forward `R1` and Reverse `R2`).
* **Format:** Both `.fastq` and `.fastq.gz` (compressed) are supported.
* **Example names:** `sample_R1.fastq.gz` and `sample_R2.fastq.gz`.

## ⚡ 3. Run the Assembly
Start the automated pipeline by pointing it to your specific files:

```bash
./launch.sh -1 your_file_R1.fastq.gz -2 your_file_R2.fastq.gz
```
* **The Wait:** This is data-intensive. It may take **15 to 60 minutes** depending on your hardware. **Go grab a coffee!** ☕ 
* **Crucial:** Do not close the terminal or put your computer to sleep while it is running.

## 📊 4. Explore Your Results
Once the pipeline finishes, go to the `results/` directory. Look for the **most recent folder** named with your sample name and the current timestamp 
(e.g., `sample_20260329_1930/`).



### **What to check first:**
1.  **`reports/` folder** → Open the **MultiQC HTML report**. 
    * *Focus on:* Sequence quality (FastQC), trimming efficiency (fastp), and the number of contigs (QUAST).
2.  **`annotation/` folder** → Locate the `genome.gbk` file.
    * *Action:* This is your "digital genome." Load it into **SigmoID**, IGV, or Artemis to explore genes and features.

## 🎯 5. What to Submit
To complete the assignment, you typically only need these two specific files:
* ✅ **MultiQC Report** (The `.html` file from the `reports/` folder).
* ✅ **Annotated Genome** (The `.gbk` file from the `annotation/` folder).

---

## ⚠️ Troubleshooting (Read this before panicking!)
* **"Permission Denied"**: Run `chmod +x launch.sh run_assembly.sh` and try again.
* **"Docker not running"**: Ensure Docker Desktop is open and shows a green "Running" status.
* **"Files not found"**: Double-check that your FASTQ files are actually inside the `bio-gen` folder, not just in your "Downloads" folder.
* **"It's taking a long time"**: If there is no red "Error" text, the pipeline is working. Bacterial assembly involves millions of calculations—patience 
is part of the science!


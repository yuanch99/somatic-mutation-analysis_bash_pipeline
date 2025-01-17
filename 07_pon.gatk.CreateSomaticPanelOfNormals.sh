#!/bin/bash
#SBATCH --mem=10g
#SBATCH --time=5:00:00
#SBATCH --error=%x.%j.CreateSomaticPanelOfNormals.log
#SBATCH --output=%x.%j.CreateSomaticPanelOfNormals.log
ln -f ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.CreateSomaticPanelOfNormals.log gatk.CreateSomaticPanelOfNormals.log


# scheduler settings

# set date to calculate running time
start=$(date)

# load modules
module load java/1.8
#module load gatk/4.2.2.0
module load samtools/1.10
module load bcftools/1.11
module load tabix

# set working dir
cd $SLURM_SUBMIT_DIR

# print jobid to 1st line
echo $SLURM_JOB_ID

# create tmp dir
if [[ ! -e .tmp ]]; then
    mkdir .tmp
fi

# create log dir
if [[ ! -e all_logfiles ]]; then
    mkdir all_logfiles
fi

# create PoN dir
if [[ ! -e PoN ]]; then
    mkdir PoN
fi

# load reference path and other reference files
# for details check script
source ${pipeline_dir}/00_export_pipeline_environment.sh ${organism} ${genome} ${mode}

# fetch file_list file
file_list=$(grep -a "^file list: " main.log | tail -1 | sed 's/^file list: //')

# fetch sample names
samples=$(cat ${file_list} | cut -d, -f1 | sort -u)
vcffiles=""
# check if there are VCFs for all samples
for sample in ${samples}; do
  if [[ ! -e mutect2/${sample}.mutect2.pon.merged.vcf.gz ]]; then
    echo "07_pon: File mutect2/${sample}.mutect2.pon.merged.vcf.gz not found" | tee -a main.log
  else
    vcffiles="${vcffiles}-V mutect2/${sample}.mutect2.pon.merged.vcf.gz "
  fi
done
# count total samples
total_samples=$(echo $vcffiles | tr ' ' '\n' | grep -c '^\-V$')
echo "07_pon: Building PoN with ${total_samples} samples." | tee -a main.log

# fetch date for timestamp
date_for_pon=$(date -I)

# run gatk's GenomicsDBImport
$gatk_path/gatk --java-options "-Djava.io.tmpdir=./.tmp" GenomicsDBImport \
 -R $reference \
 -L $intervals \
 --merge-input-intervals \
 --genomicsdb-workspace-path PoN/pon_db \
 $vcffiles

# run gatk's CreateSomaticPanelOfNormals
$gatk_path/gatk --java-options "-Djava.io.tmpdir=./.tmp" CreateSomaticPanelOfNormals \
 -R $reference \
 -V gendb://PoN/pon_db \
 -O PoN/pon.${total_samples}_samples.${date_for_pon}.vcf.gz

# check if finished
check_finish=$?

# check if command finished
if [[ "$check_finish" == 0 ]]; then
    # log to main
    echo "07_pon: CreateSomaticPanelOfNormals completed." | tee -a main.log
    # calc runtime
    runtime=$( how_long "${start}" h )
    echo "07_pon: Step gatk.CreateSomaticPanelOfNormals.log took ${runtime} hours" | tee -a main.log
    # echo delete dirs and clean-up
    if [[ -e aligned_bam ]]; then
      rm -rf aligned_bam
    fi
    if [[ -e preprocessed_bam ]]; then
      rm -rf preprocessed_bam
    fi
    if [[ -e BQSR ]]; then
      mv BQSR bam
    fi
    rm -rf .tmp
    # rename PoN db
    mv PoN/pon_db PoN/pon_db.${total_samples}_samples.${date_for_pon}
    # change permissions
    find all_logfiles -type f -name "*.log" -exec chmod 644 {} \;
    # move log
    mv gatk.CreateSomaticPanelOfNormals.log all_logfiles
    rm ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.CreateSomaticPanelOfNormals.log
fi

#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=30g
#SBATCH --time=12:00:00
#SBATCH --error=%x.%j.VarScan.log
#SBATCH --output=%x.%j.VarScan.log
ln -f ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.VarScan.log ${tumor}__${normal}.VarScan.log


# scheduler settings

# set date to calculate running time
start=$(date)

# load modules
module load parallel/20210322
module load java/1.8
module load varscan/2.3.8
module load bcftools/1.11
#module load sambamba/0.7.0
module load samtools/1.10
module load tabix

# set working dir
cd $SLURM_SUBMIT_DIR

# print jobid to 1st line
echo $SLURM_JOB_ID

# create output dirs
if [[ ! -e varscan ]]; then
    mkdir -p varscan/pileups
fi

# create tmp dir
if [[ ! -e .tmp ]]; then
    mkdir .tmp
fi

# set bam dir
if [[ ! -e bam ]]; then
    dir=BQSR
else
    dir=bam
fi

# create log dir
if [[ ! -e all_logfiles ]]; then
    mkdir all_logfiles
fi

# load reference path and other reference files
# for details check script
source ${pipeline_dir}/00_export_pipeline_environment.sh ${organism} ${genome} ${mode}

if [[ ! -e varscan/${tumor}__${normal}.varscan.all.Somatic.hc.${mode}.vcf.gz ]]; then
    # double check files
    if [[ -e varscan/pileups/${tumor}.pileup && -e varscan/pileups/${normal}.pileup ]]; then
        # run varscan
        java -jar ${varscan_jar} somatic \
         varscan/pileups/${normal}.pileup \
         varscan/pileups/${tumor}.pileup \
         varscan/${tumor}__${normal}.varscan \
         --output-vcf 1 \
         --strand-filter

        if [[ "$?" == 0 ]]; then
            # first SNVs
            java -jar ${varscan_jar} processSomatic \
              varscan/${tumor}__${normal}.varscan.snp.vcf \
              --min-tumor-freq 0.10 \
              --max-normal-freq 0.05 \
              --p-value 0.05
            # then indels
            java -jar ${varscan_jar} processSomatic \
              varscan/${tumor}__${normal}.varscan.indel.vcf \
              --min-tumor-freq 0.10 \
              --max-normal-freq 0.05 \
              --p-value 0.05
            # compress and index
            index-vcf varscan/${tumor}__${normal}.varscan.snp.Somatic.hc.vcf
            index-vcf varscan/${tumor}__${normal}.varscan.indel.Somatic.hc.vcf
            index-vcf varscan/${tumor}__${normal}.varscan.snp.Germline.hc.vcf
            index-vcf varscan/${tumor}__${normal}.varscan.indel.Germline.hc.vcf
            # concat Somatic
            bcftools concat \
             -a \
             -Oz \
             varscan/${tumor}__${normal}.varscan.snp.Somatic.hc.vcf.gz \
             varscan/${tumor}__${normal}.varscan.indel.Somatic.hc.vcf.gz \
             > varscan/${tumor}__${normal}.varscan.all.Somatic.hc.vcf.gz
            # rename
            mv varscan/${tumor}__${normal}.varscan.all.Somatic.hc.vcf.gz varscan/${tumor}__${normal}.varscan.all.Somatic.hc.${mode}.vcf.gz
            # index
            tabix varscan/${tumor}__${normal}.varscan.all.Somatic.hc.${mode}.vcf.gz
            # concat Germline
            bcftools concat \
             -a \
             -Oz \
             varscan/${tumor}__${normal}.varscan.snp.Germline.hc.vcf.gz \
             varscan/${tumor}__${normal}.varscan.indel.Germline.hc.vcf.gz \
             > varscan/${tumor}__${normal}.varscan.all.Germline.hc.vcf.gz
            # rename
            mv varscan/${tumor}__${normal}.varscan.all.Germline.hc.vcf.gz varscan/${tumor}__${normal}.varscan.all.Germline.hc.${mode}.vcf.gz
            # index
            tabix varscan/${tumor}__${normal}.varscan.all.Germline.hc.${mode}.vcf.gz
        else
            # should give $? == 1
            ls | grep "${RANDOM}"
        fi
    fi
else
  file varscan/${tumor}__${normal}.varscan.all.Germline.hc.wes.vcf.gz | grep empty
  if [[ "$?" == 0 ]]; then
      ls &> /dev/null
  else
      rm varscan/${tumor}__${normal}.varscan.all.Germline.hc.wes.vcf.gz
      # submit calling step
      sbatch --export=\
tumor=${tumor},\
normal=${normal},\
mode=${mode},\
pipeline_dir=${pipeline_dir},\
organism=${organism},\
genome=${genome} \
${pipeline_dir}/06b_call_SNVs_and_indels.varscan.sh
      exit 1
  fi
fi

# check if finished
check_finish=$?

# check if command finished
if [[ "$check_finish" == 0 ]]; then
    # log to main
    echo "06: ${tumor}__${normal} VarScan2 variant calling completed." | tee -a main.log
    # delete pileups
    #rm varscan/pileups/${tumor}.pileup
    # if [[ -e varscan/pileups/${normal}.pileup ]]; then
    #     # how many T are paired with N
    #     paired_tumors=$(grep -c ",${normal}$" tumors_and_normals.csv)
    #     if [[ $(ls varscan/*__${normal}.varscan.all.Somatic.hc.${mode}.vcf.gz | wc -l) == "${paired_tumors}" ]]; then
    #         rm varscan/pileups/${normal}.pileup
    #     fi
    # fi
    # submit annotation
    sbatch --export=\
tumor=${tumor},\
normal=${normal},\
tissue="Germline",\
mode=${mode},\
pipeline_dir=${pipeline_dir},\
organism=${organism},\
genome=${genome} \
${pipeline_dir}/09b_variant_annotation.snpEff-funcotator.sh
    # calc runtime
    runtime=$( how_long "${start}" h )
    echo "06: Step ${tumor}__${normal}.VarScan.log took ${runtime} hours" | tee -a main.log
    # move logfile
    mv ${tumor}__${normal}.VarScan.log all_logfiles
    rm ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.VarScan.log
fi

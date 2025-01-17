#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=30g
#SBATCH --time=5:00:00
#SBATCH --error=%x.%j.CalculateContamination.log
#SBATCH --output=%x.%j.CalculateContamination.log
ln -f ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.CalculateContamination.log ${tumor}__${normal}.CalculateContamination.log


# scheduler settings

# set date to calculate running time
start=$(date)

# load modules
module load java/1.8
#module load gatk/4.2.2.0
module load samtools/1.10

# set working dir
cd $SLURM_SUBMIT_DIR

# print jobid to 1st line
echo $SLURM_JOB_ID

# create dir for contamination
if [[ ! -e contamination ]]; then
    mkdir contamination
fi
# set bam dir
if [[ ! -e bam ]]; then
    dir=BQSR
else
    dir=bam
fi

# create tmp dir
if [[ ! -e .tmp ]]; then
    mkdir .tmp
fi

# create log dir
if [[ ! -e all_logfiles ]]; then
    mkdir all_logfiles
fi

# load reference path and other reference files
# for details check script
source ${pipeline_dir}/00_export_pipeline_environment.sh ${organism} ${genome} ${mode}

if [[ "${normal}" == "PON" ]]; then
    echo "06: No CalculateContamination. Tumor-only mode." | tee -a main.log
    check_finish=0
elif [[ "${gnomad_resource}" == "null" ]]; then
    echo "06: Need AF file (i.e., gnomad for CalculateContamination)... Skipping." | tee -a main.log
    check_finish=0
else
  if [[ ! -e contamination/${tumor}__${normal}.calculatecontamination.table ]]; then
# run gatk's CalculateContamination
$gatk_path/gatk --java-options "-Xmx20G -Djava.io.tmpdir=./.tmp" CalculateContamination \
 -I contamination/${tumor}.getpileupsummaries.table \
 -matched contamination/${normal}.getpileupsummaries.table \
 -O contamination/${tumor}__${normal}.calculatecontamination.table \
 --tumor-segmentation contamination/${tumor}__${normal}.tumorsegmentation.table
  else
    echo "06: CalculateContamination table found for ${tumor}__${normal}" | tee -a main.log
    check_finish=0
  fi
fi

# check if finished
check_finish=$?

# check if command finished
if [[ "$check_finish" == 0 ]]; then
    # log to main
    echo "06: ${tumor}__${normal} CalculateContamination completed." | tee -a main.log
    # calc runtime
    runtime=$( how_long "${start}" h )
    echo "06: Step ${tumor}__${normal}.CalculateContamination.log took ${runtime} hours" | tee -a main.log
    # move logfile
    mv ${tumor}__${normal}.CalculateContamination.log all_logfiles
    rm ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.CalculateContamination.log
fi

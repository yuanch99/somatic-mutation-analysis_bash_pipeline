#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=10
#SBATCH --mem=30g
#SBATCH --error=%x.%j.sambamba.markdup.log
#SBATCH --output=%x.%j.sambamba.markdup.log
ln -f ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.sambamba.markdup.log ${sample}.sambamba.markdup.log

# scheduler settings

# set date to calculate running time
start=$(date)

# load modules
module load sambamba/0.7.0
module load samtools/1.10
module load java/1.8
#module load gatk/4.2.2.0

# set working dir
cd $SLURM_SUBMIT_DIR

# print jobid to 1st line
echo $SLURM_JOB_ID

# add job details
scontrol show job -dd $SLURM_JOB_ID >> ${sample}.sambamba.markdup.log

# load reference path and other reference files
# for details check script
source ${pipeline_dir}/00_export_pipeline_environment.sh ${organism} ${genome} ${mode}

# create dir for preprocessed bam files
if [[ ! -e preprocessed_bam ]]; then
    mkdir preprocessed_bam
fi

# create .tmp dir
if [[ ! -e .tmp ]]; then
    mkdir .tmp
fi

# create log dir
if [[ ! -e all_logfiles ]]; then
    mkdir all_logfiles
fi

# check if preprocess bam exists
if [[ -e preprocessed_bam/${sample}.markdup.bam && $(samtools quickcheck preprocessed_bam/${sample}.markdup.bam && echo 1) == 1 ]]; then
    ls &> /dev/null
else
    # run sambamba to mark duplicates
    if [[ -e aligned_bam/${sample}.merged.bam && $(samtools quickcheck aligned_bam/${sample}.merged.bam && echo 1) == 1 ]]; then
        sambamba markdup \
         --tmpdir=./.tmp \
         -t 10 \
         aligned_bam/${sample}.merged.bam \
         preprocessed_bam/${sample}.markdup.bam
         # prev step already generates index
         # index bam
         # gatk BuildBamIndex -I preprocessed_bam/${sample}.markdup.bam
    else
        echo "04: Resubmitting previous step and increase time by 2hrs (${sample})" | tee -a main.log
        # add two more hours of walltime
        wt=$(( wt + 2 ))
        # resubmit previous script and exit
        sbatch --time=${wt}:00:00 --export=\
sample=${sample},\
wt=${wt},\
mode=${mode},\
pipeline_dir=${pipeline_dir},\
organism=${organism},\
genome=${genome},\
aln_only=${aln_only} \
${pipeline_dir}/03_merge_bams.sambamba.sh
        exit 0
    fi
fi

check_finish=$?

if [[ "$check_finish" == 0 ]]; then
     # remove unnecessary files
     ls preprocessed_bam/${sample}.merged.* &> /dev/null
     if [[ "$?" == 0 ]]; then
         rm preprocessed_bam/${sample}.merged.*
         rm aligned_bam/${sample}.merged.bam
     fi
     # check if there is a walltime
     if [[ -z $wt ]]; then
         wt=$(get_walltime preprocessed_bam/${sample}.markdup.bam)
     fi
     sbatch --time=${wt}:00:00 --export=\
sample=${sample},\
wt=${wt},\
mode=${mode},\
pipeline_dir=${pipeline_dir},\
organism=${organism},\
genome=${genome},\
aln_only=${aln_only} \
${pipeline_dir}/05_run_bqsr.gatk.BaseRecalibrator.sh
     # log to main
     echo "04: duplicate reads have been marked for ${sample} and preceeding files have been deleted." | tee -a main.log
     # calc runtime
     runtime=$( how_long "${start}" h )
     echo "04: Step ${sample}.sambamba.markdup.log took ${runtime} hours" | tee -a main.log
     # move log files to dir
     mv ${sample}.sambamba.markdup.log all_logfiles
     rm ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.sambamba.markdup.log
fi

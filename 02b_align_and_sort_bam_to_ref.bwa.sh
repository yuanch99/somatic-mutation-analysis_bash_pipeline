#!/bin/bash
### slurm
#SBATCH --ntasks-per-node=10
#SBATCH --nodes=1
#SBATCH --mem=60G
#SBATCH --error=%x.%j.bwa.log
#SBATCH --output=%x.%j.bwa.log
ln -f ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.bwa.log ${sample}.${index}.bwa.log

# scheduler settings

# set date to calculate running time
start=$(date)

# load modules
module load sambamba/0.7.0
module load samtools/1.10
module load bwa/0.7.17

# set working dir
cd $SLURM_SUBMIT_DIR

# print jobid to 1st line
echo $SLURM_JOB_ID

# get walltime if not set
if [[ -z $wt ]]; then
    wt=$(scontrol show job -dd $SLURM_JOB_ID | sed -rn 's/.*TimeLimit=(.*)/\1/p' | sed 's/:.*//')
fi

# write job details to log
control show job -dd $SLURM_JOB_ID

# load reference path and other reference files
# for details check script
source ${pipeline_dir}/00_export_pipeline_environment.sh ${organism} ${genome} ${mode}

# create dir for ubam
if [[ ! -e aligned_bam ]]; then
    mkdir aligned_bam
fi

# create .tmp dir
if [[ ! -e .tmp ]]; then
    mkdir .tmp
fi

# create log dir
if [[ ! -e all_logfiles ]]; then
    mkdir all_logfiles
fi

# start finish
check_finish=1

# get readgroup info
rg=$(get_read_group_info ${forward} ${sample})

# check if prev step finished correctly
if [[ -e "aligned_bam/${sample}.${index}.bam" ]]; then
    if [[ $(samtools quickcheck aligned_bam/${sample}.${index}.bam && echo 1) != 1 ]]; then
       echo "resubmitting step and increase time by 2 hrs"
       wt=$(( wt + 2 ))
       rm aligned_bam/${sample}.${index}.bam
       sbatch --time=${wt}:00:00 --export=\
sample=${sample},\
forward=${forward},\
reverse=${reverse},\
mode=${mode},\
pipeline_dir=${pipeline_dir},\
organism=${organism},\
genome=${genome},\
aln_only=${aln_only} \
${pipeline_dir}/02a_check_pairs.sh
       exit 0
    else
       # check if bam is sorted
       if [[ $(samtools quickcheck aligned_bam/${sample}.${index}.sorted.bam && echo 1) != 1 ]]; then
           sambamba sort \
            --tmpdir=./.tmp \
            -m 5GB \
            -t 10 \
            -o aligned_bam/${sample}.${index}.sorted.bam \
               aligned_bam/${sample}.${index}.bam
           # check
           check_finish=0
       else
           check_finish=0
       fi
    fi
else
   # check if input files exist and run aligner
   bwa mem \
    -t 10 \
    -R "${rg}" \
    $reference \
    ${forward} ${reverse}  \
   | sambamba view \
     -S -f bam \
     -o aligned_bam/${sample}.${index}.bam /dev/stdin
   # sort file
   if [[ $(samtools quickcheck aligned_bam/${sample}.${index}.bam && echo 1) == 1 ]]; then
       sambamba sort \
         --tmpdir=./.tmp \
         -m 5GB \
         -t 10 \
         -o aligned_bam/${sample}.${index}.sorted.bam \
         aligned_bam/${sample}.${index}.bam
   fi
   # delete unsorted
   if [[ $(samtools quickcheck aligned_bam/${sample}.${index}.sorted.bam && echo 1) == 1 ]]; then
       rm aligned_bam/${sample}.${index}.bam
       # define check
       check_finish=0
   fi
fi

# if finished successfuly, submit next job
if [[ "$check_finish" == 0 ]]; then
    # delete .tmp files
    if [[ $( echo ${forward} | grep -c "^tmp\/" ) == 1 ]]; then
        if [[ "${#reverse}" -gt 0 ]]; then
            rm "./.tmp/${forward}" "./.tmp/${reverse}"
        else
            rm "./.tmp/${forward}"
        fi
    fi
    # calculate the number of bam files to merge
    expected_bams=$(cat ${file_list} | grep -c "^${sample},")
    found_sorted_bams=$(ls aligned_bam/${sample}.*.sorted.bam | wc -l)
    # check integrity of all files
    samtools quickcheck aligned_bam/${sample}.*.sorted.bam
    # check if all files are done
    if [[ "$?" == 0 && "${expected_bams}" == "${found_sorted_bams}" ]]; then
        # submit next job
        # can switch this to picards MarkDuplicate method
        sbatch --time=${wt}:00:00 --export=\
wt=${wt},\
sample=${sample},\
forward=${forward},\
reverse=${reverse},\
mode=${mode},\
pipeline_dir=${pipeline_dir},\
organism=${organism},\
genome=${genome},\
aln_only=${aln_only} \
${pipeline_dir}/03_merge_bams.sambamba.sh
    fi
    # log to main
    echo "02: ${sample}.${index}.bam has been aligned." | tee -a main.log
    # calc runtime
    runtime=$( how_long "${start}" h )
    echo "02: Step ${sample}.${index}.bwa.log took ${runtime} hours" | tee -a main.log
    # move logfile
    mv ${sample}.${index}.bwa.log all_logfiles
    rm ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.bwa.log
fi

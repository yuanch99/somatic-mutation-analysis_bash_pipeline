#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=30g
#SBATCH --time=15:00:00
#SBATCH --error=%x.%j.haplotypecaller.log
#SBATCH --output=%x.%j.haplotypecaller.log
ln -f ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.haplotypecaller.log ${tumor}__${normal}.haplotypecaller.${index}.log

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

# log date
echo $start

# create output dirs
if [[ ! -e haplotypecaller ]]; then
    mkdir -p haplotypecaller
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

#if [[ "${gvcf}" == 0 ]]; then

#else
# run gatk's haplotypecaller
if [[ ! -e haplotypecaller/${tumor}__${normal}.haplotypecaller.unfiltered.${mode}.merged.vcf ]]; then
echo "fail to find haplotypecaller/${tumor}__${normal}.haplotypecaller.unfiltered.${mode}.merged.vcf"
$gatk_path/gatk --java-options "-Xmx20G -Djava.io.tmpdir=./.tmp" HaplotypeCaller \
 -I ${dir}/${tumor}.bqsr.bam \
 -I ${dir}/${normal}.bqsr.bam \
 -R ${reference} \
 -O haplotypecaller/${tumor}__${normal}.haplotypecaller.unfiltered.${mode}.${index}.vcf \
 --max-mnp-distance 0 \
 -L ${bed30intervals}/${bed}
 #  -bamout mutect2/${tumor}__${normal}.${index}.bam \
 #  --create-output-bam-index \
else
  # for $? = 0
    echo "found haplotypecaller/${tumor}__${normal}.haplotypecaller.unfiltered.${mode}.merged.vcf"
  ls &> /dev/null
fi

# check if finished
check_finish=$?

# check if command finished
if [[ "$check_finish" == 0 ]]; then
    # check if all HaplotypeCaller operations finished
    # first check for files
    ls all_logfiles/${tumor}__${normal}.haplotypecaller.[1-9]*.log &> /dev/null
    # if HC is still running
    if [[ "$?" == 0 ]]; then
        hc_logfiles=$(ls all_logfiles/${tumor}__${normal}.haplotypecaller.[1-9]*.log | wc -l)
        # try to wrap up in one go
        if [[ "${hc_logfiles}" == 29 ]]; then
            # gather vcffiles
            # generate list of files with their own -I flag
            vcffiles=$(ls haplotypecaller/${tumor}__${normal}.haplotypecaller.unfiltered.${mode}.*.vcf  | sort -V | sed 's/^/-I /')
            $gatk_path/gatk GatherVcfs $vcffiles -O haplotypecaller/${tumor}__${normal}.haplotypecaller.unfiltered.${mode}.merged.vcf
            # delete if finished
            if [[ "$?" == 0 ]]; then
                rm haplotypecaller/${tumor}__${normal}.haplotypecaller.unfiltered.${mode}.[1-9]*.vcf
                rm haplotypecaller/${tumor}__${normal}.haplotypecaller.unfiltered.${mode}.[1-9]*.vcf.idx
            fi
            # log to main
            if [[ -e haplotypecaller/${tumor}__${normal}.haplotypecaller.unfiltered.${mode}.merged.vcf ]]; then
                echo "06: all scattered HC calls merged for ${tumor}__${normal} - slurm." | tee -a main.log
            fi
            echo "06: all scattered HC calls merged for ${tumor}__${normal}." | tee -a main.log
            # submit bcftools filtering
            sbatch --export=\
tumor=${tumor},\
normal=${normal},\
mode=${mode},\
pipeline_dir=${pipeline_dir},\
organism=${organism},\
genome=${genome} \
${pipeline_dir}/06c_call_SNVs_and_indels.bcftools.filter.sh
            echo "06: submitted bcftools filtering for ${tumor}__${normal}." | tee -a main.log
            # first scatter
            first_scatter_date=$(ls ${tumor}__${normal}.haplotypecaller.${index}.log ${tumor}__${normal}.haplotypecaller.[0-9]*.log | \
                   parallel 'head -2 {} | tail -1' | parallel date --date={} +%s | sort -n | parallel date --date=@{} | head -1)
            runtime=$( how_long "${first_scatter_date}" h )
            # log
            echo "06: ${tumor}__${normal} HaplotypeCaller took ${runtime} hours" | tee -a main.log
            # concat logfiles
            cat $(ls ${tumor}__${normal}.haplotypecaller.${index}.log all_logfiles/${tumor}__${normal}.haplotypecaller.[0-9]*.log | sort -V) > all_logfiles/${tumor}__${normal}.haplotypecaller.log
            rm $(ls all_logfiles/${tumor}__${normal}.haplotypecaller.[0-9]*.log )
            rm ${tumor}__${normal}.haplotypecaller.${index}.log
            rm ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.haplotypecaller.log
        else
            # log to main
            echo "06: ${tumor}__${normal} HaplotypeCaller variant calling completed for interval ${index}." | tee -a main.log
            # move logfile
            mv ${tumor}__${normal}.haplotypecaller.${index}.log all_logfiles
            rm ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.haplotypecaller.log
        fi
    # no scattered logfiles found
    else
        # check if HC is running
        ls ${tumor}__${normal}.haplotypecaller.[1-9]*.log &> /dev/null
        if [[ "$?" == 0 ]]; then
            # log to main
            echo "06: ${tumor}__${normal} HaplotypeCaller variant calling completed for interval ${index}." | tee -a main.log
            # move logfile
            mv ${tumor}__${normal}.haplotypecaller.${index}.log all_logfiles
            rm ${SLURM_JOB_NAME}.${SLURM_JOB_ID}.haplotypecaller.log
        fi
    fi
fi

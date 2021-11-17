#!/bin/bash

args=($@)
vcf_file=${args[0]}
sample=$( echo $vcf_file | sed 's/\..*//')

for i in `seq 2 ${#args[@]}`; do
    i=$(( i - 1 ))
    gene=${args[i]}
    cat $vcf_file | \
    grep "missense_variant|MODERATE|${gene}|" | \
    awk -v OFS="," -v g=$gene -v s=$sample '{ 
    split($8, x, ";"); 
    split(x[length(x)], y, "="); 
    split(y[2], z, ","); 

    for (i=1; i <= length(z); ++i){ 
        split(z[i], a, "|"); 
        if (a[2] ~ /missense_variant/ && a[4] == g){ 
            print s,$1,$2,$4,$5,a[2],a[3],a[4],a[5],a[11],a[12],a[16],a[17]; 
        }
    }
}'
done

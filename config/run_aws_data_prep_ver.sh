#!/bin/bash

############################################################
# Run E2E RosettaFold analysis on AWS
## Options
# -i (Required) S3 path to input folder
# -o (Required) S3 path to output folder
# -n Input file name (e.g. input.fa)
# -p Prefix to use for output files
# -w Path to working folder on run environment file system
# -d Path to database folder on run environment file system
# -c Max CPU count
# -m Max memory amount (GB)
#
# Example CMD
# ./AWS-RoseTTAFold/run_aws_e2e_ver.sh \
#   -i s3://032243382548-rf-run-data/input \
#   -o s3://032243382548-rf-run-data/output \
#   -n input.fa
#   -w ~/work \
#   -d /fsx \
#   -c 16 \
#   -m 64 \

# make the script stop when error (non-true exit code) is occuredcd
set -e
START="$(date +%s)"
############################################################
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('conda' 'shell.bash' 'hook' 2> /dev/null)"
eval "$__conda_setup"
unset __conda_setup
# <<< conda initialize <<<
############################################################

unset -v SCRIPT PIPEDIR UUID INPUT_S3_FOLDER OUTPUT_S3_FOLDER \
    INPUT_FILE WDIR DBDIR CPU MEM

SCRIPT=`realpath -s $0`
SCRIPTDIR=`dirname $SCRIPT`

while getopts "i:o:n:p:w:d:c:m:" option
do
    case $option in
    i) INPUT_S3_FOLDER=$OPTARG ;; # s3 URI to input folder
    o) OUTPUT_S3_FOLDER=$OPTARG ;; # s3 URI to output folder
    n) INPUT_FILE=$OPTARG ;; # input file name, e.g. input.fa
    p) UUID=$OPTARG ;; # File prefix
    w) WDIR=$OPTARG ;; # path to local working folder
    d) DBDIR=$OPTARG ;; # path to local sequence databases
    c) CPU=$OPTARG ;; # vCPU
    m) MEM=$OPTARG ;; # MEM (GB)
    *) exit 1 ;;
    esac
done

[ -z "$INPUT_S3_FOLDER" ] && { echo "\$INPUT_S3_OBJECT undefined"; exit 1; }
[ -z "$OUTPUT_S3_FOLDER" ] && { echo "\$OUTPUT_S3_FOLDER undefined"; exit 1; }
[ -z "$INPUT_FILE" ] && { INPUT_FILE="input.fa"; }
[ -z "$WDIR" ] && { WDIR=$SCRIPTDIR; }
[ -z "$DBDIR" ] && { DBDIR=$WDIR; }
[ -z "$CPU" ] && { CPU="16"; }
[ -z "$MEM" ] && { MEM="64"; }

if [ -z "$UUID" ]
then
    if [ -z "$AWS_BATCH_JOB_ID" ]
    then
        UUID=`date "+%Y%m%d%H%M%S"`;
    else
        UUID=$AWS_BATCH_JOB_ID;
    fi
fi

IN=$WDIR/input.fa
aws s3 cp $INPUT_S3_FOLDER/$INPUT_FILE $IN

ls $WDIR
LEN=`tail -n1 $IN | wc -m`

conda activate RoseTTAFold

############################################################
# 1. generate MSAs
############################################################
MSA_START="$(date +%s)"

if [ ! -s $WDIR/t000_.msa0.a3m ]
then
    export PIPEDIR=$DBDIR
    echo "Running HHblits"
    $SCRIPTDIR/input_prep/make_msa.sh $IN $WDIR $CPU $MEM $DBDIR
fi

MSA_COUNT=`grep "^>" $WDIR/t000_.msa0.a3m -c`

aws s3 cp $WDIR/t000_.msa0.a3m $OUTPUT_S3_FOLDER/$UUID.msa0.a3m

MSA_DURATION=$[ $(date +%s) - ${MSA_START} ]
echo "${UUID} MSA duration: ${MSA_DURATION} sec"

############################################################
# 2. predict secondary structure for HHsearch run
############################################################
SS_START="$(date +%s)"
if [ ! -s $WDIR/t000_.ss2 ]
then
    export PIPEDIR=$SCRIPTDIR
    echo "Running PSIPRED"
    $SCRIPTDIR/input_prep/make_ss.sh $WDIR/t000_.msa0.a3m $WDIR/t000_.ss2
fi

aws s3 cp $WDIR/t000_.ss2 $OUTPUT_S3_FOLDER/$UUID.ss2

SS_DURATION=$[ $(date +%s) - ${SS_START} ]
echo "${UUID} SS duration: ${SS_DURATION} sec"

############################################################
# 3. search for templates
############################################################
TEMPLATE_START="$(date +%s)"
DB="$DBDIR/pdb100_2021Mar03/pdb100_2021Mar03"
if [ ! -s $WDIR/t000_.hhr ]
then
    echo "Running hhsearch"
    HH="hhsearch -b 50 -B 500 -z 50 -Z 500 -mact 0.05 -cpu $CPU -maxmem $MEM -aliw 100000 -e 100 -p 5.0 -d $DB"
    cat $WDIR/t000_.ss2 $WDIR/t000_.msa0.a3m > $WDIR/t000_.msa0.ss2.a3m
    $HH -i $WDIR/t000_.msa0.ss2.a3m -o $WDIR/t000_.hhr -atab $WDIR/t000_.atab -v 2
fi

TEMPLATE_COUNT=`grep "^No \d*$" $WDIR/t000_.hhr -c`

aws s3 cp $WDIR/t000_.msa0.ss2.a3m $OUTPUT_S3_FOLDER/$UUID.msa0.ss2.a3m
aws s3 cp $WDIR/t000_.hhr $OUTPUT_S3_FOLDER/$UUID.hhr
aws s3 cp $WDIR/t000_.atab $OUTPUT_S3_FOLDER/$UUID.atab

TEMPLATE_DURATION=$[ $(date +%s) - ${TEMPLATE_START} ]
echo "${UUID} template duration: ${TEMPLATE_DURATION} sec"

# Remove the working directory to prevent issue with subsequent testing
rm -rf $WDIR

TOTAL_DATA_PREP_DURATION=$[ $(date +%s) - ${START} ]
echo "${UUID} prep duration: ${TOTAL_DATA_PREP_DURATION} sec"

# Collect metrics
echo "JOB_ID: ${UUID}" >> $WDIR/metrics_data_prep.yaml
echo "INPUT_S3_FOLDER: ${INPUT_S3_FOLDER}" >> $WDIR/metrics_data_prep.yaml
echo "INPUT_FILE: ${INPUT_S3_FILE}" >> $WDIR/metrics_data_prep.yaml
echo "OUTPUT_S3_FOLDER: ${OUTPUT_S3_FOLDER}" >> $WDIR/metrics_data_prep.yaml
echo "WDIR: ${WDIR}" >> $WDIR/metrics_data_prep.yaml
echo "DBDIR: ${DBDIR}" >> $WDIR/metrics_data_prep.yaml
echo "CPU: ${CPU}" >> $WDIR/metrics_data_prep.yaml
echo "MEM: ${MEM}" >> $WDIR/metrics_data_prep.yaml
echo "MSA_COUNT: ${MSA_COUNT}" >> $WDIR/metrics_data_prep.yaml
echo "TEMPLATE_COUNT: ${TEMPLATE_COUNT}" >> $WDIR/metrics_data_prep.yaml
echo "START_TIME: ${START}" >> $WDIR/metrics_data_prep.yaml
echo "MSA_DURATION: ${MSA_DURATION}" >> $WDIR/metrics_data_prep.yaml
echo "SS_DURATION: ${SS_DURATION}" >> $WDIR/metrics_data_prep.yaml
echo "TEMPLATE_DURATION: ${TEMPLATE_DURATION}" >> $WDIR/metrics_data_prep.yaml
echo "TOTAL_DATA_PREP_DURATION: ${TOTAL_DATA_PREP_DURATION}" >> $WDIR/metrics_data_prep.yaml

aws s3 cp $WDIR/metrics_data_prep.yaml $OUTPUT_S3_FOLDER/metrics_data_prep.yaml

echo "Done"
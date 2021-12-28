#!/bin/bash

############################################################
# Run RosettaFold prediction analysis on AWS
## Options
# -i (Required) S3 path to input folder
# -o (Required) S3 path to output folder
# -p Prefix to use for output files
# -w Path to working folder on run environment file system
# -d Path to database folder on run environment file system
# -x Pathe to model weights folder on run environment
# -c Max CPU count
# -m Max memory amount (GB)
#
# Example CMD
# ./AWS-RoseTTAFold/run_aws_e2e_ver.sh \
#   -i s3://032243382548-rf-run-data/input \
#   -o s3://032243382548-rf-run-data/output \
#   -w ~/work \
#   -d /fsx/RoseTTAFold \
#   -x /fsx/RoseTTAFold \
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
    INPUT_FILE WDIR DBDIR MODEL_WEIGHTS_DIR CPU MEM 

SCRIPT=`realpath -s $0`
SCRIPTDIR=`dirname $SCRIPT`

while getopts "i:o:p:w:d:x:c:m:" option
do
    case $option in
    i) INPUT_S3_FOLDER=$OPTARG ;; # s3 URI to input folder
    o) OUTPUT_S3_FOLDER=$OPTARG ;; # s3 URI to output folder    
    p) UUID=$OPTARG ;; # File prefix
    w) WDIR=$OPTARG ;; # path to local working folder
    d) DBDIR=$OPTARG ;; # path to local sequence databases
    x) MODEL_WEIGHTS_DIR=$OPTARG ;; # path to local weights 
    c) CPU=$OPTARG ;; # vCPU
    m) MEM=$OPTARG ;; # MEM (GB)
    *) exit 1 ;;
    esac
done

[ -z "$INPUT_S3_FOLDER" ] && { echo "\$INPUT_S3_OBJECT undefined"; exit 1; }
[ -z "$OUTPUT_S3_FOLDER" ] && { echo "\$OUTPUT_S3_FOLDER undefined"; exit 1; }
[ -z "$WDIR" ] && { WDIR=$SCRIPTDIR; }
[ -z "$DBDIR" ] && { DBDIR=$WDIR; }
[ -z "$MODEL_WEIGHTS_DIR" ] && { MODEL_WEIGHTS_DIR=$WDIR; }
[ -z "$CPU" ] && { CPU="16"; }
[ -z "$MEM" ] && { MEM="64"; }
[ -z "$CUDA_VISIBLE_DEVICES" ] && { CUDA_VISIBLE_DEVICES="99"; }

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

conda activate RoseTTAFold

aws s3 cp $INPUT_S3_FOLDER/$UUID.msa0.a3m $WDIR/t000_.msa0.a3m 
aws s3 cp $INPUT_S3_FOLDER/$UUID.hhr $WDIR/t000_.hhr 
aws s3 cp $INPUT_S3_FOLDER/$UUID.atab $WDIR/t000_.atab 
aws s3 cp $INPUT_S3_FOLDER/metrics.yaml $WDIR/metrics.yaml 

############################################################
# End-to-end prediction
############################################################
PREDICT_START="$(date +%s)"
if [ ! -s $WDIR/t000_.3track.npz ]
then
    echo "Running end-to-end prediction"    
    DB="$DBDIR/pdb100_2021Mar03/pdb100_2021Mar03"

    python $SCRIPTDIR/network/predict_e2e.py \
        -m $MODEL_WEIGHTS_DIR/weights \
        -i $WDIR/t000_.msa0.a3m \
        -o $WDIR/t000_.e2e \
        --hhr $WDIR/t000_.hhr \
        --atab $WDIR/t000_.atab \
        --db $DB
fi

aws s3 cp $WDIR/t000_.e2e.pdb $OUTPUT_S3_FOLDER/$UUID.e2e.pdb
aws s3 cp $WDIR/t000_.e2e_init.pdb $OUTPUT_S3_FOLDER/$UUID.e2e_init.pdb
aws s3 cp $WDIR/t000_.e2e.npz $OUTPUT_S3_FOLDER/$UUID.e2e.npz

TOTAL_PREDICT_DURATION=$[ $(date +%s) - ${PREDICT_START} ]
echo "${UUID} prediction duration: ${TOTAL_PREDICT_DURATION} sec"

# Collect metrics
echo "PREDICT:" >> $WDIR/metrics.yaml
echo "  JOB_ID: ${UUID}" >> $WDIR/metrics.yaml
echo "  INPUT_S3_FOLDER: ${INPUT_S3_FOLDER}" >> $WDIR/metrics.yaml
echo "  OUTPUT_S3_FOLDER: ${OUTPUT_S3_FOLDER}" >> $WDIR/metrics.yaml
echo "  WDIR: ${WDIR}" >> $WDIR/metrics_data_prep.yaml
echo "  DBDIR: ${DBDIR}" >> $WDIR/metrics.yaml
echo "  MODEL_WEIGHTS_DIR: ${MODEL_WEIGHTS_DIR}" >> $WDIR/metrics.yaml
echo "  CPU: ${CPU}" >> $WDIR/metrics.yaml
echo "  MEM: ${MEM}" >> $WDIR/metrics.yaml
echo "  GPU: ${CUDA_VISIBLE_DEVICES}" >> $WDIR/metrics.yaml
echo "  START_TIME: ${PREDICT_START}" >> $WDIR/metrics.yaml
echo "  TOTAL_PREDICT_DURATION: ${TOTAL_PREDICT_DURATION}" >> $WDIR/metrics.yaml

aws s3 cp $WDIR/metrics.yaml $OUTPUT_S3_FOLDER/metrics.yaml

echo "Done"
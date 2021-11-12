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
# -x Pathe to model weights folder on run environment
# -c Max CPU count
# -m Max memory amount (GB)
# -1 Skip MSA creation and use the test file instead?
# -2 Skip SS creation and use the test file instead?
# -3 Skip template searching and use the test file instead?
# -4 Skip prediction and use test files instead?
#
# Example CMD
# ./AWS-RoseTTAFold/run_aws_e2e_ver.sh \
#   -i s3://032243382548-rf-run-data/input \
#   -o s3://032243382548-rf-run-data/output \
#   -n input.fa
#   -w ~/work \
#   -d /fsx/RoseTTAFold \
#   -x /fsx/RoseTTAFold \
#   -c 16 \
#   -m 64 \
#   -1 true

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
    INPUT_FILE WDIR DBDIR MODEL_WEIGHTS_DIR CPU MEM SKIP_MSA \
    SKIP_SS SKIP_HH SKIP_NN

SCRIPT=`realpath -s $0`
SCRIPTDIR=`dirname $SCRIPT`

while getopts "i:o:n:p:w:d:x:c:m:1:2:3:4:" option
do
    case $option in
    i) INPUT_S3_FOLDER=$OPTARG ;; # s3 URI to input folder
    o) OUTPUT_S3_FOLDER=$OPTARG ;; # s3 URI to output folder
    n) INPUT_FILE=$OPTARG ;; # input file name, e.g. input.fa
    p) UUID=$OPTARG ;; # File prefix
    w) WDIR=$OPTARG ;; # path to local working folder
    d) DBDIR=$OPTARG ;; # path to local sequence databases
    x) MODEL_WEIGHTS_DIR=$OPTARG ;; # path to local weights 
    c) CPU=$OPTARG ;; # vCPU
    m) MEM=$OPTARG ;; # MEM (GB)
    1) SKIP_MSA=$OPTARG ;; # Skip MSA creation?
    2) SKIP_SS=$OPTARG ;; # Skip SS creation?
    3) SKIP_HH=$OPTARG ;; # Skip template search?
    4) SKIP_NN=$OPTARG ;; # Skip structure prediction?
    *) exit 1 ;;
    esac
done

[ -z "$INPUT_S3_FOLDER" ] && { echo "\$INPUT_S3_OBJECT undefined"; exit 1; }
[ -z "$OUTPUT_S3_FOLDER" ] && { echo "\$OUTPUT_S3_FOLDER undefined"; exit 1; }
[ -z "$INPUT_FILE" ] && { INPUT_FILE="input.fa"; }
[ -z "$WDIR" ] && { WDIR=$SCRIPTDIR; }
[ -z "$DBDIR" ] && { DBDIR=$WDIR; }
[ -z "$MODEL_WEIGHTS_DIR" ] && { MODEL_WEIGHTS_DIR=$WDIR; }
[ -z "$CPU" ] && { CPU="16"; }
[ -z "$MEM" ] && { MEM="64"; }
[ -z "$SKIP_MSA" ] && { SKIP_MSA=false; }
[ -z "$SKIP_SS" ] && { SKIP_SS=false; }
[ -z "$SKIP_HH" ] && { SKIP_HH=false; }
[ -z "$SKIP_NN" ] && { SKIP_NN=false; }

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

# Copy test data to working folder to skip steps, if specified
[ $SKIP_MSA = true ] && cp test_data/t000_.msa0.a3m $WDIR;
[ $SKIP_SS = true ] && cp test_data/t000_.ss2 $WDIR;
[ $SKIP_HH = true ] && cp test_data/t000_.hhr test_data/t000_.msa0.ss2.a3m test_data/t000_.atab $WDIR;
[ $SKIP_NN = true ] && cp test_data/t000_.e2e.npz test_data/t000_.e2e_init.pdb test_data/t000_.e2e.pdb $WDIR;

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

aws s3 cp $WDIR/t000_.msa0.a3m $OUTPUT_S3_FOLDER/$UUID.msa0.a3m

DURATION=$[ $(date +%s) - ${MSA_START} ]
echo "${UUID} MSA duration: ${DURATION} sec"

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

DURATION=$[ $(date +%s) - ${SS_START} ]
echo "${UUID} SS duration: ${DURATION} sec"

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

aws s3 cp $WDIR/t000_.msa0.ss2.a3m $OUTPUT_S3_FOLDER/$UUID.msa0.ss2.a3m
aws s3 cp $WDIR/t000_.hhr $OUTPUT_S3_FOLDER/$UUID.hhr
aws s3 cp $WDIR/t000_.atab $OUTPUT_S3_FOLDER/$UUID.atab

DURATION=$[ $(date +%s) - ${TEMPLATE_START} ]
echo "${UUID} template duration: ${DURATION} sec"

DURATION=$[ $(date +%s) - ${START} ]
echo "${UUID} prep duration: ${DURATION} sec"

############################################################
# 4. end-to-end prediction
############################################################
PREDICT_START="$(date +%s)"
if [ ! -s $WDIR/t000_.3track.npz ]
then
    echo "Running end-to-end prediction"

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

DURATION=$[ $(date +%s) - ${PREDICT_START} ]
echo "${UUID} predict duration: ${DURATION} sec"

# Remove the working directory to prevent issue with subsequent testing
rm -rf $WDIR

DURATION=$[ $(date +%s) - ${MSA_START} ]
echo "${UUID} E2E duration: ${DURATION} sec"
echo "Done"
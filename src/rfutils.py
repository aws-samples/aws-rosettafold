"""
Helper functions for the AWS-RoseTTAFold notebook.
"""

## Load dependencies
from Bio import SeqIO
from Bio.Seq import Seq
from Bio.SeqRecord import SeqRecord
import boto3
from datetime import datetime
import json
import matplotlib.pyplot as plt
import numpy as np
import os
import pandas as pd
import py3Dmol
from re import sub
import sagemaker
import string
from time import sleep
import uuid


# Get service clients
session = boto3.session.Session()
sm_session = sagemaker.session.Session()
region = session.region_name
role = sagemaker.get_execution_role()


def get_job_name(suffix=None):

    """
    Define a simple job identifier
    """

    if suffix == None:
        return datetime.utcnow().strftime("%Y%m%dT%H%M%S")
    else:
        ## Ensure that the suffix conforms to the Batch requirements, (only letters,
        ## numbers, hyphens, and underscores are allowed).
        suffix = sub("\W", "_", suffix)
        return datetime.utcnow().strftime("%Y%m%dT%H%M%S") + "_" + suffix


def upload_fasta_to_s3(
    record, bucket=sm_session.default_bucket(), job_name=uuid.uuid4()
):

    """
    Create a fasta file and upload it to S3.
    """

    s3 = boto3.client("s3", region_name=region)
    file_out = "_tmp.fasta"
    with open(file_out, "w") as f_out:
        SeqIO.write(record, f_out, "fasta")
    object_name = f"{job_name}/input.fa"
    response = s3.upload_file(file_out, bucket, object_name)
    os.remove(file_out)
    s3_uri = f"s3://{bucket}/{object_name}"
    print(f"Sequence file uploaded to {s3_uri}")
    return s3_uri


def submit_rf_e2e_job(
    bucket=sm_session.default_bucket(),
    job_name=uuid.uuid4(),
    input_file="input.fa",
    job_definition="AWS-RoseTTAFold",
    job_queue="RoseTTAFold-GPU",
    cpu=32,
    mem=96,
    gpu=2,
    db_path="/fsx",
    weigths_path="/fsx",
):

    """
    Submit RoseTTAFold job to AWS Batch.
    """

    working_folder = f"s3://{bucket}/{job_name}"
    batch_client = boto3.client("batch")
    output_pdb_uri = f"{working_folder}/{job_name}.e2e.pdb"

    response = batch_client.submit_job(
        jobDefinition=job_definition,
        jobName=str(job_name),
        jobQueue=job_queue,
        containerOverrides={
            "command": [
                "-i",
                working_folder,
                "-n",
                input_file,
                "-o",
                working_folder,
                "-p",
                job_name,
                "-w",
                "/work",
                "-d",
                db_path,
                "-x",
                weights_path,
                "-c",
                str(cpu),
                "-m",
                str(mem),
            ],
            "environment": [{"name": "CUDA_VISIBLE_DEVICES", "value": str(gpu)}],
            "resourceRequirements": [
                {"value": str(gpu), "type": "GPU"},
                {"value": str(cpu), "type": "VCPU"},
                {"value": str(mem * 1000), "type": "MEMORY"},
            ],
        },
        tags={"output_pdb_uri": output_pdb_uri},
    )
    print(f"Job ID {response['jobId']} submitted")
    return response


def get_batch_job_info(jobId):

    """
    Retrieve and format information about a batch job.
    """

    client = boto3.client("batch")
    job_description = client.describe_jobs(jobs=[jobId])

    output = {
        "jobArn": job_description["jobs"][0]["jobArn"],
        "jobName": job_description["jobs"][0]["jobName"],
        "jobId": job_description["jobs"][0]["jobId"],
        "status": job_description["jobs"][0]["status"],
        "createdAt": datetime.utcfromtimestamp(
            job_description["jobs"][0]["createdAt"] / 1000
        ).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "dependsOn": job_description["jobs"][0]["dependsOn"],
        "tags": job_description["jobs"][0]["tags"],
    }

    if output["status"] in ["STARTING", "RUNNING", "SUCCEEDED", "FAILED"]:
        output["logStreamName"] = job_description["jobs"][0]["container"][
            "logStreamName"
        ]
    return output


def get_batch_logs(logStreamName):

    """
    Retrieve and format logs for batch job.
    """

    client = boto3.client("logs")
    try:
        response = client.get_log_events(
            logGroupName="/aws/batch/job", logStreamName=logStreamName
        )
    except client.meta.client.exceptions.ResourceNotFoundException:
        return f"Log stream {logStreamName} does not exist. Please try again in a few minutes"

    logs = pd.DataFrame.from_dict(response["events"])
    logs.timestamp = logs.timestamp.transform(
        lambda x: datetime.fromtimestamp(x / 1000)
    )
    logs.drop("ingestionTime", axis=1, inplace=True)
    return logs


def wait_for_job_start(jobId, pause=30):

    """
    Pause while a job transitions into a running state.
    """

    status = get_batch_job_info(jobId)["status"]
    print(status)
    while get_batch_job_info(jobId)["status"] in [
        "SUBMITTED",
        "PENDING",
        "RUNNABLE",
        "STARTING",
    ]:
        sleep(30)
        new_status = get_batch_job_info(jobId)["status"]
        if new_status != status:
            print("\n" + new_status)
        else:
            print(".", end="")
        status = new_status


def parse_a3m(filename):

    """
    Read A3M and convert letters into integers in the 0..20 range,
    Copied from https://github.com/RosettaCommons/RoseTTAFold/blob/main/network/parsers.py
    """

    msa = []
    table = str.maketrans(dict.fromkeys(string.ascii_lowercase))
    # read file line by line
    for line in open(filename, "r"):
        # skip labels
        if line[0] == ">":
            continue
        # remove right whitespaces
        line = line.rstrip()
        # remove lowercase letters and append to MSA
        msa.append(line.translate(table))
    # convert letters into numbers
    alphabet = np.array(list("ARNDCQEGHILKMFPSTWYV-"), dtype="|S1").view(np.uint8)
    msa = np.array([list(s) for s in msa], dtype="|S1").view(np.uint8)
    for i in range(alphabet.shape[0]):
        msa[msa == alphabet[i]] = i
    # treat all unknown characters as gaps
    msa[msa > 20] = 20
    return msa


def read_pdb_renum(pdb_filename, Ls=None):

    """
    Process pdb file.
    Copied from https://github.com/sokrypton/ColabFold/blob/main/beta/colabfold.py
    """

    if Ls is not None:
        L_init = 0
        new_chain = {}
        for L, c in zip(Ls, alphabet_list):
            new_chain.update({i: c for i in range(L_init, L_init + L)})
            L_init += L
    n, pdb_out = 1, []
    resnum_, chain_ = 1, "A"
    for line in open(pdb_filename, "r"):
        if line[:4] == "ATOM":
            chain = line[21:22]
            resnum = int(line[22 : 22 + 5])
            if resnum != resnum_ or chain != chain_:
                resnum_, chain_ = resnum, chain
                n += 1
            if Ls is None:
                pdb_out.append("%s%4i%s" % (line[:22], n, line[26:]))
            else:
                pdb_out.append(
                    "%s%s%4i%s" % (line[:21], new_chain[n - 1], n, line[26:])
                )
    return "".join(pdb_out)


def show_pdb(
    pred_output_path,
    show_sidechains=False,
    show_mainchains=False,
    color="lDDT",
    chains=None,
    Ls=None,
    vmin=50,
    vmax=90,
    color_HP=False,
    size=(800, 480),
):

    """
    Create a 3D view of a pdb structure
    Copied from https://github.com/sokrypton/ColabFold/blob/main/beta/colabfold.py
    """

    if chains is None:
        chains = 1 if Ls is None else len(Ls)

    view = py3Dmol.view(
        js="https://3dmol.org/build/3Dmol.js", width=size[0], height=size[1]
    )
    view.addModel(read_pdb_renum(pred_output_path, Ls), "pdb")
    if color == "lDDT":
        view.setStyle(
            {
                "cartoon": {
                    "colorscheme": {
                        "prop": "b",
                        "gradient": "roygb",
                        "min": vmin,
                        "max": vmax,
                    }
                }
            }
        )
    elif color == "rainbow":
        view.setStyle({"cartoon": {"color": "spectrum"}})
    elif color == "chain":
        for n, chain, color in zip(range(chains), alphabet_list, pymol_color_list):
            view.setStyle({"chain": chain}, {"cartoon": {"color": color}})
    if show_sidechains:
        BB = ["C", "O", "N"]
        HP = [
            "ALA",
            "GLY",
            "VAL",
            "ILE",
            "LEU",
            "PHE",
            "MET",
            "PRO",
            "TRP",
            "CYS",
            "TYR",
        ]
        if color_HP:
            view.addStyle(
                {"and": [{"resn": HP}, {"atom": BB, "invert": True}]},
                {"stick": {"colorscheme": "yellowCarbon", "radius": 0.3}},
            )
            view.addStyle(
                {"and": [{"resn": HP, "invert": True}, {"atom": BB, "invert": True}]},
                {"stick": {"colorscheme": "whiteCarbon", "radius": 0.3}},
            )
            view.addStyle(
                {"and": [{"resn": "GLY"}, {"atom": "CA"}]},
                {"sphere": {"colorscheme": "yellowCarbon", "radius": 0.3}},
            )
            view.addStyle(
                {"and": [{"resn": "PRO"}, {"atom": ["C", "O"], "invert": True}]},
                {"stick": {"colorscheme": "yellowCarbon", "radius": 0.3}},
            )
        else:
            view.addStyle(
                {
                    "and": [
                        {"resn": ["GLY", "PRO"], "invert": True},
                        {"atom": BB, "invert": True},
                    ]
                },
                {"stick": {"colorscheme": f"WhiteCarbon", "radius": 0.3}},
            )
            view.addStyle(
                {"and": [{"resn": "GLY"}, {"atom": "CA"}]},
                {"sphere": {"colorscheme": f"WhiteCarbon", "radius": 0.3}},
            )
            view.addStyle(
                {"and": [{"resn": "PRO"}, {"atom": ["C", "O"], "invert": True}]},
                {"stick": {"colorscheme": f"WhiteCarbon", "radius": 0.3}},
            )
    if show_mainchains:
        BB = ["C", "O", "N", "CA"]
        view.addStyle(
            {"atom": BB}, {"stick": {"colorscheme": f"WhiteCarbon", "radius": 0.3}}
        )
    view.zoomTo()
    return view


def plot_plddt_legend(dpi=100):

    """
    Create 3D Plot legend
    Copied from https://github.com/sokrypton/ColabFold/blob/main/beta/colabfold.py
    """

    thresh = [
        "plDDT:",
        "Very low (<50)",
        "Low (60)",
        "OK (70)",
        "Confident (80)",
        "Very high (>90)",
    ]
    plt.figure(figsize=(1, 0.1), dpi=dpi)
    ########################################
    for c in ["#FFFFFF", "#FF0000", "#FFFF00", "#00FF00", "#00FFFF", "#0000FF"]:
        plt.bar(0, 0, color=c)
    plt.legend(
        thresh,
        frameon=False,
        loc="center",
        ncol=6,
        handletextpad=1,
        columnspacing=1,
        markerscale=0.5,
    )
    plt.axis(False)
    return plt


def plot_msa_info(msa):

    """
    Plot a representation of the MSA coverage.
    Copied from https://github.com/sokrypton/ColabFold/blob/main/beta/colabfold.py
    """

    msa_arr = np.unique(msa, axis=0)
    total_msa_size = len(msa_arr)
    print(f"\n{total_msa_size} Sequences Found in Total\n")

    if total_msa_size > 1:
        plt.figure(figsize=(8, 5), dpi=100)
        plt.title("Sequence coverage")
        seqid = (msa[0] == msa_arr).mean(-1)
        seqid_sort = seqid.argsort()
        non_gaps = (msa_arr != 20).astype(float)
        non_gaps[non_gaps == 0] = np.nan
        plt.imshow(
            non_gaps[seqid_sort] * seqid[seqid_sort, None],
            interpolation="nearest",
            aspect="auto",
            cmap="rainbow_r",
            vmin=0,
            vmax=1,
            origin="lower",
            extent=(0, msa_arr.shape[1], 0, msa_arr.shape[0]),
        )
        plt.plot((msa_arr != 20).sum(0), color="black")
        plt.xlim(0, msa_arr.shape[1])
        plt.ylim(0, msa_arr.shape[0])
        plt.colorbar(
            label="Sequence identity to query",
        )
        plt.xlabel("Positions")
        plt.ylabel("Sequences")
        plt.show()
    else:
        print("Unable to display MSA of length 1")


def submit_rf_data_prep_job(
    bucket=sm_session.default_bucket(),
    job_name=uuid.uuid4(),
    input_file="input.fa",
    job_definition="AWS-RoseTTAFold-CPU",
    job_queue="AWS-RoseTTAFold-CPU",
    cpu=16,
    mem=64,
    db_path="/fsx",
):

    """
    Submit a RoseTTAFold data prep job (i.e. the first half of the e2e workflow) to AWS Batch.
    """

    working_folder = f"s3://{bucket}/{job_name}"
    batch_client = boto3.client("batch")
    output_msa_uri = f"{working_folder}/{job_name}.msa0.a3m"
    output_hhr_uri = f"{working_folder}/{job_name}.hhr"
    output_atab_uri = f"{working_folder}/{job_name}.atab"

    response = batch_client.submit_job(
        jobDefinition=job_definition,
        jobName=str(job_name),
        jobQueue=job_queue,
        containerOverrides={
            "command": [
                "/bin/bash",
                "run_aws_data_prep_ver.sh",
                "-i",
                working_folder,
                "-n",
                input_file,
                "-o",
                working_folder,
                "-p",
                job_name,
                "-w",
                "/work",
                "-d",
                db_path,
                "-c",
                str(cpu),
                "-m",
                str(mem),
            ],
            "resourceRequirements": [
                {"value": str(cpu), "type": "VCPU"},
                {"value": str(mem * 1000), "type": "MEMORY"},
            ],
        },
        tags={
            "output_msa_uri": output_msa_uri,
            "output_hhr_uri": output_hhr_uri,
            "output_atab_uri": output_atab_uri,
        },
    )
    print(f"Job ID {response['jobId']} submitted")
    return response


def submit_rf_predict_job(
    bucket=sm_session.default_bucket(),
    job_name=uuid.uuid4(),
    job_definition="AWS-RoseTTAFold-GPU",
    job_queue="AWS-RoseTTAFold-GPU",
    cpu=32,
    mem=96,
    gpu=2,
    db_path="/fsx",
    weights_path="/fsx",
    depends_on="",
):

    """
    Submit a RoseTTAFold prediction job (i.e. the second half of the e2e workflow) to AWS Batch.
    """

    working_folder = f"s3://{bucket}/{job_name}"
    batch_client = boto3.client("batch")
    output_pdb_uri = f"{working_folder}/{job_name}.e2e.pdb"

    response = batch_client.submit_job(
        jobDefinition=job_definition,
        jobName=str(job_name),
        jobQueue=job_queue,
        dependsOn=[{"jobId": depends_on, "type": "SEQUENTIAL"}],
        containerOverrides={
            "command": [
                "/bin/bash",
                "run_aws_predict_ver.sh",
                "-i",
                working_folder,
                "-o",
                working_folder,
                "-p",
                job_name,
                "-w",
                "/work",
                "-d",
                db_path,
                "-x",
                weights_path,
                "-c",
                str(cpu),
                "-m",
                str(mem),
            ],
            "environment": [{"name": "CUDA_VISIBLE_DEVICES", "value": str(gpu)}],
            "resourceRequirements": [
                {"value": str(gpu), "type": "GPU"},
                {"value": str(cpu), "type": "VCPU"},
                {"value": str(mem * 1000), "type": "MEMORY"},
            ],
        },
        tags={"output_pdb_uri": output_pdb_uri},
    )
    print(f"Job ID {response['jobId']} submitted")
    return response


def submit_2_step_job(
    bucket=sm_session.default_bucket(),
    job_name=uuid.uuid4(),
    data_prep_input_file="input.fa",
    data_prep_job_definition="AWS-RoseTTAFold-CPU",
    data_prep_queue="AWS-RoseTTAFold-CPU",
    data_prep_cpu=16,
    data_prep_mem=64,
    predict_job_definition="AWS-RoseTTAFold-GPU",
    predict_queue="AWS-RoseTTAFold-GPU",
    predict_cpu=32,
    predict_mem=96,
    predict_gpu=2,
    db_path="/fsx",
    weights_path="/fsx",
):

    """
    Submit a 2-step RoseTTAFold prediction job  to AWS Batch.
    """

    working_folder = f"s3://{bucket}/{job_name}"
    batch_client = boto3.client("batch")
    output_pdb_uri = f"{working_folder}/{job_name}.e2e.pdb"

    data_prep_response = submit_rf_data_prep_job(
        bucket=bucket,
        job_name=job_name,
        input_file=data_prep_input_file,
        job_definition=data_prep_job_definition,
        job_queue=data_prep_queue,
        cpu=data_prep_cpu,
        mem=data_prep_mem,
        db_path=db_path,
    )

    predict_response = submit_rf_predict_job(
        bucket=bucket,
        job_name=job_name,
        job_definition=predict_job_definition,
        job_queue=predict_queue,
        cpu=predict_cpu,
        mem=predict_mem,
        gpu=predict_gpu,
        db_path=db_path,
        weights_path=weights_path,
        depends_on=data_prep_response["jobId"],
    )

    print(
        f"Data prep job ID {data_prep_response['jobId']} and predict job ID {predict_response['jobId']} submitted"
    )
    return [data_prep_response, predict_response]


def list_recent_jobs(job_queues, hrs_in_past=1):

    """
    Display recently-submitted jobs.
    """

    batch_client = boto3.client("batch")
    result = []
    for queue in job_queues:
        recent_queue_jobs = batch_client.list_jobs(
            jobQueue=queue,
            filters=[
                {
                    "name": "AFTER_CREATED_AT",
                    "values": [
                        str(round(datetime.now().timestamp()) - (hrs_in_past * 3600))
                    ],
                }
            ],
        )
        result = result + recent_queue_jobs["jobSummaryList"]

    return result


def get_rf_job_info(
    cpu_queue="AWS-RoseTTAFold-CPU", gpu_queue="AWS-RoseTTAFold-GPU", hrs_in_past=1
):

    """
    Display information about recent AWS-RoseTTAFold jobs
    """
    from datetime import datetime

    batch_client = boto3.client("batch")
    recent_jobs = list_recent_jobs([cpu_queue, gpu_queue], hrs_in_past)
    recent_job_df = pd.DataFrame.from_dict(recent_jobs)
    detail_list = batch_client.describe_jobs(jobs=recent_job_df.jobId.to_list())
    list_of_lists = []
    for job in detail_list["jobs"]:
        resource_dict = {}
        for resource in job["container"]["resourceRequirements"]:
            resource_dict[resource["type"]] = resource["value"]
        row = [
            job["jobName"],
            job["jobId"],
            job["jobQueue"],
            job["status"],
            datetime.fromtimestamp(job["createdAt"] / 1000),
            datetime.fromtimestamp(job["startedAt"] / 1000)
            if "startedAt" in job
            else "NaT",
            datetime.fromtimestamp(job["stoppedAt"] / 1000)
            if "stoppedAt" in job
            else "NaT",
            str(
                datetime.fromtimestamp(job["stoppedAt"] / 1000)
                - datetime.fromtimestamp(job["startedAt"] / 1000)
            )
            if "startedAt" in job and "stoppedAt" in job
            else "NaN",
            (job["stoppedAt"] / 1000) - (job["startedAt"] / 1000)
            if "startedAt" in job and "stoppedAt" in job
            else "NaN",
            job["jobDefinition"],
            job["container"]["logStreamName"]
            if "logStreamName" in job["container"]
            else "",
            int(resource_dict["VCPU"]),
            int(float(resource_dict["MEMORY"]) / 1000),
            int(resource_dict["GPU"]) if "GPU" in resource_dict else 0,
        ]
        list_of_lists.append(row)

    return pd.DataFrame(
        list_of_lists,
        columns=[
            "jobName",
            "jobId",
            "jobQueue",
            "status",
            "createdAt",
            "startedAt",
            "stoppedAt",
            "duration",
            "duration_sec",
            "jobDefinition",
            "logStreamName",
            "vCPUs",
            "mem_GB",
            "GPUs",
        ],
    )

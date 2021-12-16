# AWS RoseTTAFold
Infrastructure template and Jupyter notebooks for running RoseTTAFold on AWS Batch. 

## Overview
Proteins are large biomolecules that play an important role in the body. Knowing the physical structure of proteins is key to understanding their function. However, it can be difficult and expensive to determine the structure of many proteins experimentally. One alternative is to [predict these structures using machine learning algorithms. Several high-profile research teams have released such algorithms, including AlphaFold 2 (from [DeepMind](https://deepmind.com/blog/article/alphafold-a-solution-to-a-50-year-old-grand-challenge-in-biology)) and RoseTTAFold (From the [Baker lab at the University of Washington](https://www.ipd.uw.edu/2021/07/rosettafold-accurate-protein-structure-prediction-accessible-to-all/)). Their work was important enough for Science magazine to name it the ["2021 Breakthrough of the Year"](https://www.science.org/content/article/breakthrough-2021).

Both AlphaFold 2 and RoseTTAFold use a multi-track transformer architecture trained on known protein templates to predict the structure of unknown peptide sequences. These predictions are heavily GPU-dependent and take anywhere from minutes to days to complete. The input features for these predictions include multiple sequence alignment (MSA) data. MSA algorithms are CPU-dependent and can themselves require several hours of processing time. 

Running both the MSA and structure prediction steps in the same computing environment can be cost inefficient, because the expensive GPU resources required for the prediction sit unused while the MSA step runs. Instead, using a high performance computing (HPC) service like [AWS Batch](https://aws.amazon.com/batch/) allows us to run each step as a containerized job with the best fit of CPU, memory, and GPU resources.

This project demonstrates how to provision and use AWS services for running the RoseTTAFold protein folding algorithm on AWS Batch. 

## Setup
1. Log into the AWS Console.
2. Click on *Launch Stack*:

    [![Launch Stack](img/LaunchStack.jpg)](https://console.aws.amazon.com/cloudformation/home#/stacks/create/review?templateURL=https://aws-hcls-ml.s3.amazonaws.com/blog_post_support_materials/aws-RoseTTAFold/cfn.yaml)

3. For Stack Name, enter a unique name.
4. Select an availability zone from the dropdown menu.
5. Acknowledge that AWS CloudFormation might create IAM resources and then click *Create Stack*.
6. It will take 10 minutes for CloudFormation to create the stack and another 15 minutes for CodeBuild to build and publish the container (25 minutes total). Please wait for both of these tasks to finish before you submit any analysis jobs. 
7. Download and extract the RoseTTAFold network weights (under [Rosetta-DL Software license](https://files.ipd.uw.edu/pub/RoseTTAFold/Rosetta-DL_LICENSE.txt)), and sequence and structure databases to the newly-created FSx for Lustre file system. There are two ways to do this:

### Option 1
In the AWS Console, navigate to **EC2 > Launch Templates**, select the template beginning with "aws-rosettafold-launch-template-", and then **Actions > Launch instance from template**. Select the Amazon Linux 2 AMI and launch the instance into the public subnet with a public IP. SSH into the instance and download/extract your network weights and reference data of interest to the attached volume at `/fsx/aws-rosettafold-ref-data` (i.e. Installation steps 3 and 5 from the [RoseTTAFold public repository](https://github.com/RosettaCommons/RoseTTAFold))

### Option 2
Create a new S3 bucket in your region of interest. Spin up an EC2 instance in a public subnet in the same region and use this to download and extract the network weights and reference data. Once this is complete, copy the extracted data to S3. In the AWS Console, navigate to **FSx > File Systems** and select the FSx for Lustre file system created above. Link this file system to your new S3 bucket using [these instructions](https://docs.aws.amazon.com/fsx/latest/LustreGuide/create-dra-linked-data-repo.html#create-linked-dra). Specify `/aws-rosettafold-ref-data` as the file system path when creating the data repository association. This is a good option if you want to create multiple stacks without downloading and extracting the reference data multiple times. Note that the first job you submit using this data repository will cause the FSx file system to transfer and compress 3 TB of reference data from S3. This process may require as many as six hours to complete. Alternatively, you can preload files into the file system by following [these instructions](https://docs.aws.amazon.com/fsx/latest/LustreGuide/preload-file-contents-hsm-dra.html).

Once this is complete, your FSx for Lustre file system should look like this (file sizes are uncompressed):

```
/fsx
└── /aws-rosettafold-ref-data
    ├── /bfd
    │   ├── bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt_a3m.ffdata (1.4 TB)
    │   ├── bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt_a3m.ffindex (1.7 GB)
    │   ├── bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt_cs219.ffdata (15.7 GB)
    │   ├── bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt_cs219.ffindex (1.6 GB)
    │   ├── bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt_hhm.ffdata (304.4 GB)
    │   └── bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt_hhm.ffindex (123.6 MB)
    ├── /pdb100_2021Mar03
    │   ├── LICENSE (20.4 KB)
    │   ├── pdb100_2021Mar03_a3m.ffdata (633.9 GB)
    │   ├── pdb100_2021Mar03_a3m.ffindex (3.9 MB)
    │   ├── pdb100_2021Mar03_cs219.ffdata (41.8 MB)
    │   ├── pdb100_2021Mar03_cs219.ffindex (2.8 MB)
    │   ├── pdb100_2021Mar03_hhm.ffdata (6.8 GB)
    │   ├── pdb100_2021Mar03_hhm.ffindex (3.4 GB)
    │   ├── pdb100_2021Mar03_pdb.ffdata (26.2 GB)
    │   └── pdb100_2021Mar03_pdb.ffindex (3.7 MB)
    ├── /UniRef30_2020_06
    │   ├── UniRef30_2020_06_a3m.ffdata (139.6 GB)
    │   ├── UniRef30_2020_06_a3m.ffindex (671.0 MG)
    │   ├── UniRef30_2020_06_cs219.ffdata (6.0 GB)
    │   ├── UniRef30_2020_06_cs219.ffindex (605.0 MB)
    │   ├── UniRef30_2020_06_hhm.ffdata (34.1 GB)
    │   ├── UniRef30_2020_06_hhm.ffindex (19.4 MB)
    │   └── UniRef30_2020_06.md5sums (379.0 B)
    └── /weights
        ├── RF2t.pt (126 MB KB)
        ├── Rosetta-DL_LICENSE.txt (3.1 KB)
        ├── RoseTTAFold_e2e.pt (533 MB)
        └── RoseTTAFold_pyrosetta.pt (506 MB)

```
8. Clone the CodeCommit repository created by CloudFormation to a Jupyter Notebook environment of your choice.
9. Use the `AWS-RoseTTAFold.ipynb` and `CASP14-Analysis.ipynb` notebooks to submit protein sequences for analysis.

## Architecture

![AWS-RoseTTAFold Architecture](img/AWS-RoseTTAFold-arch.png)

This project creates two computing environments in AWS Batch to run the "end-to-end" protein folding workflow in RoseTTAFold. The first of these uses the optimal mix of `c4`, `m4`, and `r4` spot instance types based on the vCPU and memory requirements specified in the Batch job. The second environment uses `g4dn` on-demand instances to balance performance, availability, and cost.

A scientist can create structure prediction jobs using one of the two included Jupyter notebooks. `AWS-RoseTTAFold.ipynb` demonstrates how to submit a single analysis job and view the results. `CASP14-Analysis.ipynb` demonstrates how to submit multiple jobs at once using the CASP14 target list. In both of these cases, submitting a sequence for analysis creates two Batch jobs, one for data preparation (using the CPU computing environment) and a second, dependent job for structure prediction (using the GPU computing environment). 

Both the data preparation and structure prediction use the same Docker image for execution. This image, based on the public Nvidia CUDA image for Ubuntu 20, includes the v1.1 release of the public [RoseTTAFold repository](https://github.com/RosettaCommons/RoseTTAFold), as well as additional scripts for integrating with AWS services. CodeBuild will automatically download this container definition and build the required image during stack creation. However, end users can make changes to this image by pushing to the CodeCommit repository included in the stack. For example, users could replace the included MSA algorithm ([hhblits](https://github.com/soedinglab/hh-suite)) with an alternative like [MMseqs2](https://github.com/soedinglab/MMseqs2) or replace the RoseTTAFold network with an alternative like AlphaFold 2 or [Uni-Fold](https://github.com/dptech-corp/Uni-Fold).

## Costs
This workload costs approximately $217 per month to maintain, plus another $2.56 per job.

## Deployment

![AWS-RoseTTAFold Dewployment](img/AWS-RoseTTAFold-deploy.png)

Running the CloudFormation template at `config/cfn.yaml` creates the following resources in the specified availability zone:
1. A new VPC with a private subnet, public subnet, NAT gateway, internet gateway, elastic IP, route tables, and S3 gateway endpoint.
2. A FSx Lustre file system with 1.2 TiB of storage and 120 MB/s throughput capacity. This file system can be linked to an S3 bucket for loading the required reference data when the first job executes.
3. An EC2 launch template for mounting the FSX file system to Batch compute instances.
4. A set of AWS Batch compute environments, job queues, and job definitions for running the CPU-dependent data prep job and a second for the GPU-dependent prediction job.
5. CodeCommit, CodeBuild, CodePipeline, and ECR resources for building and publishing the Batch container image. When CloudFormation creates the CodeCommit repository, it populates it with a zipped version of this repository stored at `s3://aws-rosettafold-ref-data`. CodeBuild uses this repository as its source and adds additional code from release 1.1 of the public [RoseTTAFold repository](https://github.com/RosettaCommons/RoseTTAFold). CodeBuild then publishes the resulting container image to ECR, where Batch jobs can use it as needed.

## Licensing
This library is licensed under the MIT-0 License. See the LICENSE file for more information.

The University of Washington has made the code and data in the [RoseTTAFold public repository](https://github.com/RosettaCommons) available under an [MIT license](https://github.com/RosettaCommons/RoseTTAFold/blob/main/LICENSE). However, the model weights used for prediction are only available for internal, non-profit, non-commercial research use only. Fore information, please see the [full license agreement](https://files.ipd.uw.edu/pub/RoseTTAFold/Rosetta-DL_LICENSE.txt) and contact the University of Washington for details.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## More Information
- [University of Washington Institute for Protein Design](https://www.ipd.uw.edu/2021/07/rosettafold-accurate-protein-structure-prediction-accessible-to-all/)
- [RoseTTAFold Paper](https://www.ipd.uw.edu/wp-content/uploads/2021/07/Baek_etal_Science2021_RoseTTAFold.pdf)
- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/)
- [CloudFormation Documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html)
- [Explaination of the RoseTTAFold and AlphaFold 2 architectures](https://www.youtube.com/watch?v=Rfw7thgGTwI)
- [David Baker's TED talk on protein design](https://www.ted.com/talks/david_baker_5_challenges_we_could_solve_by_designing_new_proteins)
- [AWS ML Blog Post on running AlphaFold 2 on Amazon EC2](https://aws.amazon.com/blogs/machine-learning/run-alphafold-v2-0-on-amazon-ec2/)
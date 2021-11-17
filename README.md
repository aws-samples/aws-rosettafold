# AWS RoseTTAFold
## Overview
Dockerfile and wrapper scripts for running RoseTTAFold on AWS. 

![AWS-RoseTTAFold Architecture](img/AWS-RoseTTAFold-arch.png)

## Getting Started
1. Submit a request to bloyal@amazon.com to grant your AWS account of interest access to the necessary S3 buckets. NOTE: These will be replaced with public buckets before the workload is shared externally.
2. Create a new CloudFormation stack using the template at `config/cfn.yaml`.
3. Once the stack creation is finished (about 15 minutes), check to make sure that CodeBuild has finished building and publishing the Docker container to ECR before submitting any jobs to AWS Batch.

Because the reference data is loaded lazily into FSx, the first job you submit to a new stack may take several hours. Once the data transfer has finished, subsequent jobs will be much faster.

## Links
- [University of Washington Institute for Protein Design](https://www.ipd.uw.edu/2021/07/rosettafold-accurate-protein-structure-prediction-accessible-to-all/)
- [RoseTTAFold Paper](https://www.ipd.uw.edu/wp-content/uploads/2021/07/Baek_etal_Science2021_RoseTTAFold.pdf)
- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/)
- [CloudFormation Documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html)
- [Explaination of the RoseTTAFold and AlphaFold 2 architectures](https://www.youtube.com/watch?v=Rfw7thgGTwI)
- [David Baker's TED talk on protein design](https://www.ted.com/talks/david_baker_5_challenges_we_could_solve_by_designing_new_proteins)
- [AWS ML Blog Post on running AlphaFold 2 on Amazon EC2](https://aws.amazon.com/blogs/machine-learning/run-alphafold-v2-0-on-amazon-ec2/)
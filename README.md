# AWS RoseTTAFold
## Overview
Dockerfile and wrapper scripts for running RoseTTAFold on AWS. 

![AWS-RoseTTAFold Architecture](img/AWS-RoseTTAFold-arch.png)

https://files.ipd.uw.edu/pub/RoseTTAFold/Rosetta-DL_LICENSE.txt

## Getting Started
1. Verify that the "All G and VT Spot Instance Requests" service quota for your account of interest is at least 48 (preferably 96).
2. Submit a request to bloyal@amazon.com to grant your AWS account of interest access to the necessary S3 buckets. NOTE: The repository maintainers will replace these with public buckets before the workload is published externally.
3. Create a new CloudFormation stack with the template at `config/cfn.yaml`.
4. It will take 17 minutes for CloudFormation to create the stack and another 5 minutes for CodeBuild to build and publish the container. Please wait for both of these tasks to finish before you submit any analysis jobs. 
5. Clone the CodeCommit repository created by CloudFormation to a Jupyter Notebook environment of your choice.
6. Use the `AWS-RoseTTAFold.ipynb` and `CASP14-Analysis.ipynb` notebooks to submit protein sequences for analysis. Note that the first job you submit will cause the FSx file system to transfer and compress 3 TB of reference data from S3. This process will require 3-4 hours to complete. The duration of subsequent jobs will depend on the length and complexity of the protein sequence.

## Costs
This workload costs approximately $270 per month to maintain, plus another $2.56 per job.

## Licensing
Software, data, or weights belonging to the Rosetta-DL package ("Software") have been developed by the contributing researchers and institutions of the Rosetta Commons ("Developers") and made available through the University of Washington ("UW") for internal, non-profit, non-commercial research use. For more information about the Rosetta Commons, please see www.rosettacommons.org. The full non-commercial license agreement is available [here](https://files.ipd.uw.edu/pub/RoseTTAFold/Rosetta-DL_LICENSE.txt).

## Links
- [University of Washington Institute for Protein Design](https://www.ipd.uw.edu/2021/07/rosettafold-accurate-protein-structure-prediction-accessible-to-all/)
- [RoseTTAFold Paper](https://www.ipd.uw.edu/wp-content/uploads/2021/07/Baek_etal_Science2021_RoseTTAFold.pdf)
- [AWS Batch Documentation](https://docs.aws.amazon.com/batch/)
- [CloudFormation Documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html)
- [Explaination of the RoseTTAFold and AlphaFold 2 architectures](https://www.youtube.com/watch?v=Rfw7thgGTwI)
- [David Baker's TED talk on protein design](https://www.ted.com/talks/david_baker_5_challenges_we_could_solve_by_designing_new_proteins)
- [AWS ML Blog Post on running AlphaFold 2 on Amazon EC2](https://aws.amazon.com/blogs/machine-learning/run-alphafold-v2-0-on-amazon-ec2/)
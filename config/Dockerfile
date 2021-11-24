# Start with a copy of the NVIDIA cuda image maintained in ECR to avoid
# DockerHub download limits.
FROM public.ecr.aws/n9j4s2r8/cuda:11.1.1-base-ubuntu20.04

# Install basic tools
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    unzip

# Install miniconda and awscli
RUN curl -L -o ~/miniconda.sh https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh \
    && chmod +x ~/miniconda.sh \
    && ~/miniconda.sh -b -p /opt/conda \
    && rm ~/miniconda.sh \
    && /opt/conda/bin/conda update conda \
    && /opt/conda/bin/conda install -c conda-forge awscli

# Copy selected code from v1.1 of the RoseTTAFold repo, available at 
# https://github.com/RosettaCommons/RoseTTAFold
COPY RoseTTAFold RoseTTAFold/
WORKDIR /RoseTTAFold

# Install lddt, cs-blast, and libgomp1
RUN ./install_dependencies.sh
RUN /opt/conda/bin/conda env create -f RoseTTAFold-linux.yml \
    && /opt/conda/bin/conda clean -ya
RUN apt-get install libgomp1

# Add the AWS-RoseTTAFold scripts
COPY run_aws_e2e_ver.sh .
COPY run_aws_data_prep_ver.sh .
COPY run_aws_predict_ver.sh .

# Clean up unecessary files to save space
RUN rm -rf \
    *.gz \
    *.zip \
    *.yml \
    install_dependencies.sh 

# Create a directory to mount the FSx Lustre file system with ref data
VOLUME /fsx

# Activate conda
RUN ["/bin/bash", "-c", \
    "/opt/conda/bin/activate", \
    "/opt/conda/bin/conda init bash", \
    "source $HOME/.bashrc"]
ENV PATH /opt/conda/bin:$PATH

# Define the default run command. Batch will overwrite this at run time.
CMD ["/bin/bash", "run_aws_e2e_ver.sh"] 

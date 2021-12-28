# Start with a copy of the cuda image maintained by Nvidia to avoid
FROM nvcr.io/nvidia/cuda:11.4.2-base-ubuntu20.04

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

# Download and unzip v1.1 of the RoseTTAFold repository, available at 
# https://github.com/RosettaCommons/RoseTTAFold
RUN wget https://github.com/RosettaCommons/RoseTTAFold/archive/refs/tags/v1.1.0.zip \
    && unzip v1.1.0.zip \
    && mv RoseTTAFold-1.1.0 /RoseTTAFold \
    && rm v1.1.0.zip
WORKDIR /RoseTTAFold

# Install lddt, cs-blast, and libgomp1
RUN ./install_dependencies.sh
RUN /opt/conda/bin/conda env create -f RoseTTAFold-linux.yml \
    && /opt/conda/bin/conda clean -ya
RUN apt-get install libgomp1

# Add the AWS-RoseTTAFold scripts
COPY run_aws_data_prep_ver.sh .
COPY run_aws_predict_ver.sh .
COPY download_ref_data.sh .

# Clean up unecessary files to save space
RUN rm -rf \
    example \
    folding \
    *.gz \
    *.zip \
    *.yml \
    install_dependencies.sh 

# Create a directory to mount the FSx Lustre file system with ref data
VOLUME /fsx

# Activate conda\
RUN ["/bin/bash", "-c", \
    "/opt/conda/bin/activate", \
    "/opt/conda/bin/conda init bash", \
    "source $HOME/.bashrc"]
ENV PATH /opt/conda/bin:$PATH

# Define the default run command. Batch will overwrite this at run time.
CMD ["/bin/bash"] 

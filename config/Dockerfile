FROM public.ecr.aws/n9j4s2r8/cuda:11.1.1-base-ubuntu20.04

RUN apt-get update && apt-get install -y \
    wget \
    curl \
    unzip

RUN curl -L -o ~/miniconda.sh https://repo.continuum.io/miniconda/Miniconda3-latest-Linux-x86_64.sh \
 && chmod +x ~/miniconda.sh \
 && ~/miniconda.sh -b -p /opt/conda \
 && rm ~/miniconda.sh \
 && /opt/conda/bin/conda update conda \
 && /opt/conda/bin/conda install -c conda-forge awscli

RUN wget https://github.com/RosettaCommons/RoseTTAFold/archive/main.zip \
 && unzip main.zip \
 && mv RoseTTAFold-main /RoseTTAFold \
 && rm main.zip

WORKDIR /RoseTTAFold

RUN ./install_dependencies.sh
RUN /opt/conda/bin/conda env create -f RoseTTAFold-linux.yml \
 && /opt/conda/bin/conda clean -ya

RUN apt-get install libgomp1

COPY run_aws_e2e_ver.sh .
COPY run_aws_data_prep_ver.sh .
COPY run_aws_predict_ver.sh .
COPY ../data data

RUN rm -rf \
 example \
 folding \
 *.gz \
 *.zip \
 *.yml \
 install_dependencies.sh 

VOLUME /fsx
RUN ["/bin/bash", "-c", \
 "/opt/conda/bin/activate", \
 "/opt/conda/bin/conda init bash", \
 "source $HOME/.bashrc"]
ENV PATH /opt/conda/bin:$PATH

CMD ["/bin/bash", "run_aws_e2e_ver.sh"] 

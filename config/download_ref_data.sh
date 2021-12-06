#!/bin/bash
yum install wget tar -y
cd /fsx

# NOTE: The RoseTTAFold network weights are covered under the Rosetta-DL software license.
# Please see https://files.ipd.uw.edu/pub/RoseTTAFold/Rosetta-DL_LICENSE.txt for more
# information.
wget https://files.ipd.uw.edu/pub/RoseTTAFold/weights.tar.gz
tar xfz weights.tar.gz
rm weights.tar.gz

# uniref30 [46G]
wget http://wwwuser.gwdg.de/~compbiol/uniclust/2020_06/UniRef30_2020_06_hhsuite.tar.gz
mkdir -p UniRef30_2020_06
tar xfz UniRef30_2020_06_hhsuite.tar.gz -C ./UniRef30_2020_06
rm UniRef30_2020_06_hhsuite.tar.gz

# structure templates (including *_a3m.ffdata, *_a3m.ffindex) [over 100G]
wget https://files.ipd.uw.edu/pub/RoseTTAFold/pdb100_2021Mar03.tar.gz
tar xfz pdb100_2021Mar03.tar.gz
rm pdb100_2021Mar03.sorted_opt.tar.gz

# BFD [272G]
wget https://bfd.mmseqs.com/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt.tar.gz
mkdir -p bfd
tar xfz bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt.tar.gz -C ./bfd
rm bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt.tar.gz

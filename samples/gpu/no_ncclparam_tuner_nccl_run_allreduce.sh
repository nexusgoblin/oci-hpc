#!/bin/bash
set -e

# number of times to run the nccl test to stress the GPUs and RDMA network. This is different from -n iterations parameter of nccl allreduce which is set below using $iter
max=$1

# This assume, the hostfile  passed is already ordered based on their rackId
if [ -n "$2" ]; then
  hostfile=$2
else
  hostfile="/tmp/ordered_hostfile_system_name"
fi

ORDEREDMACHINEFILE="ordered_hostfile_system_name"
ORDEREDRANKMACHINEFILE="rankfile_system_name"
echo INPUTFILE
cat $hostfile

# will generate rack-aware ordered host file
source /etc/os-release
if [ $ID == "ol" ] || [ $ID == "centos" ] ; then
    python3 /home/opc/node_ordering_by_rack.py --input_file $hostfile > /dev/null
    homedirectory=/home/opc
elif [ $ID == "debian" ] || [ $ID == "ubuntu" ] ; then
    python3 /home/ubuntu/node_ordering_by_rack.py --input_file $hostfile > /dev/null
    homedirectory=/home/ubuntu
fi

hostfile=$ORDEREDMACHINEFILE
rankfile=$ORDEREDRANKMACHINEFILE

echo ORDEREDMACHINEFILE
cat $ORDEREDMACHINEFILE
echo ORDEREDRANKMACHINEFILE
cat $ORDEREDRANKMACHINEFILE

# The number of GPUs to use for the test.  Has to be multiplier of 8.  If not passed, all GPUs will be used. 
if [ -n "$3" ]; then
  np=$3
else
  np=$((`less $hostfile | wc -l` * 8 ))
fi

logfile="nccl_run_allreduce.sh.log"

for x in $(seq 1 1 $max)
do

  echo $x
  echo $x >> $logfile
  date >> $logfile

  rankfile=$rankfile; np=$np ; iter=20;

  mpivars_path=`ls /usr/mpi/gcc/openmpi-*/bin/mpivars.sh`
  source $mpivars_path

  if [[ "$mpivars_path" == "" ]]; then echo "Could not find MPIPATH"; exit; fi

first_node=`head $hostfile -n 1`
shape=`ssh $first_node 'curl -sH "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/' | jq .shape`
if [ $shape == \"BM.GPU.B4.8\" ] || [ $shape == \"BM.GPU.A100-v2.8\" ]
then
  var_UCX_NET_DEVICES=mlx5_0:1
elif [ $shape == \"BM.GPU4.8\" ]
then
  var_UCX_NET_DEVICES=mlx5_4:1
fi

  # final version
  # all NCCL parameters are at /etc/nccl.conf on each compute node.
  mpirun --mca pml ucx \
  --bind-to numa \
  --mca coll ^hcoll \
  -x UCX_TLS=ud,self,sm \
  -x UCX_NET_DEVICES=${var_UCX_NET_DEVICES} \
  -x HCOLL_ENABLE_MCAST_ALL=0 \
  -x coll_hcoll_enable=0 \
  -x NCCL_TUNER_PLUGIN=$homedirectory/libnccl-ocituner.so.1.0.1 \
  --np $np --rankfile $rankfile /opt/oci-hpc/nccl-test/build/all_reduce_perf -b1G -e10G -i$((1024*1024*1024*9)) -n $iter >>  $logfile

  tail -n 32 $logfile


done



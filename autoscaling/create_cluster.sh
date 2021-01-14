#!/bin/bash

if [ $# -eq 0 ] || [ $# -eq 1 ]
then
  echo "No enough arguments supplied, please supply number of nodes and cluster name"
  exit
fi
date=`date '+%Y%m%d%H%M'`
scripts=`realpath $0`
folder=`dirname $scripts`
cp -r $folder/tf_init $folder/clusters/$2
cd $folder/clusters/$2
sed "s/##NODES##/$1/g;s/##NAME##/$2/g;s/##SHAPE##/$3/g;s/##CN##/$4/g" $folder/tf_init/variables.tf > variables.tf
echo "Started to build $2"
start=`date +%s`
terraform init > $folder/logs/create_$2_${date}.log
echo $1 $3 $4 >> currently_building
terraform apply -auto-approve >> $folder/logs/create_$2_${date}.log 2>&1
status=$?
end=`date +%s`
runtime=$((end-start))
if [ $status -eq 0 ]
  then
    echo "Successfully created $2 in $runtime seconds"
    rm currently_building
  else
    echo "Could not create $2 with $1 nodes in $runtime seconds"
    rm currently_building
    terraform destroy -auto-approve > $folder/logs/delete_$2_${date}.log 2>&1
fi

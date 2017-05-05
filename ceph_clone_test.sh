#!/bin/bash

###################################################################################
# Config
###################################################################################

# How many rbd images should be created parallely 
THREADS=1  
# How many times the whole test should be run 
ITERATIONS=1
# How many copies of the TEST_FILE should be copied to RBD image
COPY_ITERATIONS=1

CEPH_POOL=''
CEPH_USER=''
IMAGE_NAME=''
MOUNT_DIR='/tmp'
# file to be copied to rbd storage
TEST_FILE='./some_large_file_ideally_centos7_4.1GB_image_just_because'
LOG_FILE="./log"
VERBOSE_LOG_FILE=false

###################################################################################
# Preflight checks
###################################################################################

# REQUIRES MODULE rdb -> modprobe rbd
if ! lsmod | grep "rbd" &> /dev/null
then
  echo "Module rbd is not loaded"
  exit 1
fi

# Requires package parallel
command -v parallel >/dev/null 2>&1 || { echo >&2 "I require 'parallel' but it's not installed.  Aborting."; exit 1; }
command -v rbd >/dev/null 2>&1 || { echo >&2 "I require 'rbd' but it's not installed.  Aborting."; exit 1; }

# Check test file
if [ ! -f "$TEST_FILE" ]
then
  echo "Test file '$TEST_FILE' not found"
  exit 1
fi

# Test credentials
rbd --pool $CEPH_POOL --id $CEPH_USER ls >/dev/null 2>&1 || { echo >&2 "There was an error connecting via rbd.  Aborting."; exit 1; }

###################################################################################
# Fun functions
###################################################################################

function iterate_and_measure { 
  echo -e "iter\tstart time\trun(s)\texit\tcommand" >> $LOG_FILE
  for i in $(seq 1 $THREADS)
  do 
    START_TIME=$(date "+%H:%M:%S")
    # Append iterator to imagename
    CMD="$1$i"
    echo "/usr/bin/time -a -o $LOG_FILE -f '$i\t$START_TIME\t%e\t%x\t$CMD' $CMD"
  done | parallel
}

function log_shizz {
  if [ "$the_world_is_flat" = true ] 
  then
    echo "********************************************************************" | tee -a $LOG_FILE
    echo "  $1" | tee -a $LOG_FILE
  else
    echo "********************************************************************"
    echo "  $1"
  fi
}

function ceph_test_parallel {
  for i in $(seq 1 $ITERATIONS)
  do
    # Create phase
    
    log_shizz "Parallel image '$IMAGE_NAME' clone. Threads $THREADS. Iterations: $i/$ITERATIONS."
    iterate_and_measure "rbd --pool $CEPH_POOL --id $CEPH_USER clone --image-feature layering $IMAGE_NAME@snap $CEPH_POOL/$IMAGE_NAME-"

    log_shizz "Creating mount dirs"
    parallel mkdir -v ::: $(seq -f "$MOUNT_DIR/$IMAGE_NAME-%01g" $THREADS)

    log_shizz "rbd map images"
    parallel rbd --pool $CEPH_POOL --id $CEPH_USER map ::: $(seq -f "$IMAGE_NAME-%01g" $THREADS)
    
    log_shizz "Mount images"
    parallel mount -v /dev/rbd/$CEPH_POOL/{} $MOUNT_DIR/{} ::: $(seq -f "$IMAGE_NAME-%01g" $THREADS)

    # Copy test data
    log_shizz "Copy test data. Number of copies to each image: $COPY_ITERATIONS"
    for i in $(seq 1 $COPY_ITERATIONS)
    do
      parallel rsync -vh $TEST_FILE $MOUNT_DIR/{}/test-data-$i ::: $(seq -f "$IMAGE_NAME-%01g" $THREADS)
    done

    # Show copied data sizes

    for i in $(seq 1 $THREADS); do du -hs $MOUNT_DIR/$IMAGE_NAME-$i ; done  | tee -a $LOG_FILE 

    # Clean phase

    log_shizz "Umount images"
    parallel umount -v ::: $(seq -f "$MOUNT_DIR/$IMAGE_NAME-%01g" $THREADS)

    log_shizz "rbd unmap images"
    parallel rbd --pool $CEPH_POOL --id $CEPH_USER unmap ::: $(seq -f "$IMAGE_NAME-%01g" $THREADS)

    log_shizz "Parallel image '$IMAGE_NAME' remove. Threads $THREADS. Iterations: $i/$ITERATIONS."
    iterate_and_measure "rbd --pool $CEPH_POOL --id $CEPH_USER rm $IMAGE_NAME-"

    log_shizz "Removing mount dirs"
    parallel rm -rf -v ::: $(seq -f "$MOUNT_DIR/$IMAGE_NAME-%01g" $THREADS)
  done
}

###################################################################################
# Prepare base image
###################################################################################
log_shizz "Preparing base image and snapshot"
rbd --pool $CEPH_POOL --id $CEPH_USER create $IMAGE_NAME --image-feature layering --size 204800
rbd --pool $CEPH_POOL --id $CEPH_USER map $IMAGE_NAME
mkfs.ext4 -m0 "/dev/rbd/$CEPH_POOL/$IMAGE_NAME"
rbd --pool $CEPH_POOL --id $CEPH_USER unmap $IMAGE_NAME

# create snapshot
rbd --pool $CEPH_POOL --id $CEPH_USER snap create "$IMAGE_NAME@snap"
rbd --pool $CEPH_POOL --id $CEPH_USER snap protect "$IMAGE_NAME@snap"

###################################################################################
# Main shizz byzz
###################################################################################

ceph_test_parallel

###################################################################################
# Cleanup
###################################################################################

log_shizz "Cleaning base image and snapshot"
rbd --pool $CEPH_POOL --id $CEPH_USER snap unprotect "$IMAGE_NAME@snap"
rbd --pool $CEPH_POOL --id $CEPH_USER snap rm "$IMAGE_NAME@snap"

rbd --pool $CEPH_POOL --id $CEPH_USER rm $IMAGE_NAME

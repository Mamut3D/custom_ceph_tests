# custom_ceph_tests

### What it custom_ceph_test.sh does
  - creates 200 GB test image in ceph via rbd and formats it to ext4
  - creates snapshot test image
  - creates n clones based on $THREADS
  - copies $TEST_FILE n times ($COPY_ITERATIONS)  to each image clone
  - paraelly deleates all the clones
  - whole test runs n times based on $ITERATIONS
  
**Results are creation and delete time of each clone stored in log**

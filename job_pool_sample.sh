#!/bin/bash

. job_pool.sh

function foobar()
{
    # do something
    true
}   

# initialize the job pool to allow 3 parallel jobs and echo commands
job_pool_init 3 0

# run jobs
job_pool_run sleep 1
job_pool_run sleep 2
job_pool_run sleep 3
job_pool_run foobar
job_pool_run foobar
job_pool_run /bin/false

# wait until all jobs complete before continuing
job_pool_wait

# more jobs
job_pool_run /bin/false
job_pool_run sleep 1
job_pool_run sleep 2
job_pool_run foobar

# don't forget to shut down the job pool
job_pool_shutdown

# check the $job_pool_nerrors for the number of jobs that exited non-zero
echo "job_pool_nerrors: ${job_pool_nerrors}"

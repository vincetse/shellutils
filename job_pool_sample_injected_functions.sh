#!/bin/bash

. job_pool.sh

#####################################################
# Demonstration of function injection into each job #
#####################################################

echo "Demonstration of function injection into each job:"

# sleep some time ($1) then echo something ($2)
function sleep_n_echo()
{
    sleep "$1"
    echo "$2"
}

# Injected function that will be called before each job
# 
# Print which worker is starting which job
function print_starting_job()
{
    echo " # _job_pool_worker-${id}: Starting job: ${cmd} $(echo "${args[@]}" | xargs | tr '\v' ' ')"
}

# Injected function that will be called afetr each job
# 
# Kill all workers if the local variable "result" from _job_pool_worker
# indicates that the job failed
function kill_workers()
{
    echo " # _job_pool_worker-${id}: Finished job: ${cmd} $(echo "${args[@]}" | xargs | tr '\v' ' ')"

    # result is undefined in this script, but will be defined when
    # the function is injected in _job_pool_worker
    if [[ "${result}" != "0" ]]; then
        # get the pids of all workers:
        # - each worker's process is named after the current script (here, job_pool_sample.sh),
        #   so we use this name to get the pids
        # - we do not include the current script's pid ($$) as it is not a worker,
        #   (we do not want to kill the script itself, only the workers)
        local workers_pids=("$(pgrep -f "$0" | grep -v $$)")
        kill ${workers_pids[@]} &> /dev/null &
    fi
}

# allow 3 parallel jobs, and kill all jobs at the first fail using "kill_workers" function
job_pool_init 3 0 print_starting_job kill_workers

# simulate 3 jobs, where one fails before the others are finished, and interrupts the others
job_pool_run sleep_n_echo 3 a   # job 1
job_pool_run /bin/false         # job 2
job_pool_run sleep_n_echo 3 b   # job 3

# the job 2 will kill all other running workers, using the function "kill_workers"
# (that is ran after processing each job)

job_pool_shutdown

echo -e "\nOnly the failed job exited, the others did not because they were canceled."

# `shellutils`
`shellutils` is collection of command line utilities that I tossed together as a way to save shell scripts that may be useful so that I don't have to keep rewriting them.  I wrote them to be used with bash, but I suspect they make work in ksh or sh too.

## `job_pool.sh`
`job_pool.sh` is a library that you can source from a shell script so that you can keep n number of jobs running at any one time instead of kicking them off all at the same time and saturating the host.  It uses a pre-fork type of model and start a bunch of working to kick off your jobs.

The following is a sample program that uses it.

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

The interface consists of four public functions and one variable that reports how many jobs exited non-zero.

    # \brief initializes the job pool
    # \param[in] pool_size  number of parallel jobs allowed
    # \param[in] echo_command  1 to turn on echo, 0 to turn off
    function job_pool_init()
    
    # \brief waits for all queued up jobs to complete and shuts down the job pool
    function job_pool_shutdown()
    
    # \brief run a job in the job pool
    function job_pool_run()
    
    # \brief waits for all queued up jobs to complete before starting new jobs
    # This function actually fakes a wait by telling the workers to exit
    # when done with the jobs and then restarting them.
    function job_pool_wait()

    # \brief variable to check for number of non-zero exits
    job_pool_nerrors=0

This was inspired by [a discussion on StackOverflow](http://stackoverflow.com/questions/6441509/how-to-write-a-process-pool-bash-shell).

## `genpass.sh`
`genpass.sh` is a random password generator, it will produce a random password of the desired length which is suitable
for manual entering via the keyboard.
- Requires uuencode to be in the search path
- Usage: genpass.sh \<length\> (default: 8)

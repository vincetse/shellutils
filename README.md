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

## `naud.sh`

Naud is a bash script for normalizing audio files using the normalize-audio utility. 
It is specifically aimed at mp3, ogg and flac files.

### NAME
naud - adjust levels of flac, mp3 or ogg files by decoding to wav, running them 
through normalize-audio(1) and then re-encoding.

### SYNOPSIS
naud [OPTION1]... [FILE1]... [OPTION2]... [FILE2]...

### DESCRIPTION
Adjust levels of flac, mp3 or ogg files by encoding to wav, running them through 
normalize-audio and then re-encoding. This requires as much extra disk space as the 
sum of all flac, mp3 or ogg files to be decoded. Unless the encoded file type is 
different from the input file type the original file will be overwritten.

A file is any parameter not beginning with a "-", for naud a file may also be a 
directory. An option is any parameter beginning with "-". Options, when set, will 
affect any later file or directory specified. Any option may be set to a different 
value later on after which the new value is used for all later files.

### OPTIONS
-o TARGET

TARGET is one of "same", "ogg", "vorbis", "mp3", or "flac". "vorbis" is a synonym for 
"ogg". The default for this option is "same". When set to "same" this option causes 
naud to re-encode the files using their original encoding type and will overwrite the 
original file. Any other option forces re-encoding to the type given in the option. 
This is mainly used for re-encoding flac files into another type such as mp3 or ogg. 
It may also be useful if you own an old or badly designed audio player which can play 
only mp3 files although, generally, it is not a good idea to encode mp3 to ogg or 
vice-versa. There is little point in re-encoding both mp3 and ogg files to flac.

-t DIRECTORY

Because naud can use a lot of temporary space this option allows you to specify the 
temporary directory to use. Naud will create temporary directories under DIRECTORY for 
its use. The default for this option is the value of the environmental variable TMP.

### Pass-through Options
The following options are passed through to normalize-audio:
- -a AMP
- -g ADJ
- -n
- -T THR
- -b
- -m
- -v
- -q

Although -q and -v are likely to be of little use as naud captures all the output of 
normalize-audio.

Because naud allows options to span multiple files this presents a problem if you want 
to *turn off* an option. In this case all the above options which are passed to 
normalize-audio can be switched off by adding a "-" as a suffix. Thus to switch off 
"-a 2" you would use "-a-", to switch off -n you would use "-n-", etc. It is permitted 
to use an option that has a value mulitple times, in this case the value used will 
change to the latest. Please note that long options for mormalize-audio (e.g. 
--clipping) are not permitted.

### SINGLE MODE
If a single file is specified then naud will normalize that file. File lists are 
allowed thus "\*" will expand to all files in the current directory and naud will 
treat this as a list of single files. Naud will ignore all non-flac, non-mp3 and 
non-ogg files.

### BATCH MODE
If a directory is specified then naud will batch normalize all audio files in that 
directory. The difference between this and normalizing a single file is that during 
batch normalization the volume of the files relative to each other remains unaffected. 
This is useful when normalizing whole albums. The assumption here is that whole albums 
will reside in their own unique directory. In practice this is not usually a problem.

### TAGS
Naud will preserve the following audio tags:
- Title
- Artist
- Album
- Track number
- Year
- Genre
- Comments

### LOSSY COMPRESSION
For files that use lossy compression (mp3 and ogg) naud will attempt as best it can to 
re-create the quality of the original file. This is a tricky subject and involves some 
magical incantations. The natures of mp3 and ogg are such that it is impossible to 
make an exact re-creation of the original. Naud will do its best to keep the quality 
of the original file without overdoing it and making files that are over-large. There 
are a number of heuristics that are used for mp3: for very high bit rate files a 
constant bit rate encoding will be used, for very low bit rate files then average bit 
rate encoding will be used, for the more common cases naud will encode mp3 files using 
a variable bit rate scheme. When encoding lossy files from flac files the defaults 
used are "-V 0" to lame for mp3 and "-q 6" to oggenc for ogg. These values are set 
near the top of the naud script and are therefore easily changed, take a look at the 
lame and oggenc man pages to see what these values mean.

### REQUIREMENTS
Naud is a bash script and relies on other programs for normalizing audio files. The 
dependencies are:
- normalize-audio
- sox
- lame
- vorbis-tools
- flac

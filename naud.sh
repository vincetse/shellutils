#!/bin/bash

###################################################################
# naud - Normalize mp3, ogg and flac files
# (c) Copyright - 2013 Geoff Clements
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.
###################################################################

###################################################################
# Two useful web pages about quality settings
# http://lame.cvs.sourceforge.net/viewvc/lame/lame/doc/html/usage.html
# http://www.vorbis.com/faq/#quality
###################################################################

###################################################################
# Quality setting when encoding from flacs
# Feel free to change to your liking
###################################################################
LAME_DEF_QUAL="-V 0"
OGG_DEF_QUAL="-q 6"

###################################################################
# O traveller stray not beyond this point - here be dragons!
###################################################################

shopt -u nullglob

# Set up temporary directory
TMPDIR=${TMP:-/tmp}
WDIRS=() # Cache of all temp dirs, used for cleanup
trap "{ cleanup ; exit 255 ;}" INT TERM
trap "{ cleanup ; exit 0 ;}" EXIT

TARGET=same # keep encoded files the same type as the decoded ones
TARGET_OPTS="same ogg vorbis mp3 flac"

#########################################
# Cleanup functions
#########################################
cleanup () {
  for tdir in "${WDIRS[@]}"
  do
    rm -r "${tdir}" 2>/dev/null
  done
  job_pool_shutdown
}

die () {
  echo "$1"
  cleanup
  exit 1
}

#########################################
# Find programs which we need
# Can't do without these
#########################################
SOX=$(which sox) || die "Cannot find sox"

SOXI=$(which soxi) || die "Cannot find soxi"

NORM=$(which normalize-audio) || \
NORM=$(which normalize) || die "Cannot find normalize-audio"

LAME=$(which lame) || die "Cannot find lame"

OGGENC=$(which oggenc) || die "Cannot find oggenc"

FLAC=$(which flac) || die "Cannot find flac"

numprocs=$(nproc 2>/dev/null)
if [ ${#numprocs} -eq 0 ]
then
  numprocs=$(grep -c "^core id" /proc/cpuinfo)
fi

#########################################
# Job Pool
# Copyright (c) 2012 Vince Tse
# with changes by Geoff Clements
#########################################
# end-of-jobs marker
job_pool_end_of_jobs="JOBPOOL_END_OF_JOBS"

# job queue used to send jobs to the workers
job_pool_job_queue=/tmp/job_pool_job_queue_$$

# where to run results to
job_pool_result_log=/tmp/job_pool_result_log_$$

# toggle command echoing
job_pool_echo_command=0

# number of parallel jobs allowed.  also used to determine if job_pool_init
# has been called when jobs are queued.
job_pool_pool_size=-1

# \brief variable to check for number of non-zero exits
job_pool_nerrors=0

################################################################################
# private functions
################################################################################

# \brief debug output
function _job_pool_echo()
{
    if [[ "${job_pool_echo_command}" == "1" ]]; then
        echo $@
    fi
}

# \brief cleans up
function _job_pool_cleanup()
{
    rm -f ${job_pool_job_queue} ${job_pool_result_log}
}

# \brief signal handler
function _job_pool_exit_handler()
{
    _job_pool_stop_workers
    _job_pool_cleanup
}

# \brief print the exit codes for each command
# \param[in] result_log  the file where the exit codes are written to
function _job_pool_print_result_log()
{
    job_pool_nerrors=$(grep ^ERROR "${job_pool_result_log}" | wc -l)
    cat "${job_pool_result_log}" | sed -e 's/^ERROR//'
}

# \brief the worker function that is called when we fork off worker processes
# \param[in] id  the worker ID
# \param[in] job_queue  the fifo to read jobs from
# \param[in] result_log  the temporary log file to write exit codes to
function _job_pool_worker()
{
    local id=$1
    local job_queue=$2
    local result_log=$3
    local cmd=
    local args=

    exec 7<> ${job_queue}
    while [[ "${cmd}" != "${job_pool_end_of_jobs}" && -e "${job_queue}" ]]; do
        # workers block on the exclusive lock to read the job queue
        flock --exclusive 7
        IFS=$'\v'
        read cmd args <${job_queue}
        set -- ${args}
        unset IFS
        flock --unlock 7
        # the worker should exit if it sees the end-of-job marker or run the
        # job otherwise and save its exit code to the result log.
        if [[ "${cmd}" == "${job_pool_end_of_jobs}" ]]; then
            # write it one more time for the next sibling so that everyone
            # will know we are exiting.
            echo "${cmd}" >&7
        else
            _job_pool_echo "### _job_pool_worker-${id}: ${cmd}"
            # run the job
            { ${cmd} "$@" ; }
            # now check the exit code and prepend "ERROR" to the result log entry
            # which we will use to count errors and then strip out later.
            local result=$?
            local status=
            if [[ "${result}" != "0" ]]; then
                status=ERROR
            fi
            # now write the error to the log, making sure multiple processes
            # don't trample over each other.
            exec 8<> ${result_log}
            flock --exclusive 8
            _job_pool_echo "${status}job_pool: exited ${result}: ${cmd} $@" >> ${result_log}
            flock --unlock 8
            exec 8>&-
            _job_pool_echo "### _job_pool_worker-${id}: exited ${result}: ${cmd} $@"
        fi
    done
    exec 7>&-
}

# \brief sends message to worker processes to stop
function _job_pool_stop_workers()
{
    # send message to workers to exit, and wait for them to stop before
    # doing cleanup.
    echo ${job_pool_end_of_jobs} >> ${job_pool_job_queue}
    wait
}

# \brief fork off the workers
# \param[in] job_queue  the fifo used to send jobs to the workers
# \param[in] result_log  the temporary log file to write exit codes to
function _job_pool_start_workers()
{
    local job_queue=$1
    local result_log=$2
    for ((i=0; i<${job_pool_pool_size}; i++)); do
        _job_pool_worker ${i} ${job_queue} ${result_log} &
    done
}

################################################################################
# public functions
################################################################################

# \brief initializes the job pool
# \param[in] pool_size  number of parallel jobs allowed
# \param[in] echo_command  1 to turn on echo, 0 to turn off
function job_pool_init()
{
    local pool_size=$1
    local echo_command=$2

    # set the global attibutes
    job_pool_pool_size=${pool_size:=1}
    job_pool_echo_command=${echo_command:=0}

    # create the fifo job queue and create the exit code log
    rm -rf ${job_pool_job_queue} ${job_pool_result_log}
    mkfifo ${job_pool_job_queue}
    touch ${job_pool_result_log}

    # fork off the workers
    _job_pool_start_workers ${job_pool_job_queue} ${job_pool_result_log}
}

# \brief waits for all queued up jobs to complete and shuts down the job pool
function job_pool_shutdown()
{
    _job_pool_stop_workers
    _job_pool_print_result_log
    _job_pool_cleanup
}

# \brief run a job in the job pool
function job_pool_run()
{
    if [[ "${job_pool_pool_size}" == "-1" ]]; then
        job_pool_init
    fi
    printf "%s\v" "$@" >> ${job_pool_job_queue}
    echo >> ${job_pool_job_queue}
}

# \brief waits for all queued up jobs to complete before starting new jobs
# This function actually fakes a wait by telling the workers to exit
# when done with the jobs and then restarting them.
function job_pool_wait()
{
    _job_pool_stop_workers
    _job_pool_start_workers ${job_pool_job_queue} ${job_pool_result_log}
}
#########################################
# End of Job Pool
#########################################

identify_file () {
  # Return array of audio parameters for the passed file: file_data
  # $1 = path to file
  #
  # The array of file data that is generated looks like this
  # 0 = path to input file
  # 1 = input file encoding
  # 2 = bit rate (bits per second)
  # 3 = number of channels
  # 4 = title
  # 5 = artist
  # 6 = album
  # 7 = date or year
  # 8 = track number
  # 9 = genre
  # 10 = comment
  
  # First save file name
  local file_data=("${1}") #0
  
  # Ignore .m3u files as soxi obligingly decodes them - the b*****d
  if echo "${1}" | grep -qv -e ".m3u$"
  then
    # Then get type, bitrate and channels
    if file_data+=($(${SOXI} -t "${1}" 2>/dev/null)) #1
    then
      file_data+=($(${SOXI} -B "${1}")) #2
      file_data+=($(${SOXI} -c "${1}")) #3
		      
      # Now get id tags
      local tags=$(${SOXI} -a "${1}")
      file_data+=("$(echo "${tags}" | grep -i '^title=' | cut -d = -f 2)") #4
      file_data+=("$(echo "${tags}" | grep -i '^artist=' | cut -d = -f 2)") #5
      file_data+=("$(echo "${tags}" | grep -i '^album=' | cut -d = -f 2)") #6
      file_data+=("$(echo "${tags}" | grep -iE '^date=|^year=' | cut -d = -f 2)") #7
      file_data+=("$(echo "${tags}" | grep -i '^tracknumber=' | cut -d = -f 2)") #8
      file_data+=("$(echo "${tags}" | grep -i '^genre=' | cut -d = -f 2)") #9
      file_data+=("$(echo "${tags}" | grep -i '^comment=' | cut -d = -f 2)") #10
    fi
  fi
  
  # Fix bitrate to be a true number
  local val
  if [ ${#file_data[2]} -gt 0 ]
  then
    case ${file_data[2]: -1} in
      k)
	val=$(echo "${file_data[2]::${#file_data[2]}-1} * 1000" | bc)
	file_data[2]=$(printf "%.0f" ${val})
	;;
      M)
	val=$(echo "${file_data[2]::${#file_data[2]}-1} * 1000000" | bc)
	file_data[2]=$(printf "%.0f" ${val})
	;;
    esac
  fi
  
  #echo "${file_data[@]}"
  echo $(declare -p file_data)
}

make_decode_name () {
  # Calculate the name of the decode file
  # $1 = full path of audio file
  # $2 = full path of temp directory
  
  local fromfile=${1##*/}
  echo "${2}/${fromfile%.*}".wav
}

decode_file () {
  # Convert the file to a wav, there's nothing more to see
  # here, move along now!
  # $1 = path of file to decode
  
  echo "Decoding $1 ..."
  ${SOX} "${1}" -t wav "${2}" 2>/dev/null
  return $?
}

change_ext () {
  # Change a file's extension. If we think it should be
  # vorbis then make it ogg, after all who uses vorbis?
  # $1 = path to file
  # $2 = new extension to append
  
  local new_ext
  if [ "${2}" == "vorbis" ]
  then
    new_ext="ogg"
  else
    new_ext="${2}"
  fi
  
  echo "${1%.*}.${new_ext}"
}

encode_file () {
  # Encode a wav file to either mp3, ogg or flac
  # $1 = array holding all file data, see earlier comments
  # for contents
  
  local file_data=("$@") quality out_type
  
  # Check to see if we're going to change the file type
  # when we encode.
  if [ "${file_data[11]}" == "same" ]
  then
    out_type=${file_data[1]}
  else
    out_type=${file_data[11]}
  fi
  
  # If we are changing the file type then we need to change
  # the extension of the output file
  if [ "${out_type}" != "${file_data[1]}" ]
  then
    file_data[0]="$(change_ext "${file_data[0]}" "${file_data[11]}")"
  fi
  
  # Choose your weapons gentlemen
  case ${out_type} in
    "mp3")
      echo Encoding $(basename "${file_data[@]: -1}") to mp3 ...

      # set the mono switch if needed
      [ "${file_data[3]}" -eq 1 ] && local mode="-m m"
      
      # Work out quality
      # Beware nasty magic numbers ahead divined by sacrificing virgins,
      # playing with the entrails and reading the web pages shown
      # near the top of this file
      if [ "${file_data[1]}" == "flac" ]
      then
	quality="${LAME_DEF_QUAL}"
      else
	# if bitrate is very high use cbr 320
	if ((${file_data[2]} > 283000))
	then
	  quality="-b 320"
	else
	  # if bitrate is low use abr 80 or 65
	  if ((${file_data[2]} < 98000))
	  then
	    if [ "${file_data[3]}" -eq 1 ]
	    then
	      quality="--abr 56"
	    else
	      quality="--abr 80"
	    fi
	  else
	    quality="-V $(echo "scale=5; (${file_data[2]} - 264285.71429) / (-21785.71429 * 1.09)  - 1;" | bc)"
	  fi
	fi
      fi
      
      ${LAME} --quiet ${quality} ${mode} --add-id3v2 \
	--tt "${file_data[4]}" \
	--ta "${file_data[5]}" \
	--tl "${file_data[6]}" \
	--ty "${file_data[7]}" \
	--tn "${file_data[8]}" \
	--tg "${file_data[9]}" \
	--tc "${file_data[10]}" \
	"${file_data[@]: -1}" "${file_data[0]}"

      echo Completed encoding $(basename "${file_data[@]: -1}") to mp3
      ;;
      
    "vorbis"|"ogg")
      echo Encoding $(basename "${file_data[@]: -1}") to ogg ...
      # Work out quality
      if [ "${file_data[1]}" == "flac" ]
      then
	quality="${OGG_DEF_QUAL}"
      else
	quality="-q $(echo "scale=5; l (${file_data[2]} / 53478.12402) * 1.1384 / 0.18859 - 1;" | bc -l)"
      fi
      
      ${OGGENC} ${quality} --quiet -o "${file_data[0]}" \
	-t "${file_data[4]}" \
	-a "${file_data[5]}" \
	-l "${file_data[6]}" \
	-d "${file_data[7]}" \
	-N "${file_data[8]}" \
	-G "${file_data[9]}" \
	-c "${file_data[10]}" \
	"${file_data[@]: -1}" 2>/dev/null

      echo Completed encoding $(basename "${file_data[@]: -1}") to ogg
      ;;
      
    "flac")
      # what no quality to worry about - ha! this _is_ easy!
      echo Encoding $(basename "${file_data[@]: -1}") to flac ...
      ${FLAC} --totally-silent --force --best -o "${file_data[0]}" \
	--tag TITLE="${file_data[4]}" \
	--tag ARTIST="${file_data[5]}" \
	--tag ALBUM="${file_data[6]}" \
	--tag DATE="${file_data[7]}" \
	--tag TRACKNUMBER="${file_data[8]}" \
	--tag GENRE="${file_data[9]}" \
	--tag COMMENT="${file_data[10]}" \
	"${file_data[@]: -1}"

      echo Completed encoding $(basename "${file_data[@]: -1}") to flac
      ;;
  esac
  return $?
}

process_file () {
  # Full process route for a single file.
  # $1 = input file path
  # $2 = temporary directory path
  # $3 = user selected target type from command line  
  # $4 = options to normalize
  
  local norm_op
  echo "Processing file $1 ..."

  # Retrieve file data into file_data
  eval $(identify_file "${1}")
  
  # If file is valid
  if [ -n "${file_data[1]}" ] &&  echo "mp3 vorbis flac" | grep -q "${file_data[1]}"
  then
    # Add target type and wav file name to file data list
    file_data+=("${3}")
    file_data+=("$(make_decode_name "${1}" "${2}")")
    if decode_file "$1" "${file_data[@]: -1}"
    then
      echo "Normalizing $1 ..."
      if norm_op=$(${NORM} --no-progress ${4} "${file_data[@]: -1}" 2>&1)
      then
	if ! echo ${norm_op} | grep -q "already normalized"
	then
	  encode_file "${file_data[@]}"
	else
	  echo $1 is already normalized - not encoding\!
	fi
      fi
    fi
  fi
  return 0
}

process_dir () {
  # Full process route for a directory, i.e batch normalize.
  # We need to decode every file to a wav before we can do
  # the normalization.
  # $1 = input file path
  # $2 = temporary directory path
  # $3 = user selected target type from command line  
  # $4 = options to normalize
  
  local idx=0 file_list=() p_list=() dec_count norm_op
  declare -r rows=13
  echo "Batch processing $1 ..."

  # For each file
  for ip_file in "${1%/}"/*
  do
    # If we get no file expansion break out now
    [ "${ip_file: -1}" == '*' ] && break

    # Retrieve file data into file_data
    eval $(identify_file "${ip_file}")
    
    # If file is valid
    if [ -n "${file_data[1]}" ] &&  echo "mp3 vorbis flac" | grep -q "${file_data[1]}"
    then
      # Add target type and wav file name to file data list
      file_data+=("${3}")
      file_data+=("$(make_decode_name "${ip_file}" "${2}")")

      # If we get a wav file then the append all the data onto
      # the end of the file list
      if decode_file "${ip_file}" "${file_data[@]: -1}"
      then
	file_list+=("${file_data[@]}")
      fi
    fi
  done
  # file_list now holds data for all files in one long list
  # Oh how I wish we had multidimensional arrays!
  # Each file takes up 13 elements (or rows)
  
  # Do we have any wavs?
  dec_count=$(ls -1 "${2}"/*.wav 2>/dev/null | wc -l)
  if ((dec_count > 0))
  then
    # Yes it's a miracle!
    echo "Batch normalizing $1 ..."
    if norm_op=$(${NORM} --batch --no-progress ${4} "${2}"/*.wav 2>&1)
    then
      if ! echo ${norm_op} | grep -q "already normalized"
      then
	# Slice the file_list every ${rows}, i.e. 1 file = 13 rows
	while ((idx < ${#file_list[@]}))
	do
	  (encode_file "${file_list[@]:${idx}:${rows}}") &
	  p_list+=($!)
	  ((idx+=rows))
	done
	wait ${p_list[*]}
      else
	echo $1 is already normalized - not encoding\!
      fi
    fi
  fi
  
  return 0
}

process_param () {
  # Process the non-option parameters, i.e. the files and directories
  # Create the temp working area and decide if were processing a file 
  # or directory.
  # $1 = input file path
  # $2 = temporary directory path
  # $3 = user selected target type from command line
  # $4 = options to normalize
  
  local WORKDIR=$(mktemp --directory --tmpdir="$2" naud-XXXXXXXXXX)
  WDIRS[${#WDIRS[@]}]="${WORKDIR}"
  if [ -d "$1" ]
  then
    process_dir "${1}" "${WORKDIR}" "${3}" "${4}"
  elif [ -f "$1" -a -r "$1" ]
  then
    process_file "${1}" "${WORKDIR}" "${3}" "${4}"
  fi
  rm -r ${WORKDIR}
  return 0
}

job_pool_init $((numprocs * 2)) 0

# Command line parameter mangling starts here
#   -a AMP         \\
#   -g ADJ          |
#   -n              |
#   -T THR          |_ These arguments are passed as arguments to normalize.
#   -b              |  Run "normalize-audio --help" for more info.
#   -m              |
#   -v              |
#   -q             /
declare -r NORM_ARG_LIST="-a -g -n -T -b -m -v -q"
NORM_ARGS=""

while [ -n "$1" ]
do
  if [ "${1::1}" == "-" ]
  then
    # It's an option
    if echo "${NORM_ARG_LIST}" | grep -q -e "${1%-}"
    then
      # pass-thru arg for normalize
      case "${1%-}" in
	-n|-b|-m|-v|-q)
	  if [ ${1: -1} == "-" ]
	  then
	    NORM_ARGS=$(echo ${NORM_ARGS} | sed "s/${1%-}//g")
	  else
	    echo ${NORM_ARGS} | grep -q -e ${1%-} || NORM_ARGS="${NORM_ARGS} ${1%-}"
	  fi
	  shift
	  ;;
	  
	-a|-g|-T)
	  if [ ${1: -1} == "-" ]
	  then
	    NORM_ARGS=$(echo ${NORM_ARGS} | sed "s/${1%-} \S\+//g")
	    shift
	  else
	    if (($# > 1))
	    then
	      if echo ${NORM_ARGS} | grep -q -e ${1%-}
	      then
		NORM_ARGS=$(echo ${NORM_ARGS} | sed "s/${1%-} \S\+/${1%-} ${2}/")
	      else
		NORM_ARGS="${NORM_ARGS} ${1%-} ${2}"
	      fi
	      shift 2
	    else
	      echo Missing argument to ${1}
	      exit 1
	    fi
	  fi
	  ;;
      esac
    else  
      # naud arg
      case "${1}" in
	-t)
	  if (($# > 1))
	  then
	    shift
	    TMPDIR="${1}"
	  else
	    echo Missing argument to -t
	    exit 1
	  fi
	  ;;
	  
	-o)
	  if (($# > 1))
	  then
	    shift
	    TARGET="${1}"
	    if ! echo ${TARGET_OPTS} | grep -q ${TARGET}
	    then
	      echo "Unrecognised target file type, should be one of \"${TARGET_OPTS}\""
	      exit 1
	    fi
	  else
	    echo Missing argument to -o
	    exit 1
	  fi
	  ;;
      esac
      shift
    fi
  else
    # It's a file / dir
    #(process_param "${1}" "${TMPDIR}" "${TARGET}" "${NORM_ARGS}") &
    job_pool_run process_param "${1}" "${TMPDIR}" "${TARGET}" "${NORM_ARGS}"
    shift
  fi
done

job_pool_wait

# Phew! - time for a cup of tea
echo "naud has finished."
exit 0
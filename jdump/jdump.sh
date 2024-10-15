#!/bin/bash
usage() {

	echo "Usage ${0} [options] <java process id>"
	echo "Options:"
	echo ""
	echo "	--outdir outputdir (Output dir where you want to collect java stats)"
	echo "	--jstackint jstackinterval (jstack interval in seconds. Default is 5 seconds)"
	echo "	--jstackcnt jstackcount (Number of jstacks to be collected. Default is 120)"
	echo "	--jstatint jstatinterval (jstat interval in milliseconds. Default is 3000)"
	echo "	--jstatcnt jstatcount (No of jstat lines to be collected. Default is 100)"
	echo "	--heapdump(Also collects heap dump. By default heap dump is not collected)"
	echo "	--fcdebug(Collect mapr file client debug. By default fcdebug is not collected.)"
	echo "	--fcint interval (Interval until file client debug needs to be collected. Works only with --fcdebug option.)"
	echo ""
	exit 1
}

check_is_error() {

	message=$2
	local func_ret_code=$1

	if [ ${func_ret_code} -eq 0 ]; then 
		return 0
	else
		echo "$message"	
		exit 1
	fi
}
	
	

get_java_cmd() {

	JAVA_CMD=${1}
	JAVA_CMD_PATH=${1}

	if [ -f ${pid_java_path}/${JAVA_CMD} ]; then 
	
		echo "Found ${JAVA_CMD_PATH}"
		JAVA_CMD_PATH=${pid_java_path}/${1}

	elif [ ! -z ${JAVA_HOME} ] && [ -f ${JAVA_HOME}/bin/${1} ]; then
		echo "Cannot find ${pid_java_path}/bin/${JAVA_CMD}, using JAVA_HOME=${JAVA_HOME}"		
		JAVA_CMD_PATH=${JAVA_HOME}/bin/${1}
	else
		echo "Cannot find ${JAVA_CMD} under ${pid_java_path} and JAVA_HOME"
		echo "Using plain ${JAVA_CMD}"
	fi

}

validate_pid_info() {
	
	local ret_code=0
	
	current_user=`whoami`
	if [ "${current_user}" != "$1" ]; then 
		echo "Current user is ${current_user}, jdump needs to run as ${1}"
		ret_code=1;
	fi
	if [ "$2" != "java" ]; then 
		echo "The process ${3} is not a java process"
		ret_code=1
	fi
	return $ret_code
}

validate_outdir() {

	local ret_code=0
	echo "Checking the output directory ${outdir}"
	
	if [ ${outflag} -eq 1 ]; then 
		if [ ! -d ${parent_outdir} ]; then
			echo "Directory ${parent_outdir} does not exist"
			ret_code=1
		else
			mkdir ${outdir}
			ret_code=$?
		fi
	else
		echo "No ouput directory provided for diagnostics. Creating ${outdir}"
		mkdir  ${outdir}
		ret_code=$?
	fi

	return ${ret_code}

}

collect_jstat() {

	echo "Collecting jstat for ${pid}"
	local jstatret=0
	${JSTAT_CMD} -gcutil -t ${pid} ${jstatint} ${jstatcnt} > ${outdir}/jstat_${pid}_$(date +"%Y%m%d_%H%M%S")
	jstatret=$?
	if [ $jstatret -ne 0 ]; then 
		echo "Having trouble running jstat for the pid ${pid}"
	fi
	return $jstatret	

}

collect_jstack() {
	echo "Collecting jstacks"
	local counter=0
	local jstckret=0
	
	while [ ${counter} -lt ${jstackcnt} ]; 
	do 
		${JSTACK_CMD} ${pid} > ${outdir}/jstack_${pid}_$(date +"%Y%m%d_%H%M%S")
		jstckret=$?
		if [ $jstckret -ne 0 ]; then 
			echo "Having trouble collecting jstack for the ${pid}..skipping jstack collection"
			break;
		fi
		sleep ${jstackint}s				
		counter=$((counter + 1))
	done	
	return $jstckret
}

collect_heap_info() {
	echo "Collecting heap information"
	local jmapret=0
	${JMAP_CMD} -histo ${pid} > ${outdir}/jmap_${pid}_histo
	${JMAP_CMD} -histo:live ${pid} > ${outdir}/jmap_${pid}_histo_live
	jmapret=$?
	if [ $jmapret -ne 0 ]; then 
		echo "Having trouble running jmap"
		return $jmapret
	fi

	if [ ${heapdump} -eq 1 ]; then
		echo "Collecting heap dump"
		${JMAP_CMD} -dump:live,file=${outdir}/heapdump_${pid}.hprof ${pid}
		jmapret=$?
		if [ $jmapret -ne 0 ]; then
			echo "Heap dump collection failed"
		fi		
	fi	
	return $jmapret
}

collect_fcdebug() {

	local fcret=0
	echo "Collecting mapr file client debug, using fcdebug"
	shmid=`ipcs -mp | awk '{if ($3 == "1290894") {split($0,a," "); system("ipcs -mi "a[1])}}' | grep 'Shared memory Segment shmid' | awk -F"=" '{print $NF}' | sort -n | head -1`
	${MAPR_HOME}/server/tools/fcdebug -s  ${shmid} -l DEBUG
	fcret=$?
	if [ $fcret -ne 0 ]; then 
		echo "fcdebug collection failed"
		return 1
	fi
	sleep ${fcint}m 
	${MAPR_HOME}/server/tools/fcdebug -s  ${shmid} -l INFO 
	fcret=$?
	if [ $fcret -ne 0 ]; then
		echo "reverting fcdebug to INFO failed"
		echo "Please run the command, ${MAPR_HOME}/server/tools/fcdebug -s  ${shmid} -l INFO , to revert back to INFO"
	fi
	proc_stderr=`ls -l /proc/${pid}/fd/2 | awk -F"->" '{print $NF}'`		
	echo "Copying stderr of the process to ${outdir}"
	/usr/bin/cp ${proc_stderr} ${outdir}
	return $fcret
	
}
wait_child_pids(){
	local ret_val=0
	for child_pid in "${jdump_pids[@]}"; do
    		wait $child_pid
		tmp_ret=$?	
    		if [ $tmp_ret -ne 0 ]; then
			ret_val=$tmp_ret

		fi
	done
	return ${ret_val}
}


#############
## MAIN #####
############# 
MAPR_HOME="/opt/mapr"
JSTAT_PATH=""
JSTACK_PATH=""
jstackint=5
jstackcnt=120
jstatint=3000
jstatcnt=100
heapdump=0
fcdebug=0
fcint=5
pidflag=0
outflag=0
jdump_pids=()
exit_code=0
# Process command-line options

if [ $# -eq 0 ]; then 
	echo "Invalid Number of arguments"
	usage
	exit 1
fi

while [ "$#" -gt 1 ]; do
    case "$1" in
        --outdir | -o)
            	parent_outdir="$2" 
		outflag=1
            	shift       
            	;;
	--jstackint)
		jstackint=$2
		shift;;
	--jstackcnt)
		jstackcnt=$2
		shift
		;;
	--jstatint)
		jstatint=$2
		shift
		;;
	--jstatcnt)
		jstatcnt=$2
		shift
		;;
	--fcint)
		fcint=$2
		shift
		;;
	--fcdebug)
	        fcdebug=1	
		;;
	--heapdump)
	        heapdump=1	
		;;
        *) 
            echo "Invalid option: $1"  # Handle invalid options
            exit 1
            ;;
    esac
    shift  # Move to the next option/argument
done

pid=${1} # Last option left is the pid

if ! [[ "$pid" =~ ^[0-9][0-9]*$ ]]; then 
	echo ""
	echo "Process id ${pid} is not valid"
	echo ""
	usage
fi


pid_info=`ps -o pid,user,args --pid ${pid} --no-headers`
if [ $? -ne 0 ]; then
	echo "Invalid Process Id"
	exit 1
fi

jdump_id=jdump_${pid}_$(date +"%Y%m%d_%H%M%S")

if [ ${outflag} -eq 0 ]; then
	outdir=${MAPR_HOME}/logs/${jdump_id}
	echo "Using default directory $outdir"
else
	outdir=${parent_outdir}/${jdump_id}
fi

validate_outdir
ret_val=$?
check_is_error ${ret_val} "Error creating output directory"

pid_user=`echo ${pid_info} | awk '{print $2}'`
pid_proc=`echo ${pid_info} | awk '{print $3}' | awk -F"/" '{print $NF}'`

validate_pid_info ${pid_user} ${pid_proc} ${pid}
ret_val=$?
check_is_error $ret_val "Exiting..error related to process or process user"

pid_java_path=`echo ${pid_info} | awk '{print $3}' | awk -F"/" 'BEGIN { OFS = "/" } { $NF="";print}'` 

echo $$ > ${outdir}/jdump_pid.out
echo "Starting diagnostics collection. To stop this, run stop_jdump.sh ${outdir}"

########### Collect jstat#######

get_java_cmd "jstat"
JSTAT_CMD=$JAVA_CMD_PATH
collect_jstat ${JSTAT_CMD} &
jdump_pids+=($!)

########### Collect jstack#######

get_java_cmd "jstack"
JSTACK_CMD=$JAVA_CMD_PATH
collect_jstack ${JSTACK_CMD} &
jdump_pids+=($!)

##########Collect fcdebug#######

if [ $fcdebug -eq 1 ]; then
	touch ${outdir}/fcdebug_is_enabled	
	collect_fcdebug &
	jdump_pids+=($!)
fi

###############################

wait_child_pids
exit_code=$?


########### Collect Heap info#######

get_java_cmd "jmap"
JMAP_CMD=$JAVA_CMD_PATH
collect_heap_info ${JMAP_CMD}
heap_ret_code=$?

if [ $heap_ret_code -ne 0 ]; then 
	exit_code=$heap_ret_code
fi

#############

echo "Requested info is collected in the dir $outdir"

exit ${exit_code}

exit 0 

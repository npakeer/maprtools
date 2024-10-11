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

get_java_cmd() {

	JAVA_CMD=${1}
	JAVA_CMD_PATH=${1}

	if [ -f ${pid_java_path}/${JAVA_CMD} ]; then 
	
		echo "Found ${JAVA_CMD_PATH}"
		JAVA_CMD_PATH=${pid_java_path}/${1}

	elif [ ! -z ${JAVA_HOME} ] && [ -f ${JAVA_HOME}/${1} ]; then
		echo "Cannot find ${pid_java_path}/${JAVA_CMD}, using JAVA_HOME=${JAVA_HOME}"		
		JAVA_CMD_PATH=${JAVA_HOME}/${1}
	else
		echo "Cannot find ${JAVA_CMD} under ${pid_java_path} and JAVA_HOME"
		echo "Using plain ${JAVA_CMD}"
	fi

}

validate_pid_info() {

	current_user=`whoami`
	if [ "${current_user}" != "$1" ]; then 
		echo "Current user is ${current_user}, jdump needs to run as ${1}"
		exit 1;
	fi
	if [ "$2" != "java" ]; then 
		echo "The process ${3} is not a java process"
		exit 1
	fi
}

validate_outdir() {

	echo "Checking the output directory ${outdir}"
	
	if [ -d ${outdir} ]; then 
		echo "Directory ${outdir} already exists"
	else
		echo "Directory ${outdir} does not exist. Creating the directory"
		mkdir  ${outdir}
		if [ $? -ne 0 ]; then
			echo "Cannot create the output ${outdir} directory..exiting"
			exit 1
		fi
	fi

}

collect_jstat() {

	echo "Collecting jstat for ${pid}"
	jstatret=0
	${JSTAT_CMD} -gcutil -t ${pid} ${jstatint} ${jstatcnt} > ${outdir}/jstat_${pid}_$(date +"%Y%m%d_%H%M%S")
	jstatret=$?
	if [ $jstatret -ne 0 ]; then 
		echo "Having trouble running jstat for the pid ${pid}"
	fi
	return $jstatret	

}

collect_jstack() {
	echo "Collecting jstacks"
	counter=0
	jstckret=0
	
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
	jmapret=0
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

	fcret=0
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
# Process command-line options

if [ $# -eq 0 ]; then 
	echo "Invalid Number of arguments"
	usage
	exit 1
fi

while [ "$#" -gt 1 ]; do
    case "$1" in
        --outdir | -o)
            	outdir="$2" 
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

if [ ${outflag} -eq 0 ]; then
	outdir=${MAPR_HOME}/logs/jdump_${pid}_$(date +"%Y%m%d_%H%M%S")
	echo "Using default directory $outdir"
	
fi
validate_outdir

pid_user=`echo ${pid_info} | awk '{print $2}'`
pid_proc=`echo ${pid_info} | awk '{print $3}' | awk -F"/" '{print $NF}'`
validate_pid_info ${pid_user} ${pid_proc} ${pid}
pid_java_path=`echo ${pid_info} | awk '{print $3}' | awk -F"/" 'BEGIN { OFS = "/" } { $NF="";print}'` 
########### Collect jstat#######
get_java_cmd "jstat"
JSTAT_CMD=$JAVA_CMD_PATH
collect_jstat ${JSTAT_CMD} 
ret1=$?
########### Collect jstack#######
get_java_cmd "jstack"
JSTACK_CMD=$JAVA_CMD_PATH
collect_jstack ${JSTACK_CMD}
ret2=$?
##########Collect fcdebug#######
ret3=0
if [ $fcdebug -eq 1 ]; then
	collect_fcdebug
	ret3=$?
fi
########### Collect Heap info#######
get_java_cmd "jmap"
JMAP_CMD=$JAVA_CMD_PATH
collect_heap_info ${JMAP_CMD}
ret4=$?

echo "Requested info is collected in the dir $outdir"

#if [ [ $ret1 -ne 0 ] -o [ $ret2 -ne 0 ] -o [ $ret3 -ne 0 ] -o [ $ret4 -ne 0 ] ]; then 
#	exit 1
#fi

 
if [ $ret1 -ne 0 -o $ret2 -ne 0 -o $ret3 -ne 0 -o $ret4 -ne 0 ]; then 
	exit 1
fi

exit 0 

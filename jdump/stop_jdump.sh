#!/bin/bash

usage() {
	echo "Usage: $0  <Diagnostics Output directory>"
	exit 1
}

if [ $# -eq 0 ]; then 
	echo "Invalid no of parameters"
	usage
fi	

outdir=${1}

if [ ! -d ${outdir} ]; then 
	echo "Output directory ${outdir} not found"
	exit 1
fi

pid=`cat ${outdir}/jdump_pid.out | tr -d ' '`

echo "Killing jstat, jstack and jmap etc.."

for p in `pstree -p $pid | tr -s '(' '\n' | grep ")" | cut -f 1 -d ")"`; do
	kill -9 $p > /dev/null 2>&1
done

if [ -f ${outdir}/fcdebug_shmid ]; then 
	shmid=`cat ${outdir}/fcdebug_shmid | tr -d ' '`
	echo "File client DEBUG  is enabled. Reverting back to INFO"
	/opt/mapr/server/tools/fcdebug -s ${shmid} -l INFO 
fi

exit 0

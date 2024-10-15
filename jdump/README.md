# jdump

This is a tool to collect HPE Ezmeral java process diagnostics

The tool collects jstat, jstack, heap information and fcdebug information of a running JVM process. Requested diagnostics are collected in the output directory mentioned through --outdir option. If this option is not specified, requested information is collected under /opt/mapr/logs

# Tool Options
```bash
Usage ./jdump.sh [options] <java process id>
Options:

        --outdir outputdir (Output dir where you want to collect java stats)
        --jstackint jstackinterval (jstack interval in seconds. Default is 5 seconds)
        --jstackcnt jstackcount (Number of jstacks to be collected. Default is 120)
        --jstatint jstatinterval (jstat interval in milliseconds. Default is 3000)
        --jstatcnt jstatcount (No of jstat lines to be collected. Default is 100)
        --heapdump(Also collects heap dump. By default heap dump is not collected)
        --fcdebug(Collect mapr file client debug. By default fcdebug is not collected.)
        --fcint interval (Interval until file client debug needs to be collected. Works only with --fcdebug option.)
```


# Example

Following example shows the collection of 1 jstack, 1 jstat with fcdebug interval for 1 minute. Note the fcdebug interval needs to be large enough for DEBUG to be collected for mapr client. The tool tries to revert the DEBUG back to INFO after the interval. jstat, jstacks and fcdebug are collected in parallel. Heap information/dump is collected only after other diagnostics collection is finished. This is needed to avoid collecting misleading jstacks, which can happen when heap information collection can freeze the java process.

```bash
$ ./jdump.sh --fcdebug --jstackcnt 1 --jstatcnt 1 --heapdump --fcint 1 14139
Using default directory /opt/mapr/logs/jdump_14139_20241014_164209
Checking the output directory /opt/mapr/logs/jdump_14139_20241014_164209
No ouput directory provided for diagnostics. Creating /opt/mapr/logs/jdump_14139_20241014_164209
Starting diagnostics collection. To stop this, run "stop_jdump.sh /opt/mapr/logs/jdump_14139_20241014_164209"
Cannot find jstat under /usr/lib/jvm/java-1.8.0-openjdk-1.8.0.372.b07-4.el8.x86_64/jre/bin/ and JAVA_HOME
Using plain jstat
Cannot find jstack under /usr/lib/jvm/java-1.8.0-openjdk-1.8.0.372.b07-4.el8.x86_64/jre/bin/ and JAVA_HOME
Using plain jstack
Collecting jstat for 14139
Collecting jstacks
Collecting mapr file client debug, using fcdebug
jstat collection ended
jstacks collection ended
Reverting fcdebug to INFO
Copying stderr of the process to /opt/mapr/logs/jdump_14139_20241014_164209
Cannot find jmap under /usr/lib/jvm/java-1.8.0-openjdk-1.8.0.372.b07-4.el8.x86_64/jre/bin/ and JAVA_HOME
Using plain jmap
Collecting heap information
Collecting heap dump
Dumping heap to /opt/mapr/logs/jdump_14139_20241014_164209/heapdump_14139.hprof ...
Heap dump file created
Heap Information collection ended
Requested info is collected in the dir /opt/mapr/logs/jdump_14139_20241014_164209

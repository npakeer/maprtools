# jdump

This is a tool to collect HPE Ezmeral java process diagnostics

The tool collects jstat, jstack, heap information and fcdebug information of a running JVM process

## Tool Options

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


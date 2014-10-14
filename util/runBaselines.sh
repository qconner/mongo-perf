#!/bin/bash
#
touch ~/build-perf
util/benchrun_daemon.sh r2.4.10
util/benchrun_daemon.sh r2.4.11
util/benchrun_daemon.sh r2.4.12
util/benchrun_daemon.sh r2.6.0
util/benchrun_daemon.sh r2.6.1
util/benchrun_daemon.sh r2.6.2
util/benchrun_daemon.sh r2.6.3
util/benchrun_daemon.sh r2.6.4
util/benchrun_daemon.sh r2.6.5
util/benchrun_daemon.sh r2.7.0
util/benchrun_daemon.sh r2.7.1
util/benchrun_daemon.sh r2.7.2
util/benchrun_daemon.sh r2.7.3
util/benchrun_daemon.sh r2.7.4
util/benchrun_daemon.sh r2.7.5
util/benchrun_daemon.sh r2.7.6
util/benchrun_daemon.sh r2.7.7
rm -f ~/build-perf


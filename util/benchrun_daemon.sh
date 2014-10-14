#!/bin/bash
#Rewritten as of April 9th, 2014 by Dave Storch & Amalia Hawkins
#Find us if you have any questions, future user!

# script should work on Linux, Solaris, MacOSX
# for Windows, run under cygwin
THIS_PLATFORM=`uname -s || echo unknown`

# environment details, within Windows or Linux
PLATFORM_SUFFIX=""
if [ $THIS_PLATFORM == 'CYGWIN_NT-6.1' ]
then
    THIS_PLATFORM='Windows'
    PLATFORM_SUFFIX="2K8"
fi
if [ $THIS_PLATFORM == 'CYGWIN_NT-6.3' ]
then
    THIS_PLATFORM='Windows'
    PLATFORM_SUFFIX="2K12"
fi
# override Platform suffix / put custom attributes here
# e.g. PLATFORM_SUFFIX="-numa"
#PLATFORM_SUFFIX=""

# *nix user name
# override may help if running as root,
# but installed to a user home directory
#RUNUSER=mongo-perf
RUNUSER=${USER}

# mongo-perf base directory
# override if not $HOME
if [ $THIS_PLATFORM == 'Darwin' ]
then
    MPERFBASE=/Users/${RUNUSER}
else
    MPERFBASE=/home/${RUNUSER}
fi
# mongo-perf working directory
# override if not $HOME/mongo-perf
MPERFPATH=${MPERFBASE}/mongo-perf

# build directory
# override if not $HOME/mongo
BUILD_DIR=${MPERFBASE}/mongo

# test database location
# override if not $HOME/db
DBPATH=${MPERFBASE}/db

# executable names
SCONSPATH=scons
MONGOD=mongod
MONGO=mongo

# path to the mongo shell
SHELLPATH=${BUILD_DIR}/${MONGO}

# branch to monitor for checkins
BRANCH=master

NUM_CPUS=1
if [ -e /proc/cpuinfo ]
then
    NUM_CPUS=$(grep ^processor /proc/cpuinfo | wc -l | awk '{print $1}')
fi

# remote database to store results
# in C++ driver ConnectionString / DBClientConnection format
# this example assumes a two-member replica set
RHOST=localhost
RPORT=27017

# create this file to un-daemonize (exit the loop)
BREAK_PATH=${MPERFBASE}/build-perf

# use sudo (without password) for cache flush between runs
SUDO=sudo

# test agenda from all .js files found here
TEST_DIR=${MPERFPATH}/testcases

# seconds between checking for something to do
SLEEPTIME=60

# uncomment to fetch recently-built binaries from mongodb.org instead of compiling from source
#FETCHMCI='TRUE'

# path to save downloaded binaries, if any
DLPATH="${MPERFPATH}/download"

# developer options for the mongod command line, if any
#MONGOD_OPT="--storageEngine wiredtiger"

# developer options for the scons command line, if any
#SCONS_OPT="--wiredtiger --cpppath=${HOME}/wiredtiger/LOCAL_INSTALL/include --libpath=${HOME}/wiredtiger/LOCAL_INSTALL/lib core"

# skip compile?  For local development use.
# use the -C option
#SKIP_COMPILE="true"

# skip git (avoid modifying working copy)?  For local development use.
# use the -G option
#SKIP_GIT="true"

# any external library dependencies?
#EXT_LIB="$HOME/wiredtiger"
#EXT_LIB="$HOME/src/wiredtiger"
if [ -n "$EXT_LIB" ]
then
    EXT_LIB_PREFIX="$EXT_LIB/LOCAL_INSTALL"
    APPEND_LIB_PATH="$EXT_LIB_PREFIX/lib"
fi

# any additions to the shared library path?
if [ -n "$APPEND_LIB_PATH" ]
then
    if [ -z $LD_LIBRARY_PATH ]
    then
        LD_LIBRARY_PATH=${APPEND_LIB_PATH}
    else
        LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${APPEND_LIB_PATH}
    fi
    export LD_LIBRARY_PATH
    echo "found external library dependency"
fi


# file name for keeping state between invocations
# modify for non-vanilla mongo-perf installs
PERSIST_LAST_HASH=${HOME}/.last-mongo-perf
if [ -n "$FETCHMCI" ]
then
    PERSIST_LAST_HASH=${PERSIST_LAST_HASH}_fetchmci
fi
if [ -n "$APPEND_LIB_PATH" ]
then
    PERSIST_LAST_HASH=${PERSIST_LAST_HASH}_externLib
fi

# windows-specific settings
if [ $THIS_PLATFORM == 'Windows' ]
then
    SCONSPATH=scons.bat
    SHELLPATH=`cygpath -w ${SHELLPATH}.exe`
    MONGOD=mongod.exe
    MONGO=mongo.exe
    DBPATH=`cygpath -w ${DBPATH}`
    SUDO=''
fi



# ensure numa zone reclaims are off
# TODO: prepend to the mongod command line
CPUCTL=""
numapath=$(which numactl)
if [[ -x "$numapath" ]]
then
    echo "turning off numa zone reclaims with:"
    CPUCTL="numactl --interleave=all"
    # TODO: intelligently set physcpubind
    #CPUCTL="numactl --physcpubind=0-7 --interleave=all"
    echo $CPUCTL
else
    echo "numactl not found on this machine"
    # TODO: run taskset instead
    # echo taskset -xff
fi

# look for command line arguments
OPTIND=1 
while getopts "b:s:d:C?G?L:" opt; do
    case "${opt}" in
    b)
        # run only this branch
        BRANCH=${OPTARG}
        ;;
    s)
        # extra scons build option
        SCONS_OPT=${OPTARG}
        ;;
    d)
        # mongod extra option
        MONGOD_OPT=${OPTARG}
        ;;
    C)
        # skip compilation / leave working copy alone
        SKIP_COMPILE="true"
        ;;
    G)
        # skip git / leave working copy alone
        SKIP_GIT="true"
        ;;
    L)
        # external library path
        EXT_LIB=${OPTARG}
        ;;
    esac
done



function do_git_tasks() {
    cd $BUILD_DIR || exit 1
    rm -rf build

    if [ -z $FETCHMCI & -z $SKIP_GIT ]
    then
        # local compile
        # some extra gyration here to allow/automate a local patch
        git fetch --all
        git checkout -- .
        git checkout $BRANCH
        git pull
        git clean -fqdx
        # apply local patch here, if any
        #patch -p 1 -F 3 < ${HOME}/pinValue.patch
    else
        echo "SKIPPING GIT CHECKOUT"
    fi
}


function do_mci_tasks() {
    cd $BUILD_DIR || exit 1
    if [ -z "$SKIP_GIT" ]
    then
        git checkout -- .
        git checkout master
        git pull
        git clean -fqdx
    fi

    # fetch latest binaries from MCI
    cd ${MPERFPATH} || exit 1
    echo "downloading binary artifacts from MCI for branch ${BRANCH}"
    if [ $THIS_PLATFORM == 'Windows' ]
    then
        if [ $BRANCH == 'master' ]
        then
            python `cygpath -w ${MPERFPATH}/util/get_binaries.py` --dir `cygpath -w "${DLPATH}"` --distribution 2008plus
        else
            python `cygpath -w ${MPERFPATH}/util/get_binaries.py` --revision ${BRANCH} --dir `cygpath -w "${DLPATH}"` --distribution 2008plus
        fi
    else
        if [ $BRANCH == 'master' ]
        then
            python ${MPERFPATH}/util/get_binaries.py --dir "${DLPATH}"
        else
            python ${MPERFPATH}/util/get_binaries.py --revision ${BRANCH} --dir "${DLPATH}"
        fi
    fi
    if [ $? != 0 ]
    then
        # no binaries found
        echo "ERROR: no binaries found for ${BRANCH}"
        exit 1
    fi
    chmod +x ${DLPATH}/${MONGOD}
    cp -p ${DLPATH}/${MONGOD} ${BUILD_DIR}
    cp -p ${DLPATH}/${MONGO} ${BUILD_DIR}
    BINHASH=""
    BINHASH=$(${DLPATH}/${MONGOD} --version | egrep git.version|perl -pe '$_="$1" if m/git.version:\s(\w+)/')
    if [ -z $BINHASH ]
    then
        echo "ERROR: could not determine git commit hash from downloaded binaries"
    else
        cd $BUILD_DIR || exit 1
        if [ -z "$SKIP_GIT" ]
        then
            git checkout $BINHASH
            git pull
        fi
    fi
}


function is_this_new() {
    cd $BUILD_DIR
    if [ -e $PERSIST_LAST_HASH ]
    then
        LAST_HASH=$(cat $PERSIST_LAST_HASH)
    else
        LAST_HAST=""
    fi
    if [ -z "$LAST_HASH" ]
    then
        LAST_HASH=$(git rev-parse HEAD)
        return 1
    else
        NEW_HASH=$(git rev-parse HEAD)
        if [ "$LAST_HASH" == "$NEW_HASH" ]
        then
            return 0
        else
            LAST_HASH=$NEW_HASH
            echo $LAST_HASH > $PERSIST_LAST_HASH
            return 1
        fi
    fi
}


function run_library_build() {
    cd $EXT_LIB
    git checkout -- .
    sh build_posix/reconf
    ./configure --with-builtins=snappy,zlib --prefix=$(EXT_LIB_PREFIX)
    make install || exit 2
}

function run_mongod_build() {
    cd $BUILD_DIR
    if [ -z $FETCHMCI ]
    then
        if [ $THIS_PLATFORM == 'Windows' ]
        then
            ${SCONSPATH} -j $NUM_CPUS --64 --release --win2008plus ${SCONS_OPT} ${MONGOD} ${MONGO}
        else
            ${SCONSPATH} -j $NUM_CPUS --64 --release ${SCONS_OPT} ${MONGOD} ${MONGO}
        fi
    fi
}

function run_mongo-perf() {
    # Kick off a mongod process.
    cd $BUILD_DIR
    if [ $THIS_PLATFORM == 'Windows' ]
    then
        rm -rf `cygpath -u $DBPATH`/*
        (./${MONGOD} --dbpath "${DBPATH}" --smallfiles --logpath mongoperf.log &)
    else
        rm -rf ${DBPATH}/*
        ${CPUCTL} ./${MONGOD} --dbpath "${DBPATH}" --smallfiles --fork --logpath mongoperf.log ${MONGOD_OPT}
    fi
    # TODO: doesn't get set properly with --fork ?
    MONGOD_PID=$!

    sleep 30

    cd $MPERFPATH
    TIME="$(date "+%m%d%Y_%H:%M")"

    # list of testcase definitions
    TESTCASES=$(find testcases/ -name *.js)


    # list of thread counts to run (high counts first to minimize impact of first trial)
    THREAD_COUNTS="16 8 4 2 1"

    # drop linux caches
    if [ -e /proc/sys/vm/drop_caches ]
    then
        ${SUDO} bash -c "echo 3 > /proc/sys/vm/drop_caches"
    fi

    # Run with single DB.
    if [ $THIS_PLATFORM == 'Windows' ]
    then
        python benchrun.py -l "${TIME}_${THIS_PLATFORM}${PLATFORM_SUFFIX}" --rhost "$RHOST" --rport "$RPORT" -t ${THREAD_COUNTS} -s "$SHELLPATH" -f $TESTCASES --trialTime 5 --trialCount 7 --mongo-repo-path `cygpath -w ${BUILD_DIR}` --safe false -w 0 -j false --writeCmd true
    else
        ${CPUCTL} python benchrun.py -l "${TIME}_${THIS_PLATFORM}${PLATFORM_SUFFIX}" --rhost "$RHOST" --rport "$RPORT" -t ${THREAD_COUNTS} -s "$SHELLPATH" -f $TESTCASES --trialTime 5 --trialCount 7 --mongo-repo-path ${BUILD_DIR} --safe false -w 0 -j false --writeCmd true
    fi

    # drop linux caches
    if [ -e /proc/sys/vm/drop_caches ]
    then
        ${SUDO} bash -c "echo 3 > /proc/sys/vm/drop_caches"
    fi

    # Run with multi-DB (4 DBs.)
    if [ $THIS_PLATFORM == 'Windows' ]
    then
        python benchrun.py -l "${TIME}_${THIS_PLATFORM}${PLATFORM_SUFFIX}-multi" --rhost "$RHOST" --rport "$RPORT" -t ${THREAD_COUNTS} -s "$SHELLPATH" -m 4 -f $TESTCASES --trialTime 5 --trialCount 7 --mongo-repo-path `cygpath -w ${BUILD_DIR}` --safe false -w 0 -j false --writeCmd true
    else
        echo ${CPUCTL} python benchrun.py -l "${TIME}_${THIS_PLATFORM}${PLATFORM_SUFFIX}-multi" --rhost "$RHOST" --rport "$RPORT" -t ${THREAD_COUNTS} -s "$SHELLPATH" -m 4 -f $TESTCASES --trialTime 5 --trialCount 7 --mongo-repo-path ${BUILD_DIR} --safe false -w 0 -j false --writeCmd true
    fi

    # Kill the mongod process and perform cleanup.
    kill -n 9 ${MONGOD_PID}
    pkill -9 ${MONGOD}         # kills all mongod processes -- assumes no other use for host
    pkill -9 mongod            # needed this for loitering mongod executable w/o .exe extension?
    sleep 5
    rm -rf ${DBPATH}/*

}


# housekeeping for meaningful benchmarks
# includes 

# disable transparent huge pages
# modify to work with your Linux distribution
if [ -e /sys/kernel/mm/transparent_hugepage/enabled ]
then
    echo never | ${SUDO} tee /sys/kernel/mm/transparent_hugepage/enabled /sys/kernel/mm/transparent_hugepage/defrag
fi

# if cpufreq scaling governor is present, ensure we aren't in power save (speed step) mode
# modify to work with your Linux distribution
if [ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]
then
    echo performance | ${SUDO} tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
fi


# main loop
while [ true ]
do
    # download binaries or prepare source code
    if [ -n "$FETCHMCI" ]
    then
        do_mci_tasks
    else
        if [ -z "$SKIP_GIT" ]
        then
            do_git_tasks
        fi
    fi

    # look at build dir Git hash
    is_this_new()
    if [ $? == 0 ]
    then
        sleep $SLEEPTIME
        continue
    fi

    # compile?
    if [[ -z "$FETCHMCI" && -z "$SKIP_GIT" && -z "$SKIP_COMPILE" ]]
    then
        echo COMPILING EXTERNAL LIBRARY
        run_library_build
        if [ $? != 0 ]
        then
            sleep $SLEEPTIME
            continue
        fi

        echo COMPILING MONGO LOCALLY
        run_mongod_build
        if [ $? != 0 ]
        then
            sleep $SLEEPTIME
            continue
        fi
    else
        echo SKIPPING COMPILE
    fi

    # if we made it this far execute the benchmark
    echo RUNNING BENCHMARK
    run_mongo-perf

    # exit if requested by user, this is a one-time (branch, tag or specific
    # commit) run, or this is a no-compile run
    if [ -e $BREAK_PATH | -n $BRANCH | -n $SKIP_GIT ]
    then
        break
    fi


done

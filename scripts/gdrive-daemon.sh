#!/bin/bash

G_DRIVE_PATH=~/Documents/gdrive/;

CONFIG_DIR=~/.gdrive/;
PREV_STATUS_FILE="$CONFIG_DIR/prev";
CUR_STATUS_FILE="$CONFIG_DIR/cur";
GRIVE_LOG_FILE="$CONFIG_DIR/grive.log";

FS_CHECK_INTERVAL=60 # seconds
INACTIVE_MAX_SKIP_COUNT=10 # max intervals to skip when inactive

# grave is force run for every N checks, even if no local changes are detected
FORCE_RUN_INTERVAL_COUNT=10;

mkdir -p "$CONFIG_DIR";
touch "$CUR_STATUS_FILE";

counter=0;
inactive_counter=1;
cd $G_DRIVE_PATH;

compute(){
    echo "$*" | bc;
}

while :
do
    echo "`date` - `compute $inactive_counter+1` intervals" >> $GRIVE_LOG_FILE;
    run_grive=false;

    mv $CUR_STATUS_FILE $PREV_STATUS_FILE;
    ls -lR $G_DRIVE_PATH > $CUR_STATUS_FILE;
    fs_changes=$(diff $CUR_STATUS_FILE $PREV_STATUS_FILE);

    if [ ! -z "$fs_changes" ]; then
        #echo "FS changed running grive...";
        run_grive=true;
        inactive_counter=1;
    else
        if [ $inactive_counter -lt $INACTIVE_MAX_SKIP_COUNT ]; then
            inactive_counter=$((inactive_counter+1));
        fi
        #echo "inactive_counter: $inactive_counter";
    fi

    if [ $counter -gt $FORCE_RUN_INTERVAL_COUNT ]; then
        #echo "counter: $counter - running grive...";
        run_grive=true;
    else
        counter=$((counter + 1));
        counter=0;
    fi

    if $run_grive ;
    then
        date >> $GRIVE_LOG_FILE;
        /usr/bin/grive >>$GRIVE_LOG_FILE 2>&1 ;
        #echo "sleeping for $sleep_inverval seconds...";
        sleep $FS_CHECK_INTERVAL;
        counter=0;
    else
        sleep_inverval=$(compute "$FS_CHECK_INTERVAL * $inactive_counter");
        #echo "sleeping for $sleep_inverval seconds...";
        sleep $sleep_inverval;
    fi
done

#touch


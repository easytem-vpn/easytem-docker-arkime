#!/bin/bash

echo "Giving OS time to start..."
until curl -sS "http://$OS_HOST:$OS_PORT/_cluster/health?wait_for_status=yellow" > /dev/null 2>&1
do
    echo "Waiting for OS to start"
    sleep 1
done
echo
echo "OS started..."

# set runtime environment variables
export ARKIME_PASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n1)  # random password
export ARKIME_LOCALELASTICSEARCH=no
export ARKIME_ELASTICSEARCH="http://"$OS_HOST":"$OS_PORT
export ARKIME_INET=no

if [ ! -f $ARKIMEDIR/etc/.initialized ]; then
    if [ -z $OS_USER ]; then
        # pass empty OS user to Configure script
        echo -e "$ARKIME_LOCALELASTICSEARCH\n\n$ARKIME_INET" | $ARKIMEDIR/bin/Configure
    else
        # pass OS user and password to Configure
        echo -e "$ARKIME_LOCALELASTICSEARCH\n$OS_USER\n$OS_PASSWORD\n$ARKIME_INET" | $ARKIMEDIR/bin/Configure
    fi
    echo INIT | $ARKIMEDIR/db/db.pl http://$OS_HOST:$OS_PORT init
    $ARKIMEDIR/bin/arkime_add_user.sh admin "Admin User" $ARKIME_ADMIN_PASSWORD --admin
    echo $ARKIME_VERSION > $ARKIMEDIR/etc/.initialized
else
    # possible update
    read old_ver < $ARKIMEDIR/etc/.initialized
    # detect the newer version
    newer_ver=`echo -e "$old_ver\n$ARKIME_VERSION" | sort -rV | head -n 1`
    # the old version should not be the same as the newer version
    # otherwise -> upgrade
    if [ "$old_ver" != "$newer_ver" ]; then
        echo "Upgrading OS database..."
        echo -e "$ARKIME_LOCALELASTICSEARCH\n$ARKIME_INET" | $ARKIMEDIR/bin/Configure
        $ARKIMEDIR/db/db.pl http://$OS_HOST:$OS_PORT upgradenoprompt
        echo $ARKIME_VERSION > $ARKIMEDIR/etc/.initialized
    fi
fi

# start cron daemon for logrotate
service cron start


echo "Look at log files for errors"
if [ "$CAPTURE" = "on" ]; then
    echo "  /data/logs/capture.log"
fi
if [ "$VIEWER" = "on" ]; then
    echo "  /data/logs/viewer.log"
fi


# check if the capture process should be started
if [ "$CAPTURE" = "on" ]; then
    # ensure /data/pcap directory is writable for user 'nobody' (used by the capture process)
    chmod 757 /data/pcap

    echo "magicMode=basic" >> $ARKIMEDIR/etc/config.ini
    echo "snapLen=65536" >> $ARKIMEDIR/etc/config.ini
    echo "readTruncatedPackets=true" >> $ARKIMEDIR/etc/config.ini
    echo "pcapReadMethod=tpacketv3" >> $ARKIMEDIR/etc/config.ini
    echo "tpacketv3NumThreads=2" >> $ARKIMEDIR/etc/config.ini
    echo "tpacketv3BlockSize=8388608" >> $ARKIMEDIR/etc/config.ini
    echo "pcapWriteSize=4194304" >> $ARKIMEDIR/etc/config.ini
    sed -i 's/pcapWriteSize=262143/pcapWriteSize=4194304/' $ARKIMEDIR/etc/config.ini

    sed -i 's/packetThreads=2/packetThreads=5/' $ARKIMEDIR/etc/config.ini
    echo "dbBulkSize=4000000" >> $ARKIMEDIR/etc/config.ini
    echo "dbEsHealthCheck=false" >> $ARKIMEDIR/etc/config.ini

    sed -i 's/maxStreams=1000000/maxStreams=2000000/' $ARKIMEDIR/etc/config.ini
    sed -i 's/# maxPacketsInQueue=200000/maxPacketsInQueue=300000/' $ARKIMEDIR/etc/config.ini
    sed -i 's/parseQSValue=false/#parseQSValue=false/' $ARKIMEDIR/etc/config.ini

    echo "Launch capture..."
    if [ "$VIEWER" = "on" ]; then
        # Background execution
        exec $ARKIMEDIR/bin/capture --config $ARKIMEDIR/etc/config.ini --host $ARKIME_HOSTNAME >> $ARKIMEDIR/logs/capture.log 2>&1 &
    else
        # If only capture, foreground execution
        exec $ARKIMEDIR/bin/capture --config $ARKIMEDIR/etc/config.ini --host $ARKIME_HOSTNAME >> $ARKIMEDIR/logs/capture.log 2>&1
    fi
fi

# check if the viewer should be started
if [ "$VIEWER" = "on" ]; then
    echo "Launch viewer..."
    echo "Visit http://127.0.0.1:8005 with your favorite browser."
    echo "  user: admin"
    echo "  password: $ARKIME_ADMIN_PASSWORD"

    pushd $ARKIMEDIR/viewer
    exec $ARKIMEDIR/bin/node viewer.js -c $ARKIMEDIR/etc/config.ini --host $ARKIME_HOSTNAME >> $ARKIMEDIR/logs/viewer.log 2>&1
    popd
fi

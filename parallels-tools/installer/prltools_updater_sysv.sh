#!/bin/sh
### BEGIN INIT INFO
# Provides:			 prltools updater
# Required-Start:	 $network $local_fs
# Required-Stop:	 
# Default-Start:	 2 3 4 5
# Default-Stop:		 0 1 6
# Short-Description: Parallels tools autoupdater service for sysV
# Description:		 Copyright (c) 2004-2014 Parallels IP Holdings GmbH.
#### END INIT INFO
###
# chkconfig: 345 06 20
# description: Autostart script for Parallels service that autoupdate tools in guest.
###

PATH=${PATH:+$PATH:}/sbin:/bin:/usr/sbin:/usr/bin

log="/var/log/parallels.log"
touch $log && chmod go+rw $log

start()
{
	( source prltools_updater.sh -i; wait $PPID )
}


case "$1" in
  start)
	start
	wait $PPID
		;;
  stop)
		;;
  *)
		echo "Usage: $0 {start}"
		exit 1
esac

exit 0

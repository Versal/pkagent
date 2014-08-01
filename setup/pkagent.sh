#! /bin/sh
### BEGIN INIT INFO
# Provides:          pkagent
# Required-Start:    $remote_fs $network $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: PubKey Agent
# Description:       PubKey Agent
### END INIT INFO

# Author: PubKey/Onepower <git@onepower.in>
#

# PATH should only include /usr/* if it runs after the mountnfs.sh script
PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin
DESC="PubKey Agent"
PKAGENTPATH="/opt/pkagent"
NAME=pkagent
DAEMON=$PKAGENTPATH/pkagent.rb
DAEMON_ARGS="--options args"
PIDFILE=/var/run/$NAME.pid
SCRIPTNAME=/etc/init.d/$NAME
BUNDLER=`which bundle`
# Exit if the package is not installed
[ -x "$DAEMON" ] || exit 0

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME

# Load the VERBOSE setting and other rcS variables
. /lib/init/vars.sh

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.2-14) to ensure that this file is present
# and status_of_proc is working.
. /lib/lsb/init-functions

#
# Function that starts the daemon/service
#
do_start()
{
	# Return
	#   0 if daemon has been started
	#   1 if daemon was already running
	#   2 if daemon could not be started
	start-stop-daemon --start --quiet --name pkagent.rb --make-pidfile --pidfile $PIDFILE --chdir $PKAGENTPATH --background --test --exec $BUNDLER -- exec ./pkagent.rb || return 1
	start-stop-daemon --start --name pkagent.rb --make-pidfile --pidfile $PIDFILE --chdir $PKAGENTPATH --background --exec $BUNDLER -- exec ./pkagent.rb || return 2
	# Add code here, if necessary, that waits for the process to be ready
	# to handle requests from services started subsequently which depend
	# on this one.  As a last resort, sleep for some time.
}

#
# Function that stops the daemon/service
#
do_stop()
{
	# Return
	#   0 if daemon has been stopped
	#   1 if daemon was already stopped
	#   2 if daemon could not be stopped
	#   other if a failure occurred
	start-stop-daemon --stop --pidfile $PIDFILE
	RETVAL="$?"
	rm -f $PIDFILE
	[ "$RETVAL" = 2 ] && return 2
}


case "$1" in
  start)
	log_daemon_msg "Starting $DESC" "($NAME)"
	do_start
	case "$?" in
		0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
		2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
	esac
	;;
  stop)
	log_daemon_msg "Stopping $DESC" "($NAME)"
	do_stop
	case "$?" in
		0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
		2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
	esac
	;;
  status)
       status_of_proc -p $PIDFILE "$DAEMON" "$NAME" && exit 0 || exit $?
       ;;
  restart|force-reload)
	log_daemon_msg "Restarting $DESC" "($NAME)"
	do_stop
	case "$?" in
	  0|1)
		do_start
		case "$?" in
			0) log_end_msg 0 ;;
			1) log_end_msg 1 ;; # Old process is still running
			*) log_end_msg 1 ;; # Failed to start
		esac
		;;
	  *)
	  	# Failed to stop
		log_end_msg 1
		;;
	esac
	;;
  *)
	#echo "Usage: $SCRIPTNAME {start|stop|restart|reload|force-reload}" >&2
	echo "Usage: $SCRIPTNAME {start|stop|status|restart|force-reload}" >&2
	exit 3
	;;
esac

:

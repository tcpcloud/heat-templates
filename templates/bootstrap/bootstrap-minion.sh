#!/bin/bash -e

#
# ENVIRONMENT
#

SALT_SOURCE=${SALT_SOURCE:-pkg}
SALT_VERSION=${SALT_VERSION:-latest}

CONFIG_DOMAIN=${CONFIG_DOMAIN:-openstack.local}
CONFIG_ADDRESS=${CONFIG_ADDRESS:-10.10.10.200}

MINION_MASTER=${MINION_MASTER:-$CONFIG_ADDRESS}
MINION_HOSTNAME=${MINION_HOSTNAME:-minion}
MINION_ID=${MINION_HOSTNAME}.${CONFIG_DOMAIN}

#
# FUNCTIONS
#

install_salt_minion_pkg_apt()
{
    echo -e "\nPreparing base OS repository ...\n"

    echo -e "deb [arch=amd64] http://apt.tcpcloud.eu/nightly/ trusty main security extra tcp" > /etc/apt/sources.list
    wget -O - http://apt.tcpcloud.eu/public.gpg | apt-key add -

    apt-get clean
    apt-get update

    echo -e "\nInstalling salt minion ...\n"

    if [ "$SALT_VERSION" == "latest" ]; then
      apt-get install -y salt-common salt-minion
    else
      apt-get install -y --force-yes salt-common=$SALT_VERSION salt-minion=$SALT_VERSION
    fi

    echo -e "\nConfiguring salt minion ...\n"
    
    [ ! -d /etc/salt/minion.d ] && mkdir -p /etc/salt/minion.d
    echo -e "master: $MINION_MASTER\nid: $MINION_ID" > /etc/salt/minion.d/minion.conf

    service salt-minion restart

    salt-call pillar.data > /dev/null 2>&1
}

install_salt_minion_pkg_yum()
{
    echo -e "\nPreparing base OS repository ...\n"

    source /etc/os-release
    yum install -y https://repo.saltstack.com/yum/redhat/salt-repo-latest-1.el${VERSION_ID}.noarch.rpm

    yum clean all

    echo -e "\nInstalling salt minion ...\n"

    if [ "$SALT_VERSION" == "latest" ]; then
        yum install -y salt-minion
    else
        yum install -y salt-minion-$SALT_VERSION
    fi

    echo -e "\nConfiguring salt minion ...\n"

    [ ! -d /etc/salt/minion.d ] && mkdir -p /etc/salt/minion.d
    echo -e "master: $MINION_MASTER\nid: $MINION_ID" > /etc/salt/minion.d/minion.conf

    service salt-minion restart

    salt-call pillar.data > /dev/null 2>&1
}

install_pip_apt()
{
    echo -e "\nPreparing base OS repository ...\n"
    
    echo -e "deb [arch=amd64] http://apt.tcpcloud.eu/nightly/ trusty main security extra tcp" > /etc/apt/sources.list
    wget -O - http://apt.tcpcloud.eu/public.gpg | apt-key add -
    
    apt-get clean
    apt-get update

    echo -e "\nInstalling pip ...\n"
    
    if [ -x "`which invoke-rc.d 2>/dev/null`" -a -x "/etc/init.d/salt-minion" ] ; then
        apt-get purge -y salt-minion salt-common && apt-get autoremove -y
    fi
    
    apt-get install -y python-pip python-dev zlib1g-dev reclass git
}

install_pip_yum()
{
    echo -e "\nPreparing base OS repository ...\n"

    yum install epel-release

    yum clean all

    echo -e "\nInstalling pip ...\n"

    yum install -y python-pip python-dev zlib1g-dev reclass git
}

install_salt_minion_pip()
{ 
    if [ "$SALT_VERSION" == "latest" ]; then
        pip install salt
    else
        pip install salt==$SALT_VERSION
    fi

    [ ! -d /etc/salt/minion.d ] && mkdir -p /etc/salt/minion.d
    echo -e "master: $MINION_MASTER\nid: $MINION_ID" > /etc/salt/minion.d/minion.conf

    # TODO: get CentOS init script variant here

    cat << 'EOF' > /etc/init.d/salt-minion
#!/bin/sh
### BEGIN INIT INFO
# Provides:          salt-minion
# Required-Start:    $remote_fs $network
# Required-Stop:     $remote_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: salt minion control daemon
# Description:       This is a daemon that controls the salt minions
### END INIT INFO

# Author: Michael Prokop <mika@debian.org>

PATH=/sbin:/usr/sbin:/bin:/usr/bin
DESC="salt minion control daemon"
NAME=salt-minion
DAEMON=/usr/bin/salt-minion
DAEMON_ARGS="-d"
PIDFILE=/var/run/$NAME.pid
SCRIPTNAME=/etc/init.d/$NAME

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME

# Exit if the package is not installed
[ -x "$DAEMON" ] || exit 0

. /lib/lsb/init-functions

do_start() {
    # Return
    #   0 if daemon has been started
    #   1 if daemon was already running
    #   2 if daemon could not be started
    pid=$(pidofproc -p $PIDFILE $DAEMON)
    if [ -n "$pid" ] ; then
        return 1
    fi

    start-stop-daemon --start --quiet --background --pidfile $PIDFILE --exec $DAEMON -- \
            $DAEMON_ARGS \
            || return 2
}

do_stop() {
    # Return
    #   0 if daemon has been stopped
    #   1 if daemon was already stopped
    #   2 if daemon could not be stopped
    #   other if a failure occurred
    start-stop-daemon --stop --quiet --retry=TERM/30/KILL/5 --pidfile $PIDFILE --name $NAME
    RETVAL="$?"
    [ "$RETVAL" = 2 ] && return 2
    rm -f $PIDFILE
    return "$RETVAL"
}

case "$1" in
    start)
        [ "$VERBOSE" != no ] && log_daemon_msg "Starting $DESC" "$NAME"
        do_start
        case "$?" in
            0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
              2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
    stop)
        [ "$VERBOSE" != no ] && log_daemon_msg "Stopping $DESC" "$NAME"
        do_stop
        case "$?" in
            0|1) [ "$VERBOSE" != no ] && log_end_msg 0 ;;
              2) [ "$VERBOSE" != no ] && log_end_msg 1 ;;
        esac
        ;;
    status)
        status_of_proc "$DAEMON" "$NAME" && exit 0 || exit $?
        ;;
    #reload)
        # not implemented
        #;;
    restart|force-reload)
        log_daemon_msg "Restarting $DESC" "$NAME"
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
        echo "Usage: $SCRIPTNAME {start|stop|status|restart|force-reload}" >&2
        exit 3
        ;;
esac

exit 0
EOF
    chmod 755 /etc/init.d/salt-minion
    ln -s /usr/local/bin/salt-minion /usr/bin/salt-minion

    service salt-minion restart

    salt-call pillar.data > /dev/null 2>&1
}

#
# MAIN
#

if [ "$SALT_SOURCE" == "pkg" ]; then
    if [[ $(which yum 2> /dev/null) ]]; then
        install_salt_minion_pkg_yum
    elif [[ $(which apt-get 2> /dev/null) ]]; then
        install_salt_minion_pkg_apt
    else
        echo "Unsupported package manager, exiting ..."
        exit 1
    fi
elif [ "$SALT_SOURCE" == "pip" ]; then
    if [[ $(which yum 2> /dev/null) ]]; then
        install_pip_yum
    elif [[ $(which apt-get 2> /dev/null) ]]; then
        install_pip_apt
    else
        echo "Unsupported package manager, exiting ..."
        exit 1
    fi
    install_salt_minion_pip
fi


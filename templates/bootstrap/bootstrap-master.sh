#!/bin/bash -e

#
# ENVIRONMENT
#

OS_VERSION=${OS_VERSION:-kilo}
OS_DISTRIBUTION=${OS_DISTRIBUTION:-ubuntu}
OS_NETWORKING=${OS_NETWORKING:-opencontrail}
OS_DEPLOYMENT=${OS_DEPLOYMENT:-single}
OS_SYSTEM="${OS_VERSION}_${OS_DISTRIBUTION}_${OS_NETWORKING}_${OS_DEPLOYMENT}"

SALT_SOURCE=${SALT_SOURCE:-pkg}
SALT_VERSION=${SALT_VERSION:-latest}

FORMULA_SOURCE=${FORMULA_SOURCE:-git}
FORMULA_PATH=${FORMULA_PATH:-/usr/share/salt-formulas}
FORMULA_BRANCH=${FORMULA_BRANCH:-master}
FORMULA_REPOSITORY=${FORMULA_REPOSITORY:-deb [arch=amd64] http://apt.tcpcloud.eu/nightly/ trusty tcp-salt}
FORMULA_GPG=${FORMULA_GPG:-http://apt.tcpcloud.eu/public.gpg}

if [ "$FORMULA_SOURCE" == "git" ]; then
  SALT_ENV="dev"
elif [ "$FORMULA_SOURCE" == "pkg" ]; then
  SALT_ENV="prd"
fi

RECLASS_ADDRESS=${RECLASS_ADDRESS:-https://github.com/tcpcloud/openstack-salt-model.git}
RECLASS_BRANCH=${RECLASS_BRANCH:-master}
RECLASS_SYSTEM=${RECLASS_SYSTEM:-$OS_SYSTEM}

CONFIG_HOSTNAME=${CONFIG_HOSTNAME:-config}
CONFIG_DOMAIN=${CONFIG_DOMAIN:-openstack.local}
CONFIG_HOST=${CONFIG_HOSTNAME}.${CONFIG_DOMAIN}
CONFIG_ADDRESS=${CONFIG_ADDRESS:-10.10.10.200}

#
# FUNCTIONS
#

install_salt_master_pkg()
{
    echo -e "\nPreparing base OS repository ...\n"
    
    echo -e "deb [arch=amd64] http://apt.tcpcloud.eu/nightly/ trusty main security extra tcp" > /etc/apt/sources.list
    wget -O - http://apt.tcpcloud.eu/public.gpg | apt-key add -
    
    apt-get clean
    apt-get update
    
    echo -e "\nInstalling salt master ...\n"
    
    apt-get install reclass git -y
    
    if [ "$SALT_VERSION" == "latest" ]; then
      apt-get install -y salt-common salt-master salt-minion
    else
      apt-get install -y --force-yes salt-common=$SALT_VERSION salt-master=$SALT_VERSION salt-minion=$SALT_VERSION
    fi

    configure_salt_master

    install_salt_minion_pkg

    echo -e "\nRestarting services ...\n"
    service salt-master restart
    [ -f /etc/salt/pki/minion/minion_master.pub ] && rm -f /etc/salt/pki/minion/minion_master.pub
    service salt-minion restart
    salt-call pillar.data > /dev/null 2>&1
}

install_salt_master_pip() 
{
    echo -e "\nPreparing base OS repository ...\n"
    
    echo -e "deb [arch=amd64] http://apt.tcpcloud.eu/nightly/ trusty main security extra tcp" > /etc/apt/sources.list
    wget -O - http://apt.tcpcloud.eu/public.gpg | apt-key add -
    
    apt-get clean
    apt-get update
    
    echo -e "\nInstalling salt master ...\n"
    
    if [ -x "`which invoke-rc.d 2>/dev/null`" -a -x "/etc/init.d/salt-minion" ] ; then
      apt-get purge -y salt-minion salt-common && apt-get autoremove -y
    fi
    
    apt-get install -y python-pip python-dev zlib1g-dev reclass git
    
    if [ "$SALT_VERSION" == "latest" ]; then
      pip install salt
    else
      pip install salt==$SALT_VERSION
    fi
    
    cat << 'EOF' > /etc/init.d/salt-master
#!/bin/sh
### BEGIN INIT INFO
# Provides:          salt-master
# Required-Start:    $remote_fs $network
# Required-Stop:     $remote_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: salt master control daemon
# Description:       This is a daemon that controls the salt minions
### END INIT INFO

# Author: Michael Prokop <mika@debian.org>

PATH=/sbin:/usr/sbin:/bin:/usr/bin
DESC="salt master control daemon"
NAME=salt-master
DAEMON=/usr/bin/salt-master
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

    start-stop-daemon --start --quiet --pidfile $PIDFILE --exec $DAEMON -- \
            $DAEMON_ARGS \
            || return 2
}

do_stop() {
    # Return
    #   0 if daemon has been stopped
    #   1 if daemon was already stopped
    #   2 if daemon could not be stopped
    #   other if a failure occurred
    pids=$(pidof -x $DAEMON)
    if [ $? -eq 0 ] ; then
       echo $pids | xargs kill 2&1> /dev/null
       RETVAL=0
    else
       RETVAL=1
    fi

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
    chmod 755 /etc/init.d/salt-master
    ln -s /usr/local/bin/salt-master /usr/bin/salt-master

    configure_salt_master

    install_salt_minion_pip

    echo -e "\nRestarting services ...\n"
    service salt-master restart
    [ -f /etc/salt/pki/minion/minion_master.pub ] && rm -f /etc/salt/pki/minion/minion_master.pub
    service salt-minion restart
    salt-call pillar.data > /dev/null 2>&1
}

configure_salt_master()
{

    [ ! -d /etc/salt/master.d ] && mkdir -p /etc/salt/master.d
    
    cat << 'EOF' > /etc/salt/master.d/master.conf
file_roots:
  base:
  - /usr/share/salt-formulas/env
pillar_opts: False
open_mode: True
reclass: &reclass
  storage_type: yaml_fs
  inventory_base_uri: /srv/salt/reclass
ext_pillar:
  - reclass: *reclass
master_tops:
  reclass: *reclass
EOF

    echo "Configuring reclass ..."
    
    [ ! -d /etc/reclass ] && mkdir /etc/reclass
    cat << 'EOF' > /etc/reclass/reclass-config.yml
storage_type: yaml_fs
pretty_print: True
output: yaml
inventory_base_uri: /srv/salt/reclass
EOF
    
    git clone ${RECLASS_ADDRESS} /srv/salt/reclass -b ${RECLASS_BRANCH}
    
    if [ ! -f "/srv/salt/reclass/nodes/${CONFIG_HOST}.yml" ]; then
    
    cat << EOF > /srv/salt/reclass/nodes/${CONFIG_HOST}.yml
classes:
- service.git.client
- system.linux.system.single
- system.openssh.client.workshop
- system.salt.master.single
- system.salt.master.formula.$FORMULA_SOURCE
- system.reclass.storage.salt
- system.reclass.storage.system.$RECLASS_SYSTEM
parameters:
  _param:
    reclass_data_repository: "$RECLASS_ADDRESS"
    reclass_data_revision: $RECLASS_BRANCH
    salt_formula_branch: $FORMULA_BRANCH
    reclass_config_master: $CONFIG_ADDRESS
    single_address: $CONFIG_ADDRESS
    salt_master_host: 127.0.0.1
    salt_master_base_environment: $SALT_ENV
  linux:
    system:
      name: ${CONFIG_HOSTNAME}
      domain: $CONFIG_DOMAIN
EOF
    
    if [ "$SALT_VERSION" == "latest" ]; then
    
    cat << EOF >> /srv/salt/reclass/nodes/${CONFIG_HOST}.yml
  salt:
    master:
      accept_policy: open_mode
      source:
        engine: $SALT_SOURCE
    minion:
      source:
        engine: $SALT_SOURCE
EOF
    
    else
    
    cat << EOF >> /srv/salt/reclass/nodes/${CONFIG_HOST}.yml
  salt:
    master:
      accept_policy: open_mode
      source:
        engine: $SALT_SOURCE
        version: $SALT_VERSION
    minion:
      source:
        engine: $SALT_SOURCE
        version: $SALT_VERSION
EOF
    
    fi

    fi

    service salt-master restart
}

install_salt_minion_pkg()
{
    echo -e "\nInstalling salt minion ...\n"

    if [ "$SALT_VERSION" == "latest" ]; then
      apt-get install -y salt-common salt-minion
    else
      apt-get install -y --force-yes salt-common=$SALT_VERSION salt-minion=$SALT_VERSION
    fi

    [ ! -d /etc/salt/minion.d ] && mkdir -p /etc/salt/minion.d
    echo -e "master: 127.0.0.1\nid: $CONFIG_HOST" > /etc/salt/minion.d/minion.conf

    service salt-minion restart
}

install_salt_minion_pip()
{
    echo -e "\nInstalling salt minion ...\n"

    [ ! -d /etc/salt/minion.d ] && mkdir -p /etc/salt/minion.d
    echo -e "master: 127.0.0.1\nid: $CONFIG_HOST" > /etc/salt/minion.d/minion.conf

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
}

install_salt_formula_pkg()
{
    echo "Configuring necessary formulas ..."
    which wget > /dev/null || (apt-get update; apt-get install -y wget)
    
    echo "${FORMULA_REPOSITORY}" > /etc/apt/sources.list.d/salt-formulas.list
    wget -O - "${FORMULA_GPG}" | apt-key add -
    
    apt-get clean
    apt-get update
    
    [ ! -d /srv/salt/reclass/classes/service ] && mkdir -p /srv/salt/reclass/classes/service
    
    declare -a FORMULA_SERVICES=("linux" "reclass" "salt" "openssh" "ntp" "git" "nginx" "collectd" "sensu" "heka" "sphinx")
    
    for FORMULA_SERVICE in "${FORMULA_SERVICES[@]}"; do
        echo -e "\nConfiguring salt formula ${FORMULA_SERVICE} ...\n"
        [ ! -d "${FORMULA_PATH}/env/${FORMULA_SERVICE}" ] && \
            apt-get install -y salt-formula-${FORMULA_SERVICE}
        [ ! -L "/srv/salt/reclass/classes/service/${FORMULA_SERVICE}" ] && \
            ln -s ${FORMULA_PATH}/reclass/service/${FORMULA_SERVICE} /srv/salt/reclass/classes/service/${FORMULA_SERVICE}
    done
    
    [ ! -d /srv/salt/env ] && mkdir -p /srv/salt/env
    [ ! -L /srv/salt/env/prd ] && ln -s ${FORMULA_PATH}/env /srv/salt/env/prd
}

install_salt_formula_git()
{
    echo "Configuring necessary formulas ..."
    
    [ ! -d /srv/salt/reclass/classes/service ] && mkdir -p /srv/salt/reclass/classes/service
    
    declare -a FORMULA_SERVICES=("linux" "reclass" "salt" "openssh" "ntp" "git" "nginx" "collectd" "sensu" "heka" "sphinx")
    
    for FORMULA_SERVICE in "${FORMULA_SERVICES[@]}"; do
        echo -e "\nConfiguring salt formula ${FORMULA_SERVICE} ...\n"
        [ ! -d "${FORMULA_PATH}/env/_formulas/${FORMULA_SERVICE}" ] && \
            git clone https://github.com/tcpcloud/salt-formula-${FORMULA_SERVICE}.git ${FORMULA_PATH}/env/_formulas/${FORMULA_SERVICE} -b ${FORMULA_BRANCH}
        [ ! -L "/usr/share/salt-formulas/env/${FORMULA_SERVICE}" ] && \
            ln -s ${FORMULA_PATH}/env/_formulas/${FORMULA_SERVICE}/${FORMULA_SERVICE} /usr/share/salt-formulas/env/${FORMULA_SERVICE}
        [ ! -L "/srv/salt/reclass/classes/service/${FORMULA_SERVICE}" ] && \
            ln -s ${FORMULA_PATH}/env/_formulas/${FORMULA_SERVICE}/metadata/service /srv/salt/reclass/classes/service/${FORMULA_SERVICE}
    done
    
    [ ! -d /srv/salt/env ] && mkdir -p /srv/salt/env
    [ ! -L /srv/salt/env/dev ] && ln -s /usr/share/salt-formulas/env /srv/salt/env/dev
}

run_salt_states()
{
    echo -e "\nReclass metadata ...\n"
    reclass --nodeinfo ${CONFIG_HOST}
    
    echo -e "\nSalt grains metadata ...\n"
    salt-call grains.items --no-color
    
    echo -e "\nSalt pillar metadata ...\n"
    salt-call pillar.data --no-color
    
    echo -e "\nRunning necessary base states ...\n"
    salt-call --retcode-passthrough state.sls linux,salt.minion,salt --no-color
    
    echo -e "\nRunning complete state ...\n"
    salt-call --retcode-passthrough state.highstate --no-color
}

#
# MAIN
#

if [ "$SALT_SOURCE" == "pkg" ]; then
    install_salt_master_pkg
elif [ "$SALT_SOURCE" == "pip" ]; then
    install_salt_master_pip
fi
if [ "$FORMULA_SOURCE" == "pkg" ]; then
    install_salt_formula_pkg
elif [ "$FORMULA_SOURCE" == "git" ]; then
     install_salt_formula_git
fi
run_salt_states


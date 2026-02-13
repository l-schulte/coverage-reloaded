#!/bin/bash
user_name="node"
group_name="node"
LOG=/tmp/container-init.log
export DBUS_SESSION_BUS_ADDRESS="autolaunch:"
export DISPLAY=":1"
export VNC_RESOLUTION="1440x768x16"
export LANG="en_US.UTF-8"
export LANGUAGE="en_US.UTF-8"

log() {
    echo -e "[$(date)] $@" | tee -a $LOG > /dev/null
}

startInBackgroundIfNotRunning() {
    log "Starting $1."
    echo -e "\n** $(date) **" | tee -a /tmp/$1.log > /dev/null
    if ! pidof $1 > /dev/null; then
        keepRunningInBackground "$@"
        while ! pidof $1 > /dev/null; do
            sleep 1
        done
        log "$1 started."
    else
        echo "$1 is already running." | tee -a /tmp/$1.log > /dev/null
        log "$1 is already running."
    fi
}

keepRunningInBackground() {
    local cmd="$3"
    (while :; do echo "[$(date)] Process started."; ${cmd}; echo "[$(date)] Process exited!; sleep 5"; done 2>&1 | tee -a /tmp/$1.log > /dev/null &)
    echo $! > /tmp/$1.pid
}

log "** SCRIPT START **"

# Start dbus
log 'Running "/etc/init.d/dbus start".'
if [ -f "/var/run/dbus/pid" ] && ! pidof dbus-daemon > /dev/null; then
    rm -f /var/run/dbus/pid
fi
/etc/init.d/dbus start 2>&1 | tee -a /tmp/dbus-daemon-system.log > /dev/null
while ! pidof dbus-daemon > /dev/null; do
    sleep 1
done

# Startup tigervnc server and fluxbox
rm -rf /tmp/.X11-unix /tmp/.X*-lock
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
chown root:${group_name} /tmp/.X11-unix

if [ "$(echo "${VNC_RESOLUTION}" | tr -cd 'x' | wc -c)" = "1" ]; then VNC_RESOLUTION=${VNC_RESOLUTION}x16; fi
screen_geometry="${VNC_RESOLUTION%*x*}"
screen_depth="${VNC_RESOLUTION##*x}"

startInBackgroundIfNotRunning "Xtigervnc" "" "tigervncserver ${DISPLAY} -geometry ${screen_geometry} -depth ${screen_depth} -rfbport 5901 -dpi ${VNC_DPI:-96} -localhost -desktop fluxbox -fg -passwd /usr/local/etc/vscode-dev-containers/vnc-passwd"

# Spin up noVNC if installed and not running
if [ -d "/usr/local/novnc" ] && [ "$(ps -ef | grep '/usr/local/novnc/noVNC*/utils/launch.sh' | grep -v grep)" = "" ]; then
    keepRunningInBackground "noVNC" "" "/usr/local/novnc/noVNC*/utils/launch.sh --listen 6080 --vnc localhost:5901"
    log "noVNC started."
else
    log "noVNC is already running or not installed."
fi

log "Executing '$@'."
exec "$@"
log "** SCRIPT EXIT **"
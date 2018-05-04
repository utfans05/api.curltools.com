#!/usr/bin/env bash

# - title        : Nova Agent Installer
# - description  : This script will Install the Nova-Agent
# - author       : Kevin Carter
# - date         : 2012-25-06
# - version      : 1
# - usage        : bash installnova.sh
# - notes        : Latest Nova Agent Installer
# - bash_version : >= 3.2.48(1)-release
# - OS Supported : Debian, Ubuntu, Fedora, CentOS, RHEL, SUSE
#### ========================================================================== ####

# Check for systemd - added 5.26.2015
if [ "$(cat /proc/1/comm)" == "systemd" ];then
    echo "Failure this script does not support systemd"
    exit 99
fi

# Checking for dependency
if [ $(which curl) ];then
    echo "
    Requirement of CURL has been found"
else
    echo "CURL has not been found on the system."
    echo "Install CURL to continue"
    echo "Exiting now"
    exit 1
fi

# Determining the Version of the Agent
NAME='nova-agent'
AGENTDOWNLOAD='http://c73fdfb81b64a729bb9c-7209acacb11dfdf4c4a2203cb01738e5.r9.cf2.rackcdn.com/nova-agent-Linux-i686-0.0.1.36.tar.gz'
NAMEOFAGENT='nova-agent-Linux-i686-0.0.1.36.tar.gz'
VERSION='0.0.1.36'
TEMPDIR="/tmp/${NAME}"
NOVADIR="/usr/share/${NAME}"
NOVAINIT="/etc/init.d/${NAME}"

# Determinig OS Type
if [ -f "/etc/issue" ];then
    RHEL=$(cat /etc/issue | grep -i '\(centos\)\|\(red\)\|\(fedora\)\|\(mageia\)')
    DEBIAN=$(cat /etc/issue | grep -i '\(debian\)\|\(ubuntu\)')
    SUSE=$(cat /etc/issue | grep -i '\(suse\)')
else
    echo -e "\nWARNING!! I could not determin your OS Type."
    echo "This Application has olny been tested on : "
    echo -e "\033[1;31mDebian, Ubuntu, Fedora, CentOS, RHEL, SUSE\033[0m"
    echo "If you are using one of these OS's then Press [ Enter ] to proceed."
    echo "If not and you would like to continue anyway, you do so at your own risk\n"
    read -p "Please Make a decision, [ Enter ] to Continue [ CTRL C ] to quit."
fi

# Removing The OLD Version of the Nova Agent.
if [ -d "${NOVADIR}" ];then
    rm -rf "${NOVADIR}"
    echo -e "\nThis script found that there was a Nova-Agent installed from before."
    echo -e "\033[1;31mThe old installation was removed.\033[0m"
fi

# Creating Working Directory
if [ -d "${TEMPDIR}" ];then
    rm -rf "${TEMPDIR}"
    echo -e "\nA Stale installation of Nova-Agent has been found in /tmp"
    echo -e "\033[1;31mThe Directory was removed\033[0m"
fi

echo -e "\nCreating Working Directory"
mkdir "${TEMPDIR}"

# Stop ALL Nova Agent Processes
echo "
Stopping ALL Nova-Agent PIDS"
for MURDER in $( ps x | awk "/`echo ${NOVADIR} | sed 's/\//\\\\\//g'`/" | awk '{print $1}' ); do kill -9 ${MURDER}; done

# Getting Files for installation
echo -e "\nGetting Files from ${DOMAINNAME}"
curl -s ${AGENTDOWNLOAD} > ${TEMPDIR}/${NAMEOFAGENT}

# Extraction of files
echo "
Decompressing files to ${TEMPDIR}/"
tar xzf ${TEMPDIR}/${NAMEOFAGENT} -C ${TEMPDIR}/

# Removing Old RUN Levels
if [ -n "$RHEL" ];then
    chkconfig ${NAME} off
    echo -e "\033[1;31mThe previous Nova-Agent Run Levels have been cleaned up\033[0m"
elif [ -n "$DEBIAN" ];then
    update-rc.d -f ${NAME} remove
    echo -e "\033[1;31mThe previous Nova-Agent Run Levels have been cleaned up\033[0m"
elif [ -n "$SUSE" ];then
    chkconfig ${NAME} off
    echo -e "\033[1;31mThe previous Nova-Agent Run Levels have been cleaned up\033[0m"
else
    echo "Because I could not determine the OS type you will have to"
    echo "remove your old RUN Levels if there is a conflict."
fi

# Removing Old Init Script
if [ -f ${NOVAINIT} ];then
    rm ${NOVAINIT}
    echo -e "\033[1;31mThe Symlink to the init.d script was removed.\033[0m"
fi

# Nova Agent Installation
echo -e "\nInstalling the Nova Agent"
bash ${TEMPDIR}/installer.sh

echo -e "\nChecking for LSB Headers in the ${NOVADIR}/${VERSION}/etc/nova-agent.init script"
if [ -z "`grep '### BEGIN INIT INFO' ${NOVADIR}/${VERSION}/etc/nova-agent.init`" ];then
    echo -e "\nNo LSB Headers Found, I am Injecting them"
    # Inject the LSB-Headers into the init Script (If NOT already there)
    sed '2i#\n# nova-agent    Allows Communication with the Hypervisor\n#\n# chkconfig: 2345 40 86\n# description: Allows Communication with the Hypervisor\n#\n### BEGIN INIT INFO\n# Provides:          nova-agent Virtual Machine Tools\n# Required-Start:    $remote_fs $syslog\n# Required-Stop:     $remote_fs $syslog\n# Default-Start:     2 3 4 5\n# Default-Stop:      0 1 6\n# Short-Description: XenServer Virtual Machine daemon providing host integration services\n# Description:       Enable service provided by daemon.\n### END INIT INFO\n' ${NOVADIR}/${VERSION}/etc/nova-agent.init > ${NOVADIR}/${VERSION}/etc/nova-agent.init.lsb

    # Copy Nova Agent into Place
    echo -e "\nMoving the new script with LSB Headers into place"
    mv -v ${NOVADIR}/${VERSION}/etc/nova-agent.init ${NOVADIR}/${VERSION}/etc/nova-agent.init.old
    cp -v ${NOVADIR}/${VERSION}/etc/nova-agent.init.lsb ${NOVADIR}/${VERSION}/etc/nova-agent.init

    # Make Nova Agent Executable
    chmod +x ${NOVAINIT}
fi

# Enable Nova Agent at Boot
echo -e "\nSystem Check"
if [ -n "$RHEL" ];then
    echo "I see that you are on RHEL-ish type OS, too bad but ok here we go..."
    echo "I will ensure that the system boots the Nova-Agent on startup."
    chkconfig nova-agent on
elif [ -n "$DEBIAN" ];then
    echo "You are using a Debian type system, Good Job!"
    echo "I will ensuring that the the Nova-Agent is started on boot."
    update-rc.d -f nova-agent defaults
elif [ -n "$SUSE" ];then
    echo "I see that you are on openSUSE, Not as good as Debian but better then RHEL-isht Distros..."
    echo "I will make sure that the system boots the Nova-Agent on startup."
    chkconfig nova-agent on
else
    echo "I could not find your system type so you will have to figure out whats up"
    echo "While the Nova Agent installation script should have ensured that the run levels were set right"
    echo "You are going to have to ensure that the NOVA Agent is turned on and able to run at boot."
    echo "Run Levels should be :"
    echo "ON  @  2 3 4 5"
    echo "OFF @  0 1 6"
fi

# Restarting The Nova-Agent
echo -e "\nRestarting the Nova Agent"

# Start up the agent
${NOVAINIT} start

echo -e "\nAll Done...\n"
exit 0

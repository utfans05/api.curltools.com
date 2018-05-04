#!/bin/bash
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# [LINUX]Rackspace RackConnect v1-v2 Network Configuration Script
# For use with the RackConnect F5 or ASA solution
#
# USAGE: bash <filename>.sh 'REGION CODE'
#
# Region codes:
# LON = LON Region
# DFW = DFW Region
# ORD = ORD Region
#
# This script is intended for use on the following operating systems:
# RHEL, CentOS, Fedora, Ubuntu, Debian
#
# The purpose of this script is to disable direct public access to the Cloud Server and properly
# configure eth1 (the service network) to communicate through a dedicated network device utilizing
# RackConnect (F5 BIG-IP device or ASA 5510 Sec+ or greater firewall).
#
# Logging has also been set to log to 'rackconnecthybridnetworkconfig[ddmmyy].log' in the current 
# working directory.
#
# NOTICE: This file may change without notice to evaluate the version of the file you are using
# please refer to the file version in the output text or the variable ${VERSION} for more information.
# Also, the output may change as well, without notice. If you have written a script that depends
# on the output of this file please evaluate the version first.
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Make sure path is enumerated properly
PATH="${PATH}:${HOME}/bin:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/sbin:/usr/sbin:"
HISTFILE=/dev/null

# Set variables
VERSION="2.2.1"
SCRIPT_NAME="Rackspace RackConnect v1-v2 Network Configuration Script Version ${VERSION}"
DestFolder="/tmp/"

# Set exit statuses
EXIT_SUCCESS=0
EXIT_NO_GW=1
EXIT_NICNOTDOWN=2
EXIT_NOLOGFILE=3
EXIT_GWNOTCHANGED=4
EXIT_INVALIDOS=5
EXIT_ARCHNOPROFILE=6
EXIT_NOFILE=21
EXIT_NOTADDEDROUTES=22
EXIT_BADREGION=23
EXIT_NOREGION=24
EXIT_BADGATEWAY=25
EXIT_UNDEFINED_STATUS=99

# Pass Supplied Argument to Variable
my_region="${1}"

# Logging
ENABLE_LOGGING="1"
LOG_FILE="rackconnecthybridnetworkconfig$(date +%d%m%y).log"

# Remove old log files if they exist
function cleanup(){
	if [[ -f  "${LOG_FILE}" ]]; then
		/bin/rm -f "${LOG_FILE}"
	fi
}

# Logs arguments to the file specified
function log(){
	# Don't try to append to a file in a directory that doesn't exist.
	[[ -d "$(dirname "${LOG_FILE}")" ]] || rba_exit "${EXIT_NOLOGFILE}"

	if [[ "${ENABLE_LOGGING}" == "1" ]]; then
		echo -n "$(date -u +'%D %r') UTC: ${*}; " >> "${LOG_FILE}" 2>/dev/null
	else
		echo "${@}"
	fi
}

# Determine OS type
function os_type(){
	if [[ `cat /etc/issue | grep -i 'ubuntu' | wc -l` -ge 1 ]]; then
		os=ubuntu
	elif [[ -f /etc/debian_version ]]; then
		os=debian
	elif [[ -f /etc/arch-release ]]; then
		os=arch
	elif [[ -f /etc/gentoo-release ]]; then
		os=gentoo
	elif [[ `cat /etc/issue | grep -i 'opensuse' | wc -l` -ge 1 ]]; then
		os=opensuse
	elif [[ -f /etc/sysconfig/network-scripts/ifcfg-eth0 || -f /etc/sysconfig/network-scripts/ifcfg-eth1 ]]; then
		os=redhat
	else
		rba_exit "${EXIT_INVALIDOS}"
	fi
	log "OS type is set to: ${os}"
}

# External commands this script will need.
function sanity_check() {
	which_cmd AWK awk
	which_cmd CAT cat
	which_cmd CHMOD chmod
	which_cmd CHPASSWD chpasswd
	which_cmd CHOWN chown
	which_cmd CP cp
	which_cmd CUT cut
	which_cmd DATE date
	which_cmd ECHO echo
	which_cmd GREP grep
	which_cmd HEAD head
	which_cmd IFCONFIG ifconfig
	which_cmd IP ip
	which_cmd MV mv
	which_cmd RM rm
	which_cmd ROUTE route
	which_cmd SED sed
	which_cmd SLEEP sleep
	which_cmd SORT sort
	which_cmd TOUCH touch
	which_cmd TR tr
	which_cmd USERADD useradd
	which_cmd WC wc
	which_cmd WGET wget

	if [[ "${os}" == "arch" ]]; then
		which_cmd NETCFG netcfg
	elif [[ "${os}" == "gentoo" ]]; then
		which_cmd RCUPDATE rc-update
	elif [[ "${os}" == "ubuntu" ]]; then
		which_cmd IFDOWN ifdown
		which_cmd IFUP ifup
	fi

	if [[ "${os}" != "arch" ]]; then
		which_cmd SERVICE service
	fi
}

# Check the location and existence of a command
function which_cmd() {
	local block=1
	if [ "a${1}" == "a-n" ]; then
		local block=0
		shift
	fi

	# Would use `which ${2}` here, but which doesn't exist in base CentOS 5.8
	local cmd="`builtin type -P ${2} 2>/dev/null`"
	if [ ${?} -gt 0 -o ! -x "${cmd}" ]; then
		if [ ${block} -eq 1 ]; then
			log "Command not found in the system path: '${2}'"
		fi
	else
		log "Command was found in the system path: '${2}' '${cmd}'"
	fi

	eval ${1}='"'"${cmd}"'"'
}

# RBA depends on status output being in a certain format
function rba_exit(){
	local RBA_START="RBA START STATUS:"
	local RBA_END="RBA END STATUS:"
	local RBA_EXIT_STATUS="${1}"

	"${ECHO}" "${RBA_START}"
	case "${1}" in
		"${EXIT_SUCCESS}")        "${ECHO}" "SUCCESS";;
		"${EXIT_NO_GW}")          "${ECHO}" "FAILED: No gateway supplied";;
		"${EXIT_NICNOTDOWN}")     "${ECHO}" "FAILED: NIC did not shutdown properly";;
		"${EXIT_NOLOGFILE}")      "${ECHO}" "FAILED: Cannt create a log file";;
		"${EXIT_GWNOTCHANGED}")   "${ECHO}" "FAILED: Proper eth1 gateway route *does not* exist";;
		"${EXIT_INVALIDOS}")      "${ECHO}" "FAILED: OS is not supported";;
		"${EXIT_ARCHNOPROFILE}")  "${ECHO}" "FAILED: No eth1 net-profile found.  Arch servers MUST use net-profiles.";;
		"${EXIT_NOFILE}")         "${ECHO}" "FAILED: Bad URL or gateway information does not exist.";;
		"${EXIT_NOTADDEDROUTES}") "${ECHO}" "FAILED: Routes were not added successfully.";;
		"${EXIT_BADREGION}")      "${ECHO}" "FAILED: Region is unknown: ${URLLocation}";;
		"${EXIT_NOREGION}")       "${ECHO}" "FAILED: No region supplied.";;
		*)                        "${ECHO}" "FAILED: Undefined exit status."
		                          RBA_EXIT_STATUS="${EXIT_UNDEFINED_STATUS}";;
	esac

	"${ECHO}" "${RBA_END}"
	"${ECHO}" "RBA START DATA:"
	rbaexitfile
	"${ECHO}" "RBA END DATA:"
	exit ${RBA_EXIT_STATUS}
}

# Exit routine for all RBA DATA
function rbaexitfile(){
	# RBA Exit data
	"${CAT}" "${LOG_FILE}" | "${SED}" 's/\; /\n/g'
}

# Make sure Arguments were passed to the Script
function checkoptions(){
	get_region_url

	log "Making the API call to get the Gateway IP Address"
	getgatewayipaddress
	log "Successfully retrieved the Gateway IP Address: '${my_gateway}'"
}

# Confirming that the proper arguments were passed
function get_region_url(){
	case "${my_region}" in
		'DFW' | 'HKG' | 'IAD' | 'LON' | 'ORD' | 'SYD')
			my_region_lowercase="$("${ECHO}" "${my_region}" | \
			                       "${SED}" 'y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/')"
			URLLocation="https://${my_region_lowercase}.api.rackconnect.rackspace.com/v1/"
			;;
		*)
			if [[ "${my_region}" == "" ]]; then
				log "No region supplied"
			else
				log "Unknown region supplied"
			fi

			log "USAGE: [Script Name].sh 'REGION CODE'"
			log "Valid region codes are: DFW HKG IAD LON ORD SYD"
			log "END [LINUX] ${SCRIPT_NAME}"

			if [[ "${my_region}" == "" ]]; then
				rba_exit "${EXIT_NOREGION}"
			else
				rba_exit "${EXIT_BADREGION}"
			fi
			;;
	esac
	log "Region is set to: '${URLLocation}'"
}

# WGET Retry Logic for all API calls
function wgetretrylogic(){
	countwgetfails=1
	# Download the file and check that it exists
	"${WGET}" --tries=5 --waitretry=10 --timeout=30 --no-check-certificate -O  "${MasterDestLocation}" "${MasterLocationURL}" --retry-connrefused  2> /tmp/wgetlog.log
	while [ `"${CAT}" /tmp/wgetlog.log | "${GREP}" -i -o "error" | "${WC}" -l` -ge 1 ] || [ `"${CAT}" /tmp/wgetlog.log | "${GREP}" -i -o "not found" | "${WC}" -l` -ge 1 ]
	do
		"${SLEEP}" 30
		log "Could not establish connection to server retrying now. Atempt #${countwgetfails}"
		"${WGET}" --tries=5 --waitretry=10 --timeout=30 --no-check-certificate -O "${MasterDestLocation}" "${MasterLocationURL}" --retry-connrefused  2> /tmp/wgetlog.log
		((countwgetfails++))
		# Retry for 5 mins if it does not work Fail.
		if [[ "${countwgetfails}" -ge 6 ]]; then
			break
		fi
	done
	
	"${RM}" -f /tmp/wgetlog.log
}

# Retrieve the gateway IP for the Cloud Server
function getgatewayipaddress(){
	GatewayIPFile="gateway_ip.txt"
	APICallGwIPAddr="gateway_ip?format=TEXT"

	MasterDestLocation="${DestFolder}${GatewayIPFile}"
	MasterLocationURL="${URLLocation}${APICallGwIPAddr}"

	wgetretrylogic

	# True if file exists and has a size greater than zero.
	if [ ! -s  "${MasterDestLocation}" ]; then
		log "Could not get Gateway IP address correctly"
		log "Bad URL or gateway information does not exist."
		log "Usage: bash <filename>.sh 'REGION CODE'"
		log "END [LINUX] ${SCRIPT_NAME}"
		rba_exit "${EXIT_NOFILE}"
	fi
	# populate the local variable and trim the whitespace
	my_dirty_gateway="`"${CAT}" "${MasterDestLocation}"`"
	my_gateway="`"${ECHO}" "${my_dirty_gateway}" | "${TR}" -d " "`"
}

# Restart the rsyslog daemon after all other scripts have run  
function syslogrestartfix(){
	log "Restarting the rsyslog now."
	if [[ "${os}" == "ubuntu" || "${os}" == "debian" ]]; then
		"${SERVICE}" rsyslog restart >/dev/null 2>/dev/null
	elif [[ "${os}" == "arch" ]]; then
		/etc/rc.d/syslog-ng restart >/dev/null 2>/dev/null
	elif [[ "${os}" == "gentoo" ]]; then
		"${SERVICE}" rsyslog restart >/dev/null 2>/dev/null
	elif [[ "${os}" == "opensuse" ]]; then
		"${SERVICE}" syslog restart >/dev/null 2>/dev/null
	else # redhat, fedora, centos
		"${SERVICE}" rsyslog restart >/dev/null 2>/dev/null
		"${SERVICE}" syslog restart >/dev/null 2>/dev/null
	fi
}

# Determine public IP (eth0)
function eth0_ip(){
	pub_ip="$("${IP}" -o addr show dev eth0 2>/dev/null | "${SED}" -ne '/eth0\s*inet /s/^.*inet \([0-9.]*\)\/.*$/\1/p')"
	if [[ "${pub_ip}" == "" ]]; then
		log "Public adapter (eth0) does not exist - exiting"
		return 1
	fi
}

# Determine private IP (eth1)
function eth1_ip(){
	priv_ip="$("${IP}" -o addr show dev eth1 2>/dev/null | "${SED}" -ne '/eth1\s*inet /s/^.*inet \([0-9.]*\)\/.*$/\1/p')"
	if [[ "${priv_ip}" == "" ]]; then
		log "Public adapter (eth0) does not exist - exiting"
		return 1
	fi
	log "Private adapter (eth1) does exist: '${priv_ip}'"
}

# Determine current eth0 gateway IP
function eth0_gw(){
	eth0_gateway="$("${IP}" -o route list exact 0.0.0.0/0 | "${SED}" -ne '/dev eth0/s/^.* via \([0-9.]*\) .*$/\1/p')"
	log "Current (eth0) Gateway IP: '${eth0_gateway}'"
}

# Determine current eth1 gateway IP
function eth1_gw(){
	eth1_gateway="$("${IP}" -o route list exact 0.0.0.0/0 | "${SED}" -ne '/dev eth1/s/^.* via \([0-9.]*\) .*$/\1/p')"
	log "Current (eth1) Gateway IP: '${eth1_gateway}'"
}

# Restart networking
function restart_net(){
	if [[ "${os}" == "ubuntu" || "${os}" == "debian" ]]; then
		"${IP}" addr flush eth1 &>/dev/null
		"${IP}" addr flush eth0 &>/dev/null
		"${IP}" route flush dev eth0 &>/dev/null
		"${IP}" route flush dev eth1 &>/dev/null
		"${IP}" link set eth0 down &>/dev/null
		"${IP}" link set eth1 down &>/dev/null
		# 'service networking restart' fails on Ubuntu 12.04 and below, but '/etc/init.d/networking restart' fails on Ubuntu 13.10+.  Try both.
		# Both of those fail on Ubuntu 14.04.  Using ifdown/ifup works on all Ubuntu, but not on Debian. So, use the init script
		# for Debian and ifdown/ifup for Ubuntu.
		if [[ "${os}" == "debian" ]]; then
			/etc/init.d/networking restart &>/dev/null || "${SERVICE}" networking restart &>/dev/null
		else
			"${IFDOWN}" eth1 &>/dev/null
			"${IFUP}" eth1 &>/dev/null
		fi

	elif [[ "${os}" == "arch" ]]; then
		"${NETCFG}" -D eth0 &>/dev/null || ( "${IP}" addr flush eth0 ; "${IP}" route flush dev eth0 ; "${IP}" link set eth0 down ) &>/dev/null
		"${NETCFG}" -R eth1 &>/dev/null
	elif [[ "${os}" == "gentoo" ]]; then
		[[ -x /etc/init.d/net.eth0 ]] && /etc/init.d/net.eth0 stop &>/dev/null || "${IP}" addr flush dev eth0 &>/dev/null
		/etc/init.d/net.eth1 restart &>/dev/null || ( "${IP}" addr flush dev eth1 ; /etc/init.d/net.eth1 restart ) &>/dev/null
	else
		"${SERVICE}" network restart &>/dev/null
	fi
	log "Networking restarted"

	if [[ "${os}" == "gentoo" ]]; then
		"${SLEEP}" 2
		/etc/init.d/sshd restart 2>/dev/null >/dev/null
		log "SSHd service restarted"
	fi
}

# Populates dns_servers variable with DNS servers, one-per-line for ease of scripting.
function get_dns() {
	if [[ "${os}" == "ubuntu" || "${os}" == "debian" ]]; then
		eth0_dns="$("${SED}" -ne '/^\s*iface\s/{h;s/^.*\s\(eth[0-9]\)\s.*$/\1/;x};/^\s*dns-nameservers\s/{G;/^\(.*\)\neth0$/{s/^\s*dns-nameservers\s\+\(.*\)\s*\n.*$/\1/;s/\s\+/\n/g;p}}' /etc/network/interfaces)"
		eth1_dns="$("${SED}" -ne '/^\s*iface\s/{h;s/^.*\s\(eth[0-9]\)\s.*$/\1/;x};/^\s*dns-nameservers\s/{G;/^\(.*\)\neth1$/{s/^\s*dns-nameservers\s\+\(.*\)\s*\n.*$/\1/;s/\s\+/\n/g;p}}' /etc/network/interfaces)"

	elif [[ "${os}" == "arch" ]]; then
		eth0_dns="$("${SED}" -ne '/^DNS\s*=\s*/{s///;s/[(")]//g;s/\s\+/\n/g;s/\n\+/\n/g;p}' /etc/network.d/eth0)"
		eth1_dns="$("${SED}" -ne '/^DNS\s*=\s*/{s///;s/[(")]//g;s/\s\+/\n/g;s/\n\+/\n/g;p}' /etc/network.d/eth1)"

	elif [[ "${os}" == "gentoo" ]]; then
		eth0_dns="$("${SED}" -ne '/^\s*dns_servers_eth0\s*=\s*\([("]\).*$/{h;s//#\1/;s/(/)/;x};G;/^\(.*\)\([")]\)\s*\n#\2/{x;s/^.*$//;x};/^\(.*\)\n#/{s/\n.*$//;s/^dns_servers_eth0\s*=\s*//;s/["()]//g;s/^\s\+//;s/\s\+$//;s/\s\+/\n/;/^$/d;p}' /etc/conf.d/net)"
		eth1_dns="$("${SED}" -ne '/^\s*dns_servers_eth1\s*=\s*\([("]\).*$/{h;s//#\1/;s/(/)/;x};G;/^\(.*\)\([")]\)\s*\n#\2/{x;s/^.*$//;x};/^\(.*\)\n#/{s/\n.*$//;s/^dns_servers_eth1\s*=\s*//;s/["()]//g;s/^\s\+//;s/\s\+$//;s/\s\+/\n/;/^$/d;p}' /etc/conf.d/net)"

	elif [[ "${os}" == "redhat" ]]; then
		# /etc/sysconfig/network entries override any device-specific entries.
		eth0_dns="$("${SED}" -ne '/^\s*DNS[0-9]*=/{G;/^\s*DNS\([0-9]*\)=.*\n\1 /d;s/\n.*$//;s/^\s*DNS\([0-9]*\)=/\1 /;p;H}' /etc/sysconfig/network /etc/sysconfig/network-scripts/ifcfg-eth0 | "${SORT}" -n | "${AWK}" '{print $2}')"
		eth1_dns="$("${SED}" -ne '/^\s*DNS[0-9]*=/{G;/^\s*DNS\([0-9]*\)=.*\n\1 /d;s/\n.*$//;s/^\s*DNS\([0-9]*\)=/\1 /;p;H}' /etc/sysconfig/network /etc/sysconfig/network-scripts/ifcfg-eth1 | "${SORT}" -n | "${AWK}" '{print $2}')"
	else
		# No device-specific DNS configs for SuSE.  Code will fall back to using /etc/resolv.conf
		eth0_dns=""
		eth1_dns=""
	fi

	if [[ "${eth0_dns}" == "" && "${eth1_dns}" == "" ]]; then
		# No DNS entries found in device config scripts, get DNS from /etc/resolv.conf instead.
		dns_servers="$("${SED}" -ne 's/^\s*nameserver\s\+\([0-9.]\+\)\s*$/\1/p' /etc/resolv.conf)"
	else
		# Dedupe while preserving order.  Prefer configured eth1 DNS servers over configured eth0 DNS servers.
		dns_servers="$( ( "${ECHO}" "${eth1_dns}" ; "${ECHO}" "${eth0_dns}" ) | "${SED}" -ne 'G;/^\([^\n]*\)\n\([^\n]*\n\)*\1\(\n\|$\)/d;s/\n.*$//;p;H')"
	fi
}

# Enumerate network devices
function get_network(){
	# This ifconfig statement tested working on all current Cloud Server OS's
	eth0_gw; eth1_gw;

	eth0_ip; eth1_ip;

	get_dns

	if [[ "${priv_ip}" != "" ]]; then
		priv_netmask=$("${IFCONFIG}" | "${GREP}" "${priv_ip}" | "${GREP}" -i 'mask' | "${AWK}" -F : '{print$4}')
	fi

	priv_macaddr=$("${IFCONFIG}" 'eth1' | "${GREP}" 'eth1' | "${GREP}" -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')

	if [[ "$pub_ip" != "" ]]; then
		pub_netmask=$("${IFCONFIG}" | "${GREP}" $pub_ip | "${GREP}" -i 'mask' | "${AWK}" -F : '{print$4}')
	fi

	pub_macaddr=$("${IFCONFIG}" 'eth0' | "${GREP}" 'eth0' | "${GREP}" -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')

	log "BEGIN: Ethernet adapter eth1"
	log "MAC Address: ${priv_macaddr}"
	log "IP Address(es): ${priv_ip}"
	log "IP Subnet(s): ${priv_netmask}"
	log "IP Gateway(s): ${eth1_gateway}"
	log "END: Ethernet adapter eth1"
	log "BEGIN: Ethernet adapter eth0"
	log "MAC Address: ${pub_macaddr}"
	log "IP Address(es): ${pub_ip}"
	log "IP Subnet(s): ${pub_netmask}"
	log "IP Gateway(s): ${eth0_gateway}"
	log "Local system DNS Servers: ${dns_servers}"
	log "END: Ethernet adapter eth0"
}

# Update with proper gateway if needed
function update_gw(){
	log "Updating gateway from: '${eth1_gateway}' to: '${my_gateway}'"
	if [[ "${os}" == "ubuntu" || "${os}" == "debian" ]]; then
		# Delete old gateway/dns entries from eth0 and eth1 config blocks
		"${SED}" -i '/^\s*iface\s/{h;s/^.*\s\(eth[0-9]\)\s.*$/\1/;x};/^\s*\(gateway\|dns-nameservers\)\s/{G;/^\(.*\)\neth[01]$/d;s/\n.*$//}' /etc/network/interfaces

		# Add correct values to eth1 block
		dns_servers_oneline="$("${ECHO}" "${dns_servers}" | "${TR}" '\n' ' ')"
		"${SED}" -i '/^\s*iface\s\+eth1\s/s/$/\n    gateway '"${my_gateway}"'\n    dns-nameservers '"${dns_servers_oneline}"'/' /etc/network/interfaces

	elif [[ "${os}" == "arch" ]]; then
		[ -f /etc/network.d/eth1 ] || rba_exit "${EXIT_ARCHNOPROFILE}"

		#CONNECTION="ethernet"
		#INTERFACE=eth1
		#IP="static"
		#ADDR="1.2.3.4"
		#NETMASK="255.255.255.0"
		#GATEWAY="1.2.3.5"
		#DNS=(2.2.2.2 3.3.3.3)
		#ROUTES=("1.2.0.0/255.2255.0.0 via 1.2.3.6" "1.3.0.0/255.255.0.0 via 1.2.3.7")

		"${SED}" -i '/^\s*WIRED_INTERFACE=/s/eth0/eth1/' /etc/conf.d/netcfg

		# Delete old gateway/dns entries from eth0 and eth1 config
		"${SED}" -i '/^\s*\(GATEWAY\|DNS\)=/d' /etc/network.d/eth{0,1} 2>/dev/null

		# Add correct values to eth1 config
		dns_servers_oneline="$("${ECHO}" "${dns_servers}" | "${TR}" '\n' ' ')"
		( "${ECHO}" "GATEWAY=\"${my_gateway}\"" ;
			"${ECHO}" "DNS=(${dns_servers_oneline})" ) >> /etc/network.d/eth1

		# Make sure that eth1 is set to start via NETWORKS
		"${SED}" -i '/^\s*NETWORKS=/{/[( ]eth1[ )]/!{s/(/(eth1 /;s/ )/)/}}' /etc/conf.d/netcfg /etc/rc.conf

		# Make sure that net-profiles is set to start at boot and "network" is not.
		# Re-enable net-profiles if it's disabled, insert it where "network" configured if
		# it's not present, or insert it at beginning of DAEMONS line if none of the above.
		"${SED}" -i '/^\s*DAEMONS=/{s/\([( ]\)[@!]*\(network[ )]\)/\1!\2/;s/!\(net-profiles[ \)]\)/\1/;/[( @]net-profiles[ )]/!{/\(!network\)\([ )]\)/{s//\1 net-profiles\2/}};/[( @]net-profiles[ )]/!{s/(/(net-profiles /;s/ )/)/}}' /etc/rc.conf

	elif [[ "${os}" == "gentoo" ]]; then
		# Gentoo allows for multi-line entries, and depending on version, could be:
		#
		# routes_eth0=( "..." "..."
		#               "..." )
		#  -or-
		# routes_eth0="...
		# ...
		# ..."

		routes_old_value="$("${SED}" -ne '/^\s*routes_eth1\s*=\s*\([("'"'"']\).*$/{h;s//#\1/;s/(/)/;x};G;/^\(.*\)\(['"'"'")]\)\s*\n#\2/{x;s/^.*$//;x};/^\(.*\)\n#/{s/\n.*$//;s/^routes_eth1\s*=\s*//;p}' /etc/conf.d/net)"

		if [[ "${routes_old_value}" == "" ]]; then
			routes_new_value='"default via '"${my_gateway}"'"'
		else
			placeholder="$("${ECHO}" "${routes_old_value}" | "${SED}" 's/^\(.\).*$/\1/;q')"

			# Handle gentoo's many variations.
			if [[  "${placeholder}" == '(' ]]; then
				# Old paren-based multi-string array
				routes_new_value="$("${ECHO}" "${routes_old_value}" | "${SED}" 's/["'"'"']\s*default\s\+via\s\+[^"'"'"']*["'"'"']\s*//;s/^(\s*/( "default via '"${my_gateway}"'" /;s/\s*$//;/^$/d')"
			elif [[ "${placeholder}" == '"' || "${placeholder}" == "'" ]]; then
				# Newer multi-line string list
				routes_new_value="$("${ECHO}" "${routes_old_value}" | "${SED}" 's/^\s*\(["'"'"']\{0,1\}\)default\s\+via\s[^"'"'"']*\(["'"'"']\{0,1\}\)\s*$/\1\2/;s/^\(["'"'"']\)/\1default via '"${my_gateway}"'\n/;s/\n"/"/')"
			else
				# Empty string, or no quotes/paren around single-line value.
				routes_new_value="$("${ECHO}" "${routes_old_value}" | "${SED}" 's/^\s*default\s\+via\s.*$//;s/^\(.*\)$/"default via '"${my_gateway}"'\n\1"/;s/\n"$/"/')"
			fi
		fi

		placeholder="$("${SED}" -ne 's/dns_servers_eth1\s*=\s*\(.\).*$/\1/p' /etc/conf.d/net)"
		if [[ "${placeholder}" == '(' ]]; then
			# Old paren-based multi-string array
			dns_new_value="$("${ECHO}" "${dns_servers}" | "${SED}" 's/\s//g;s/^/"/;s/$/"/;1s/^/( /;$s/$/ )/' | "${TR}" '\n' ' ')"
		else
			dns_new_value='"'"${dns_servers}"'"'
		fi

		# Delete routes_ and dns_servers_ blocks for eth0/eth1
		"${SED}" -i '/^\s*\(routes\|dns_servers\)_eth[01]\s*=\s*\([("'"'"']\).*$/{h;s//#\2/;s/(/)/;x};G;/^\(.*\)\(['"'"'")]\)\s*\n#\2/{x;s/^.*$//;x};/\n#/d;s/\n$//' /etc/conf.d/net

		# Add the correct (eth1 only) values.
		( "${ECHO}" "routes_eth1=${routes_new_value}" ; "${ECHO}" "dns_servers_eth1=${dns_new_value}" ) >> /etc/conf.d/net

	elif [[ "${os}" == "opensuse" ]]; then
		# Delete old default routes, if any.
		"${SED}" -i '/^\s*default\s/d' /etc/sysconfig/network/ifroute-eth{0,1}

		# Add correct value.
		"${ECHO}" "default "${my_gateway}" - - " >> /etc/sysconfig/network/ifroute-eth1

		# SuSE just uses /etc/resolv.conf for DNS, so no need to modify any interface-specific DNS config.

	elif [[ "${os}" == "redhat" ]]; then
		# Convert list of DNS servers into DNS1=..., DNS2=..., etc. lines
		dns_new_value="$("${ECHO}" "${dns_servers}" | "${SED}" = | "${SED}" 'N;s/^\(.*\)\n\(.*\)$/DNS\1=\2/')"

		# Delete old gateway and DNS lines, if present.
		"${SED}" -i '/^\s*\(DEFROUTE\|GATEWAY\|DNS[0-9]*\)\s*=/d' /etc/sysconfig/network /etc/sysconfig/network-scripts/ifcfg-eth{0,1}

		# Add correct values.
		( "${ECHO}" "DEFROUTE=yes" ;
		  "${ECHO}" "GATEWAY=${my_gateway}" ;
		  "${ECHO}" "${dns_new_value}" ) >> /etc/sysconfig/network-scripts/ifcfg-eth1

	else
		# Should be impossible.
		log "No update_gw code for OS '${OS}'!"
		log "END [LINUX] ${SCRIPT_NAME}"
		rba_exit "${EXIT_INVALIDOS}"
	fi
}

# Bring down eth0 and persist down across reboots
function disable_eth0(){
	"${IP}" addr flush eth0 2>/dev/null >/dev/null
	"${IP}" route flush dev eth0 2>/dev/null >/dev/null
	"${IP}" link set eth0 down 2>/dev/null >/dev/null
	"${SLEEP}" 2
	if [[ "$("${IP}" -o link show eth0 | "${SED}" -ne '/<\([^>,]*,\)*UP\(,[^>,]*\)*>/p')" == "" ]]; then
		log "Public adapter eth0 offline"
	else
		log "eth0 failed to be brought down - exiting"
		rba_exit "${EXIT_NICNOTDOWN}"
	fi

	log "Updating /etc/hosts file for proper name resolution"
	"${SED}" -i '/^\(\s*\)'"${pub_ip}"'\(\s\)/s//\1'"${priv_ip}"'\2/' /etc/hosts

	# Restart syslog to reflect changes in hosts file
	syslogrestartfix

	if [[ "${os}" == "ubuntu" || "${os}" == "debian" ]]; then
		# EXAMPLE: Ubuntu/Debian configs look like this
		# auto eth0
		# iface eth0 inet static
		#     address 1.2.3.4
		# netmask 255.255.255.0
		#     gateway 1.2.3.5
		#     dns-nameservers 2.2.2.2 3.3.3.3
		# auto eth1
		# iface eth1 inet static
		# ...
		
		# This comments out all lines in the appropriate iface block.
		"${SED}" -i '/^\s*iface\s/{h;s/^.*\s\(eth[0-9]\)\s.*$/\1/;x};/^\s*\(iface\|address\|netmask\|broadcast\|network\|metric\|gateway\|pointopoint\|media\|hwaddress\|mtu\|hostname\|leasehours\|leasetime\|vendor\|client\|up\|down\|pre-up\|pre-down\|dns-nameservers\)\s/{G;s/^\(.*\)\neth0$/#\1/;s/\n.*$//};/^\s*auto\s\+eth0/s/^/#/' /etc/network/interfaces
		"${SED}" -i '/^\s*auto\s\+eth0/s/^/#/' /etc/network/interfaces

		log "Commented out eth0 config in '/etc/network/interfaces'"

	elif [[ "${os}" == "arch" ]]; then
		# Arch network can be configured in a multitude of ways.  We mostly focus on fixing the one
		# that Cloud Servers configures automatically.  If the server is using an unknown method, the
		# scripts may not detect that and odd results may happen, up to and including total network
		# connectivity loss.  Unfortunately, Arch is too bleeding-edge to catch everything, so we
		# handle what we can.

		# Remove eth0 from startup
		"${SED}" -i '/^\s*NETWORKS=/{s/\s*eth0\s*/ /;s/( /(/;s/ )/)/}' /etc/rc.conf /etc/conf.d/netcfg

		#Shut down and remove eth0 net-profile
		if [ -f /etc/network.d/eth0 ]; then
			"${NETCFG}" -d eth0
			"${RM}" -f /etc/network.d/eth0 /run/network/*/eth0
		fi

		# Other methods that could be in use
		"${SED}" -i '/^\s*eth0=/d' /etc/rc.conf
		"${SED}" -i '/^\s*INTERFACES=/{s/\s*eth0\s*/ /;s/( /(/;s/ )/)/}' /etc/rc.conf
		
		if [[ "$("${SED}" -ne '/^\s*interface=\(\s*\|"\)eth0\(\s*\|"\)/p' /etc/rc.conf)" != "" ]]; then
			"${SED}" -i '/^\s*\(interface\|address\|netmask\|gateway\)=/{s/^/#/;s/=.*$/=/}' /etc/rc.conf
		fi

	elif [[ "${os}" == "gentoo" ]]; then
		# EXAMPLE: Gentoo allows for multi-line entries, and depending on version, could be
		# config_eth0="1.2.3.4"
		# dns_servers_eth0="1.1.1.1
		# 2.2.2.2"
		# routes_eth0=( "..." '...'
		#               "..." )
		#  -or-
		# routes_eth0="...
		# ...
		# ..."
		#  -or-
		# routes_eth0='...
		# ...
		# ...'

		# This ugly sed comments out blocks of either format.
		"${SED}" -i '/^\s*\(config\|routes\|dns_servers\)_eth0\s*=\s*\([("'"'"']\).*$/{h;s//#\2/;s/(/)/;x};G;/^\(.*\)\(['"'"'")]\)\s*\n#\2/{x;s/^.*$//;x};s/^\(.*\)\n\(.\{0,1\}\).*$/\2\1/' /etc/conf.d/net

		log "Commented out eth0 config in '/etc/conf.d/net'"

		# Gentoo network init scripts are all symlinks to the same script (net.lo, usually).  If net.eth1
		# has been disabled and net.eth0 exists, move the net.eth0 script to net.eth1.  Otherwise, just
		# remove the net.eth0 init script.
		if [[ -x /etc/init.d/net.eth0 ]]; then
			/etc/init.d/net.eth0 stop
			if [[ -x /etc/init.d/net.eth1 ]]; then
				"${RM}" -f /etc/init.d/net.eth0

				log "Removed net.eth0 init script"
			else
				"${RM}" -f /etc/init.d/net.eth1
				"${MV}" /etc/init.d/net.eth0 /etc/init.d/net.eth1

				log "Moved net.eth0 init script to net.eth1 init script."
			fi
		fi

		"${RCUPDATE}" del net.eth0 2>/dev/null && log "Removed eth0 autostart"

	elif [[ "${os}" == "opensuse" ]]; then
		# EXAMPLE:
		# BOOTPROTO='static'
		# IPADDR='1.2.3.4'
		# NETMASK=255.255.255.255
		# STARTMODE=auto
		# USERCONTROL='no'

		# Delete all uncommented X=Y lines except DEVICE= or HWADDR=.
		"${SED}" -i '/^\s*[^#].*=/{/^\s*\(DEVICE\|HWADDR\)\s*=/!d}' /etc/sysconfig/network/ifcfg-eth0

		# Replace with sane values.
		( "${ECHO}" 'BOOTPROTO=static' ;
		  "${ECHO}" 'IPADDR=1.1.1.1' ;
		  "${ECHO}" 'NETMASK=255.255.255.255' ;
		  "${ECHO}" 'STARTMODE=no' ;
		  "${ECHO}" 'ONBOOT=no' ;
		  "${ECHO}" 'USERCONTROL=no' ) >> /etc/sysconfig/network/ifcfg-eth0

		log "Removed eth0 config in '/etc/sysconfig/network/ifcfg-eth0'"

	elif [[ "${os}" == "redhat" ]]; then
		# EXAMPLE:
		# DEVICE=eth0
		# BOOTPROTO=static
		# HWADDR=de:ad:be:ef:13:37
		# IPADDR=1.2.3.4
		# NETMASK=255.255.255.0
		# DEFROUTE=yes
		# GATEWAY=1.2.3.5
		# DNS1=2.2.2.2
		# DNS2=3.3.3.3
		# ONBOOT=yes
		# NM_CONTROLLED=no
		
		# Delete all uncommented X=Y lines except DEVICE= or HWADDR=.
		"${SED}" -i '/^\s*[^#].*=/{/^\s*\(DEVICE\|HWADDR\)\s*=/!d}' /etc/sysconfig/network-scripts/ifcfg-eth0

		# Replace with sane values.
		( "${ECHO}" 'BOOTPROTO=static' ;
		  "${ECHO}" 'IPADDR=1.1.1.1' ;
		  "${ECHO}" 'NETMASK=255.255.255.255' ;
		  "${ECHO}" 'STARTMODE=no' ;
		  "${ECHO}" 'ONBOOT=no' ;
		  "${ECHO}" 'NM_CONTROLLED=no' ) >> /etc/sysconfig/network-scripts/ifcfg-eth0

		log "Removed eth0 config in '/etc/sysconfig/network-scripts/ifcfg-eth0'"

	else
		# Should be impossible.
		log "No disable_eth0 code for OS '${OS}'!"
		rba_exit "${EXIT_INVALIDOS}"
	fi
}

# If current eth1 and proper gateways match, do nothing. Else, update with proper gateway
function ensure_proper_gateway_eth1(){
	if [[ "${my_gateway}" == "${eth1_gateway}" ]]; then
		log "Gateways match, no change needed. REMOTE:'${my_gateway}' = CURRENT:'${eth1_gateway}'"
	else
		log "Gateway mismatch, changing network file to reflect proper gateway. REMOTE:'${my_gateway}' X CURRENT:'${eth1_gateway}'"
		update_gw
	fi
}

# Verify the gateway is current with the retrieved gateway
function verify_gateway_eth1(){
	old_eth1_gw="${eth1_gateway}"

	eth1_gw

	if [[ "${my_gateway}" == "${eth1_gateway}" ]]; then
		log "Gateway has been updated successfully from '${old_eth1_gw}' to '${eth1_gateway}'"
	else
		log "ERROR: Proper eth1 gateway route *does not* exist. Manual intervention required."
		rba_exit "${EXIT_GWNOTCHANGED}"
	fi
}

# Run the script!
function maincalls(){
	cleanup

	log "BEGIN [LINUX] ${SCRIPT_NAME}"

	log "OS DETECTION"
	os_type
	sanity_check

	log "Checking the environment and ensuring setup is correct"
	checkoptions
	get_network

	log "Get private IP (eth1)"
	eth1_ip

	log "Check current (eth0) GATEWAY IP"
	eth0_gw

	log "Check current (eth1) GATEWAY IP"
	eth1_gw

	log "Get current DNS settings"
	get_dns

	log "If current eth1 and proper gateways match, do nothing. Else, update with proper gateway"
	ensure_proper_gateway_eth1

	log "Shutting down eth0 and not adding any static routes, as all access will be performed over the newly added public IP."
	disable_eth0

	log "Restart network"
	restart_net

	log "Verify the (eth1) gateway"
	verify_gateway_eth1
	get_network

	log "END [LINUX] ${SCRIPT_NAME}"
}

# Begin running the actual script
maincalls

# If all works, exit with success
rba_exit "${EXIT_SUCCESS}"

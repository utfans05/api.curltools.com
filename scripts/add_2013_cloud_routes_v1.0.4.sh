#!/bin/bash

_VERSION_='1.0.2'

FLAG_CHECK=0
FLAG_ADD_ROUTE=0
FLAG_FORCE=0
FLAG_NO_OP=0

function usage() {
  echo "Usage: bash add_2013_cloud_routes.sh [-n] {--check | --add-route }"
  echo
  echo "    Utility to check whether a Rackspace Cloud Server has any routes that"
  echo "may conflict with the new network routes being added in June 2013.  If no"
  echo "conflicts are found, script may also be used to automatically add routes"
  echo "to the server for the following two new IP ranges:"
  echo "        10.176.0.0/12"
  echo "        10.208.0.0/12"
  echo
  echo "    Either --check or --add-route must be provided before the script will"
  echo "do anything other than print this usage statement."
  echo
  echo "Available command-line options:"
  echo "  --check:      Check to see if there are any conflicts that may prevent"
  echo "                the new routes from being added.  This mode makes no"
  echo "                changes to the system."
  echo
  echo "  --add-route:  Attempt to add the new routes to the server.  Will not"
  echo "                add any routes if system fails conflicts check.  Script"
  echo "                must be run as the root user if this option is provided."
  echo
  echo "  -n, --no-op:  Run script without actually making any changes.  Not"
  echo "                particularly useful unless you want to see what would be"
  echo "                done by --add-route without any changes being made."
  echo
  exit 2
}


function parseCLIargs() {
  while [ $# -gt 0 ]; do
    [[ "$1" == '--check'                           ]] && FLAG_CHECK=1
    [[ "$1" == '--add-route'                       ]] && FLAG_ADD_ROUTE=1
    [[ "$1" == '-n' || \
       "$1" == '--no-op'                           ]] && FLAG_NO_OP=1

    # DO NOT USE THIS OPTION with --add-route unless you absolutely know the consequences.
    # Failure to follow this advice will likely result in a BROKEN NETWORK, either immediately or on next reboot.
    [[ "$1" == '--force-mode-i-know-what-im-doing' ]] && FLAG_FORCE=1
    shift 1
  done

  # If neither --check nor --add-route were passed, print usage and exit.
  [ ${FLAG_CHECK} -eq 1 -o ${FLAG_ADD_ROUTE} -eq 1 ] || usage

  [ ${FLAG_NO_OP} -eq 1 ] && echo "No-op mode enabled.  No changes will be made, despite messages to the contrary."
}


function which_cmd() {
  # Utility function - 'which_cmd VAR cmd'
  #                    Sets VAR="`which cmd`"

  # Since some OSes (like CentOS 5.8) don't have 'which' available, this is the bash equivalent to `which ${2}`.
  local cmd="$(builtin type -P ${2} 2>/dev/null)"

  if [ -z "${cmd}" ]; then
    echo "ERROR: Unable to find '${2}' binary in system path.  Aborting."
    exit 1
  fi

  # Since ${1}='VAR' and ${cmd}='/path/to/cmd', this is basically VAR="/path/to/cmd"
  eval ${1}='"'"${cmd}"'"'
}


# Determine OS type
function os_type(){
  if [ ! -z "$("${_SED}" -ne '/ubuntu/Ip' /etc/issue)" ]; then
    os='ubuntu'
  elif [ -f /etc/debian_version ]; then
    os='debian'
  elif [ -f /etc/arch-release ]; then
    os='arch'
  elif [ -f /etc/gentoo-release ]; then
    os='gentoo'
  elif [ ! -z "$("${_SED}" -ne '/opensuse/Ip' /etc/issue)" ]; then
    os='opensuse'
  elif [ -f /etc/sysconfig/network-scripts/ifcfg-eth0 -o -f /etc/sysconfig/network-scripts/ifcfg-eth1 ]; then
    # Includes all RedHat variants (RHEL, CentOS, or Fedora).
    os='redhat'
  else
    echo "ERROR: Unable to detect OS!"
    exit 3
  fi
  echo "Auto-detected OS type as '${os}'."
}


function initial_setup() {
  # Since this calls parseCLIargs, it needs to be called with the CLI args ("$@")

  which_cmd _SED   sed
  which_cmd _TR    tr
  which_cmd _MKDIR mkdir
  which_cmd _CP    cp
  which_cmd _DATE  date

  # This is in /sbin/ on all distros I've tested, but just in case, run through bash-which if it's not there.
  if [ -x /sbin/ip ]; then
    _IP='/sbin/ip'
  else
    which_cmd _IP ip
  fi

  # Figure out what class of OS we're running.
  os_type

  # addRoute_RHEL() needs sort, none of the others do.
  if [[ "${os}" == "redhat" ]]; then
    which_cmd _SORT sort
  fi

  parseCLIargs "$@"
}


function _overlapsAny() {
  # Given two arguments of the form AAA.B.CC.DDD[/NN], determines if there's any overlap between the two
  # IPv4 network ranges using only bash and sed.  If there is overlap, a zero (true) status is returned.
  # Otherwise, a 1 (false) status is returned.

  # Making this a variable makes the code much easier to read.
  IP_SED='^\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\(\/\([0-9]\{1,2\}\)\)\{0,1\}$'

  # Save these into variables since we may modify them later.
  A_ARG="$1"
  B_ARG="$2"

  # If either argument isn't an IP, complain and return a bad status.
  if [[ -z "$(echo "${A_ARG}" | "${_SED}" -ne "/${IP_SED}/p")" ]]; then
    echo "ERROR: _overlapsAny('${A_ARG}', '${B_ARG}'): '${A_ARG}' is not an IP of the form AAA.BBB.CCC.DDD/NN." >&2
    return 255
  fi
  if [[ -z "$(echo "${B_ARG}" | "${_SED}" -ne "/${IP_SED}/p")" ]]; then
    echo "ERROR: _overlapsAny('${A_ARG}', '${B_ARG}'): '${B_ARG}' is not an IP of the form AAA.BBB.CCC.DDD/NN." >&2
    return 255
  fi

  # If no netmask was provided on either arg, add /32 so the math doesn't break later.
  [[ -z "$(echo "${A_ARG}" | "${_SED}" "s/${IP_SED}/"'\6/')" ]] && A_ARG="${A_ARG}/32"
  [[ -z "$(echo "${B_ARG}" | "${_SED}" "s/${IP_SED}/"'\6/')" ]] && B_ARG="${B_ARG}/32"

  # Turn the IP into its 32-bit decimal equivalent.  This is done by breaking up the octets of A.B.C.D
  # into a math equation (A*256^3 + B*256^2 + C*256 + D) and passing that to bash's $(( )) function.
  # (Like many programming languages, exponentiation (^) is handled by the ** operator.)
  A_IP=$(( $(echo "${A_ARG}" | "${_SED}" "s/${IP_SED}/"'(\1*256**3 + \2*256**2 + \3*256 + \4)/') ))

  # Turn the netmask into the decimal equivalent of the netmask.
  # This is done by calculating the binary negation of 2^(32-NN)-1, where NN is the mask length
  # from the CIDR notation (/NN).  This is best illustrated by an example:
  #   In binary, mask length /28 would be 11111111111111111111111111110000
  #   In decimal, 2^(32-28)-1 = 2^4-1 = 16-1 = 15
  #   In 32-bit binary, 15 = 00000000000000000000000000001111.
  #   The logical inverse of this is 11111111111111111111111111110000
  # The "& 0xFFFFFFFF" probably isn't necessary even on x86_64 systems, but it ensures that we
  # always are only dealing with 32-bit numbers.
  A_MASK=$(( $(echo "${A_ARG}" | "${_SED}" "s/${IP_SED}/"'~ (2**(32-\6)-1)/') & 0xFFFFFFFF ))

  # The first IP is calculated by doing a bitwise AND of the IP and the mask.
  # For example, 192.168.0.1/24 would have the following binary and decimal notations:
  #   11000000101010000000000000000001 = 3232235521 = 192*256^3 + 168*256^2 + 0*256 + 1 [192.168.0.1]
  # & 11111111111111111111111100000000 = ~ 00000000000000000000000011111111 = ~ 255 = ~ (2^8-1) = ~ (2^(32-24)-1)
  # = 11000000101010000000000000000000 = 3232235520 = 192*256^3 + 168*256^2 + 0*256 + 0 [192.168.0.0]
  A_FIRST_IP=$(( (A_IP & A_MASK) & 0xFFFFFFFF ))

  # The last IP is calculated by doing a bitwise OR of the IP and the logical inverse of the mask.
  # Again, using the 192.168.0.1/24 example:
  #   11000000101010000000000000000001 = 3232235521 = 192*256^3 + 168*256^2 + 0*256 + 1   [192.168.0.1]
  # | 00000000000000000000000011111111 = ~ 11111111111111111111111100000000
  # = 11000000101010000000000011111111 = 3232235775 = 192*256^3 + 168*256^2 + 0*256 + 255 [192.168.0.255]
  A_LAST_IP=$(( (A_IP | (~ A_MASK)) & 0xFFFFFFFF ))

  # Do the same thing for the second IP/netmask.
  B_IP=$(( $(echo "${B_ARG}" | "${_SED}" "s/${IP_SED}/"'(\1*256**3 + \2*256**2 + \3*256 + \4)/') ))
  B_MASK=$(( $(echo "${B_ARG}" | "${_SED}" "s/${IP_SED}/"'~ (2**(32-\6)-1)/') & 0xFFFFFFFF ))
  B_FIRST_IP=$(( (B_IP & B_MASK) & 0xFFFFFFFF ))
  B_LAST_IP=$(( (B_IP | (~ B_MASK)) & 0xFFFFFFFF ))

  ## Uncomment if you want to see the numbers.
  #printf '%18s %10d %10d\n' "${A_ARG}" "${A_FIRST_IP}" "${A_LAST_IP}" \
  #                          "${B_ARG}" "${B_FIRST_IP}" "${B_LAST_IP}"

  # To understand why the trick works, it's easiest to imagine the numeric ranges as blocks on a number line:

  # In either of these situations, there is no overlap.  Return false (1)
  # [      AAAAAAA ]     [ AAAAA        ]
  # [ BBBBB        ]     [        BBBBB ]
  # B Last < A First     B-First > A-Last
  [ ${B_LAST_IP} -lt ${A_FIRST_IP} -o ${B_FIRST_IP} -gt ${A_LAST_IP} ] && return 1

  # In any other possible situation, there is overlap and we want to return true (0).
  # [ AAAAAAA      ] [      AAAAAAA ] [   AAAAAAA    ]
  # [      BBBBBBB ] [ BBBBBBB      ] [     BBB      ]
  #
  # [     AAA      ] [     AAA      ] [   AAAAAAA    ]
  # [   BBBBBBB    ] [   BBBBBBB    ] [   BBBBBBB    ]
  return 0
}


function _getAllIPs() {
  # Utility function - parse a given string and return only the objects from it
  # that look like IPs or CIDR notation networks (AAA.BBB.CCC.DDD[/NN]).
  # Returns IP/network strings, one per line.  This being bash, "returns"="prints".
  echo "$*" | "${_SED}" -ne 's/\([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\(\/[0-9]\{1,2\}\)\{0,1\}\)/\n###IP### \1\n/g;s/\n###IP### \([^\n]*\)\n[^\n]*/\n\1/g;s/^[^\n]*\n//p'
}


function _getConflictingIPs() {
  # Utility function - finds all IPs/nets in a given string (via _getAllIPs()), then
  # checks each to see if it overlaps with 10.184.0.0/13 or 10.208.0.0/12.
  # Returns any IPs/nets that overlap either range.
  for IP in $(_getAllIPs "$*"); do
    if _overlapsAny 10.184.0.0/13 ${IP} || _overlapsAny 10.208.0.0/12 ${IP}; then
      echo ${IP}
    fi
  done
}


function gatherData() {
  # Instead of running this over and over, capture the route list into a variable.
  ROUTES="$("${_IP}" route show)"

  # Find the route for 10.176.0.0/13, 10.176.0.0/12, or 10.208.0.0/12.
  # Whatever the GW for this route is will be our ServiceNet gateway.
  SNET_GW="$(echo "${ROUTES}" | "${_SED}" -ne '/10\.\(176\|208\)\.0\.0\/1[23].* via \([0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\)\($\| .*$\)/{s//\2/p;q}')"

  SNET_DEV="$(echo "${ROUTES}" | "${_SED}" -ne '/10\.\(176\|208\)\.0\.0\/1[23].* dev \(\S*\)\($\| .*$\)/{s//\2/p;q}')"

  # This script is pretty useless if we can't determine the snet GW.
  if [[ -z "${SNET_GW}" ]]; then
    echo "ERROR: Unable to determine the ServiceNet gateway IP!"
    echo "Aborting.  No routes have been added."
    exit 1
  fi

  # Split the routes into two categories: those going to the default ServiceNet GW, and those not.
  # Anything going to the SNET_GW is going to the same place as the routes we will add, so we don't
  # need to consider them when looking for conflicts.
  ROUTES_TO_SNET="$(echo "${ROUTES}" | "${_SED}" -ne "/ via ${SNET_GW}"'\($\| \)/p')"
  ROUTES_NO_SNET="$(echo "${ROUTES}" | "${_SED}" -ne "/ via ${SNET_GW}"'\($\| \)/!p')"
}


function checkForConflicts() {
  if [[ ! -z "$(echo "${ROUTES}" | "${_SED}" -ne '/10\.176\.0\.0\/12.* via '"${SNET_GW}/p")" ]] &&
     [[ ! -z "$(echo "${ROUTES}" | "${_SED}" -ne '/10\.208\.0\.0\/12.* via '"${SNET_GW}/p")" ]]; then
    echo "Routes for new networks already exist.  Nothing to do."
    if [ ${FLAG_FORCE} -eq 1 ]; then
      echo "Script was run with force option (-f).  Continuing anyway."
    else
      exit 0
    fi
  fi

  echo -n "Checking for conflicts with existing routes..."

  # Pull the IPs and CIDRs from the route data, then test each against the two networks we're
  # checking for overlap on.
  BAD_IPS="$(_getConflictingIPs "${ROUTES_NO_SNET}")"

  # If there are no conflicts, we're good to move to the next step.
  # Otherwise, display the conflicting routes and exit with an error.
  if [[ "${BAD_IPS}" != "" ]]; then

    # Turn the list of bad IPs into a sed script that we can run against the route list to just get
    # those routes that conflict.  Because we absolutely know what each line of BAD_IPS looks like,
    # we don't have to worry about any unexpected characters breaking sed.
    BAD_IPS_SED="$(echo "${BAD_IPS}" | "${_TR}" '\n' '|' \
                  | "${_SED}" 's/\./\\./g;s@/@\\/@g;s/|/\\|/g;s@^@/\\(^\\| \\)\\(@;s@\\|$@\\)\\($\\| \\)/p@')"

    echo "CONFLICT DETECTED!"
    echo "The following routes currently overlap the IP space for the new routes being added:"

    # Print the conflicting routes, indented by 2 spaces.
    echo "${ROUTES}" | "${_SED}" -ne "${BAD_IPS_SED}" | "${_SED}" 's/^/  /'

    echo

    if [ ${FLAG_FORCE} -eq 1 ]; then
      echo "Script was run with force option (-f).  Ignoring conflicts and continuing."
    else
      echo "Aborting.  No routes have been added."
      exit 1
    fi
  else
    echo "no conflicts detected.  Safe to add routes."
  fi
}


function backup_file() {
  echo -n "Backing up $* to ${BACKUP_DIR} ..."
  if [ ${FLAG_NO_OP} -eq 0 ]; then
    "${_CP}" -L "$@" "${BACKUP_DIR}"
    if [ $? -ne 0 ]; then
      echo "ERROR during backup operation.  Aborting."
      exit 1
    fi
  fi
  echo "done."
}


function addRoute_Ubuntu() {
  # Make a backup before we make any changes.
  backup_file /etc/network/interfaces

  # Split the interfaces file into blocks for each interface.  Print lines starting with up/down
  # for the interface block corresponding to SNET_DEV.
  DEV_ROUTES="$("${_SED}" -ne '/^\s*iface\s/{h;s/^.*\s\(eth[0-9]\+\)\s.*$/\1/;x};/^\s*\(up\|down\)\s\+route\s/{G;/^\(.*\)\n'"${SNET_DEV}"'$/{s/^\(\s*\(up\|down\)\s\+route\s.*\)\n.*$/\1/;p}}' /etc/network/interfaces)"

  echo -n "Looking for a 10.176.0.0/12 route..."
  if [ -z "$(echo "${DEV_ROUTES}" | "${_SED}" -ne '/\s10\.176\.0\.0\(\s\+netmask\s\+255\.240\.0\.0\|\/12\)\s/p')" ]; then
    echo "no 10.176.0.0/12 route found."

    echo -n "Looking for a 10.176.0.0/13 route to convert..."
    if [ ! -z "$(echo "${DEV_ROUTES}" | "${_SED}" -ne '/\s10\.176\.0\.0\(\s\+netmask\s\+255\.248\.0\.0\|\/13\)\s/p')" ]; then
      echo "found an existing 10.176.0.0/13 route."
      echo -n "Changing existing 10.176.0.0/13 route to 10.176.0.0/12..."

      # Make the change.
      if [ ${FLAG_NO_OP} -eq 0 ]; then
        "${_SED}" -i 's/\(\s10\.176\.0\.0\s\+netmask\s\+255\.\)248\(\.0\.0\s\)/\1240\2/;s/\(\s10\.176\.0\.0\/\)13\(\s\)/\112\2/' /etc/network/interfaces
      fi
    else
      echo "no 10.176.0.0/13 route found."
      echo -n "Adding route for 10.176.0.0/12..."

      # This ugly block of sed parses through the interfaces file until it finds the 'iface eth1' (or
      # whatever the SNET_DEV is).  Then, it continues until it hits another line starting with auto
      # or iface (ignoring preceeding whitespace).  Once it finds one, it rewinds back a few lines if
      # those lines were blank or only contained comments.  This is basically the entire contents of
      # the file up to the insert point.  Finally, we do a line-count (using sed instead of wc -l to
      # limit the number of dependencies we have) to get the line number at which we're supposed to
      # insert the new route.
      INSERT_POINT="$("${_SED}" -ne ':AAA;p;/^\s*iface\s\+'"${SNET_DEV}"'\s/bBBB;$bBBB;n;bAAA;:BBB;n;/^\s*\(iface\|auto\)\s/!{H;$!bBBB};/^\s*\(iface\|auto\)\s\+'"${SNET_DEV}"'\(\s\|$\)/{H;$!bBBB};x;s/^\n//;s/\(\n\s*\(\|#[^\n]*\|auto\s[^\n]*\|iface\s[^\n]*\)\)*$//;p;q' /etc/network/interfaces | "${_SED}" -ne '$=')"

      # Print everything up to the insert point, print the routes, print everything after the
      # insert point.  Save it all into a variable (bash would kill the file if we tried just
      # redirecting this sequence of commands directly to /etc/network/interfaces).
      NEW_CONTENTS="$("${_SED}" -ne "1,${INSERT_POINT}p" /etc/network/interfaces ; \
                      echo "up route add -net 10.176.0.0 netmask 255.240.0.0 gw ${SNET_GW}" ; \
                      echo "down route del -net 10.176.0.0 netmask 255.240.0.0 gw ${SNET_GW}" ; \
                      "${_SED}" -e "1,${INSERT_POINT}d" /etc/network/interfaces )"

      # Sanity check that new line count is old line count +2.
      if [ $(echo "${NEW_CONTENTS}" | "${_SED}" -ne '$=') -eq $(( $("${_SED}" -ne '$=' /etc/network/interfaces) + 2 )) ]; then
        # Sanity check passed.  Replace the contents of the file with the new contents.
        if [ ${FLAG_NO_OP} -eq 0 ]; then
          echo "${NEW_CONTENTS}" > /etc/network/interfaces
        fi
      else
        echo
        echo "ERROR: Unable to auto-add 10.176.0.0/12 route.  Please manually add the following lines to /etc/network/interfaces in the ${SNET_DEV} block and re-run this script:"
        echo "up route add -net 10.176.0.0 netmask 255.240.0.0 gw ${SNET_GW}"
        echo "down route del -net 10.176.0.0 netmask 255.240.0.0 gw ${SNET_GW}"
        exit 1
      fi

    fi
    echo "done."
  else
    echo "existing 10.176.0.0/12 route found.  No need to add it."
  fi


  # Because we may have made changes, re-fetch route list so line numbers are correct.
  DEV_ROUTES="$("${_SED}" -ne '/^\s*iface\s/{h;s/^.*\s\(eth[0-9]\+\)\s.*$/\1/;x};/^\s*\(up\|down\)\s\+route\s/{G;/^\(.*\)\n'"${SNET_DEV}"'$/{s/^\(\s*\(up\|down\)\s\+route\s.*\)\n.*$/\1/;p}}' /etc/network/interfaces)"

  echo -n "Looking for a 10.208.0.0/12 route..."
  if [ -z "$(echo "${DEV_ROUTES}" | "${_SED}" -ne '/\s10\.208\.0\.0\(\s\+netmask\s\+255\.240\.0\.0\|\/12\)\s/p')" ]; then
    echo "no 10.208.0.0/13 route found."
    echo -n "Adding route for 10.208.0.0/12..."

      # See above for explanation of this sed trick.
      INSERT_POINT="$("${_SED}" -ne ':AAA;p;/^\s*iface\s\+'"${SNET_DEV}"'\s/bBBB;$bBBB;n;bAAA;:BBB;n;/^\s*\(iface\|auto\)\s/!{H;$!bBBB};/^\s*\(iface\|auto\)\s\+'"${SNET_DEV}"'\(\s\|$\)/{H;$!bBBB};x;s/^\n//;s/\(\n\s*\(\|#[^\n]*\|auto\s[^\n]*\|iface\s[^\n]*\)\)*$//;p;q' /etc/network/interfaces | "${_SED}" -ne '$=')"

      NEW_CONTENTS="$("${_SED}" -ne "1,${INSERT_POINT}p" /etc/network/interfaces ; \
                      echo "up route add -net 10.208.0.0 netmask 255.240.0.0 gw ${SNET_GW}" ; \
                      echo "down route del -net 10.208.0.0 netmask 255.240.0.0 gw ${SNET_GW}" ; \
                      "${_SED}" -e "1,${INSERT_POINT}d" /etc/network/interfaces )"

      # Sanity check that new line count is old line count +2.
      if [ $(echo "${NEW_CONTENTS}" | "${_SED}" -ne '$=') -eq $(( $("${_SED}" -ne '$=' /etc/network/interfaces) + 2 )) ]; then
        # Sanity check passed.  Replace the contents of the file with the new contents.
        if [ ${FLAG_NO_OP} -eq 0 ]; then
          echo "${NEW_CONTENTS}" > /etc/network/interfaces
        fi
      else
        echo
        echo "ERROR: Unable to auto-add 10.208.0.0/12 route.  Please manually add the following lines to /etc/network/interfaces in the ${SNET_DEV} block and re-run this script:"
        echo "up route add -net 10.208.0.0 netmask 255.240.0.0 gw ${SNET_GW}"
        echo "down route del -net 10.208.0.0 netmask 255.240.0.0 gw ${SNET_GW}"
        exit 1
      fi

    echo "done."
  else
    echo "existing 10.208.0.0/12 route found.  No need to add it."
  fi
}


function addRoute_Arch() {
  echo
  echo "WARNING: Arch has many ways of handling network configurations!  This script"
  echo "assumes that you are using the standard network configuration method used by"
  echo "the base Arch2013.2 image (individual /etc/network.d/ethX netcfg files)."

  ROUTES_FILE="/etc/network.d/${SNET_DEV}"

  if [ ! -f "${ROUTES_FILE}" ]; then
    echo "It appears that this is not the case for your installation.  Please add the"
    echo "following routes manually via your chosen network configuration method:"
    echo
    echo "   10.176.0.0/12 via ${SNET_GW} dev ${SNET_DEV}"
    echo "   10.208.0.0/12 via ${SNET_GW} dev ${SNET_DEV}"
    echo
    exit 1
  fi
  echo

  # Make a backup before we make any changes.
  backup_file "${ROUTES_FILE}"

  echo -n "Looking for a 10.176.0.0/12 route..."
  if [ -z "$("${_SED}" -ne '/10\.176\.0\.0\/\(255\.240\.0\.0\|\/12\)/p' "${ROUTES_FILE}")" ]; then
    echo "no 10.176.0.0/12 route found."

    echo -n "Looking for a 10.176.0.0/13 route to convert..."
    if [ ! -z "$("${_SED}" -ne '/10\.176\.0\.0\/\(255\.240\.0\.0\|\/12\)/p' "${ROUTES_FILE}")" ]; then
      echo "found an existing 10.176.0.0/13 route."
      echo -n "Changing existing 10.176.0.0/13 route to 10.176.0.0/12..."

      # Make the change.
      if [ ${FLAG_NO_OP} -eq 0 ]; then
        "${_SED}" -i 's/\(10\.176\.0\.0\/255\.\)248\(\.0\.0\)/\1240\2/;s/\(10\.176\.0\.0\/\)13/\112/' "${ROUTES_FILE}"
      fi
    else
      echo "no 10.176.0.0/13 route found."
      echo -n "Adding route for 10.176.0.0/12..."

      if [ -z "$("${_SED}" -ne '/^\(\s*ROUTES\s*=\s*(\s*\)\([)"'"'"']\)/p' "${ROUTES_FILE}")" ]; then
        # No ROUTES= line.  Cowardly refuse to add a new ROUTES= line, since it might break networking on next boot.
        echo "Unable to automatically add route to network config file.  Please manually add the following route to your system and re-run this script:"
        echo "   10.176.0.0/12 via ${SNET_GW} dev ${SNET_DEV}"
        exit 1
      else
        # Make the change
        if [ ${FLAG_NO_OP} -eq 0 ]; then
          "${_SED}" -i '/^\(\s*ROUTES\s*=\s*(\s*\)\([)"'"'"']\)/s//\1"10.176.0.0\/255.240.0.0 via '"${SNET_GW}"'" \2/' "${ROUTES_FILE}"
        fi
      fi
    fi
    echo "done."
  else
    echo "existing 10.176.0.0/12 route found.  No need to add it."
  fi

  echo -n "Looking for a 10.208.0.0/12 route..."
  if [ -z "$("${_SED}" -ne '/10\.208\.0\.0\/\(255\.240\.0\.0\|\/12\)/p' "${ROUTES_FILE}")" ]; then
    echo "no 10.208.0.0/12 route found."

    echo -n "Looking for a 10.208.0.0/13 route to convert..."
    if [ ! -z "$("${_SED}" -ne '/10\.208\.0\.0\/\(255\.240\.0\.0\|\/12\)/p' "${ROUTES_FILE}")" ]; then
      echo "found an existing 10.208.0.0/13 route."
      echo -n "Changing existing 10.208.0.0/13 route to 10.208.0.0/12..."

      # Make the change.
      if [ ${FLAG_NO_OP} -eq 0 ]; then
        "${_SED}" -i 's/\(10\.208\.0\.0\/255\.\)248\(\.0\.0\)/\1240\2/;s/\(10\.208\.0\.0\/\)13/\112/' "${ROUTES_FILE}"
      fi
    else
      echo "no 10.208.0.0/13 route found."
      echo -n "Adding route for 10.208.0.0/12..."

      if [ -z "$("${_SED}" -ne '/^\(\s*ROUTES\s*=\s*(\s*\)\([)"'"'"']\)/p' "${ROUTES_FILE}")" ]; then
        # No ROUTES= line.  Cowardly refuse to add a new ROUTES= line, since it might break networking on next boot.
        echo "Unable to automatically add route to network config file.  Please manually add the following route to your system and re-run this script:"
        echo "   10.208.0.0/12 via ${SNET_GW} dev ${SNET_DEV}"
        exit 1
      else
        # Make the change
        if [ ${FLAG_NO_OP} -eq 0 ]; then
          "${_SED}" -i '/^\(\s*ROUTES\s*=\s*(\s*\)\([)"'"'"']\)/s//\1"10.208.0.0\/255.240.0.0 via '"${SNET_GW}"'" \2/' "${ROUTES_FILE}"
        fi
      fi
    fi
    echo "done."
  else
    echo "existing 10.208.0.0/12 route found.  No need to add it."
  fi
}



function addRoute_Gentoo() {
  # Gentoo allows for multi-line entries, and depending on version, could be:
  #
  # routes_eth0=( "..." "..."
  #               "..." )
  #  -or-
  # routes_eth0="...
  # ...
  # ..."
  #  -or-
  # routes_eth0='...
  # ...
  # ...'

  # Make a backup before we make any changes.
  backup_file /etc/conf.d/net

  DEV_ROUTES="$("${_SED}" -ne '/^\s*routes_'"${SNET_DEV}"'\s*=\s*\([("'"'"']\).*$/{h;s//#\1/;s/(/)/;x};G;/^\(.*\)\(['"'"'")]\)\s*\n#\2/{x;s/^.*$//;x};/^\(.*\)\n#/{s/\n.*$//;s/^routes_'"${SNET_DEV}"'\s*=\s*//;p}' /etc/conf.d/net)"

  echo -n "Looking for a 10.176.0.0/12 route..."
  if [ -z "$(echo "${DEV_ROUTES}" | "${_SED}" -ne '/10\.176\.0\.0\(\s\+netmask\s\+255\.240\.0\.0\|\/12\)/p')" ]; then
    echo "no 10.176.0.0/12 route found."

    echo -n "Looking for a 10.176.0.0/13 route to convert..."
    if [ ! -z "$(echo "${DEV_ROUTES}" | "${_SED}" -ne '/10\.176\.0\.0\(\s\+netmask\s\+255\.248\.0\.0\|\/13\)/p')" ]; then
      echo "found an existing 10.176.0.0/13 route."
      echo -n "Changing existing 10.176.0.0/13 route to 10.176.0.0/12..."

      NEW_ROUTES="$(echo "${DEV_ROUTES}" | "${_SED}" 's/\(10\.176\.0\.0\s\+netmask\s\+255\.\)248\(\.0\.0\)/\1240\2/;s/\(10\.176\.0\.0\/\)13/\112/')"
    else
      echo "no 10.176.0.0/13 route found."
      echo -n "Adding route for 10.176.0.0/12..."

      if [[ "${DEV_ROUTES}" == "" ]]; then
        NEW_ROUTES='"10.176.0.0/12 via '"${SNET_GW}"'"'
      else
        FIRST_CHAR="$(echo "${DEV_ROUTES}" | "${_SED}" 's/^\(.\).*$/\1/;q')"

        # Handle gentoo's many variations.
        if [[  "${FIRST_CHAR}" == '(' ]]; then
          # Old paren-based multi-string array
          NEW_ROUTES="$(echo "${DEV_ROUTES}" | "${_SED}" 's/^(\s*/( "10.176.0.0\/12 via '"${SNET_GW}"'" /;s/\s*$//;/^$/d')"
        elif [[ "${FIRST_CHAR}" == '"' || "${FIRST_CHAR}" == "'" ]]; then
          # Newer multi-line string list
          NEW_ROUTES="$(echo "${DEV_ROUTES}" | "${_SED}" 's/^\(["'"'"']\)/\110.176.0.0\/12 via '"${SNET_GW}"'\n/;s/\n"/"/')"
        else
          # Empty string, or no quotes/paren around single-line value.
          NEW_ROUTES="$(echo "${DEV_ROUTES}" | "${_SED}" 's/^\(.*\)$/"10.176.0.0\/12 via '"${SNET_GW}"'\n\1"/;s/\n"$/"/')"
        fi
      fi
    fi

    # Make the change if anything has changed.
    if [[ "${NEW_ROUTES}" != "${DEV_ROUTES}" ]]; then
      if [ ${FLAG_NO_OP} -eq 0 ]; then
        # Do something
        # Delete the old routes_ethX entry.
        "${_SED}" -i '/^\s*routes_eth1\s*=\s*\([("'"'"']\).*$/{h;s//#\1/;s/(/)/;x};G;/^\(.*\)\(['"'"'")]\)\s*\n#\2/{x;s/^.*$//;x};/\n#/d;s/\n$//' /etc/conf.d/net

        # Add back our modified version.
        echo "routes_${SNET_DEV}=${NEW_ROUTES}" >> /etc/conf.d/net
      fi
    fi

    echo "done."
  else
    echo "existing 10.176.0.0/12 route found.  No need to add it."
  fi


  # Because we may have made changes, re-fetch route list.
  DEV_ROUTES="$("${_SED}" -ne '/^\s*routes_'"${SNET_DEV}"'\s*=\s*\([("'"'"']\).*$/{h;s//#\1/;s/(/)/;x};G;/^\(.*\)\(['"'"'")]\)\s*\n#\2/{x;s/^.*$//;x};/^\(.*\)\n#/{s/\n.*$//;s/^routes_'"${SNET_DEV}"'\s*=\s*//;p}' /etc/conf.d/net)"

  echo -n "Looking for a 10.208.0.0/12 route..."
  if [ -z "$(echo "${DEV_ROUTES}" | "${_SED}" -ne '/10\.208\.0\.0\(\s\+netmask\s\+255\.240\.0\.0\|\/12\)/p')" ]; then
    echo "no 10.208.0.0/12 route found."
    echo -n "Adding route for 10.208.0.0/12..."

    if [[ "${DEV_ROUTES}" == "" ]]; then
      NEW_ROUTES='"10.208.0.0/12 via '"${SNET_GW}"'"'
    else
      FIRST_CHAR="$(echo "${DEV_ROUTES}" | "${_SED}" 's/^\(.\).*$/\1/;q')"

      # Handle gentoo's many variations.
      if [[  "${FIRST_CHAR}" == '(' ]]; then
        # Old paren-based multi-string array
        NEW_ROUTES="$(echo "${DEV_ROUTES}" | "${_SED}" 's/^(\s*/( "10.208.0.0\/12 via '"${SNET_GW}"'" /;s/\s*$//;/^$/d')"
      elif [[ "${FIRST_CHAR}" == '"' || "${FIRST_CHAR}" == "'" ]]; then
        # Newer multi-line string list
        NEW_ROUTES="$(echo "${DEV_ROUTES}" | "${_SED}" 's/^\(["'"'"']\)/\110.208.0.0\/12 via '"${SNET_GW}"'\n/;s/\n"/"/')"
      else
        # Empty string, or no quotes/paren around single-line value.
        NEW_ROUTES="$(echo "${DEV_ROUTES}" | "${_SED}" 's/^\(.*\)$/"10.208.0.0\/12 via '"${SNET_GW}"'\n\1"/;s/\n"$/"/')"
      fi
    fi

    # Make the change if anything has changed.
    if [[ "${NEW_ROUTES}" != "${DEV_ROUTES}" ]]; then
      if [ ${FLAG_NO_OP} -eq 0 ]; then
        # Do something
        # Delete the old routes_ethX entry.
        "${_SED}" -i '/^\s*routes_eth1\s*=\s*\([("'"'"']\).*$/{h;s//#\1/;s/(/)/;x};G;/^\(.*\)\(['"'"'")]\)\s*\n#\2/{x;s/^.*$//;x};/\n#/d;s/\n$//' /etc/conf.d/net

        # Add back our modified version.
        echo "routes_${SNET_DEV}=${NEW_ROUTES}" >> /etc/conf.d/net
      fi
    fi

    echo "done."
  else
    echo "existing 10.208.0.0/12 route found.  No need to add it."
  fi
}


function addRoute_openSUSE() {
  #SUSE makes this easy.

  ROUTES_FILE="/etc/sysconfig/network/ifroute-${SNET_DEV}"

  # Make a backup before we make any changes.
  backup_file "${ROUTES_FILE}"

  echo -n "Looking for a 10.176.0.0/12 route..."
  if [ -z "$("${_SED}" -ne '/^\s*10\.176\.0\.0\(\s\+\S*\s\+255\.240\.0\.0\|\/12\)\s/p' "${ROUTES_FILE}")" ]; then
    echo "no 10.176.0.0/12 route found."

    echo -n "Looking for a 10.176.0.0/13 route to convert..."
    if [ ! -z "$("${_SED}" -ne '/^\s*10\.176\.0\.0\(\s\+\S*\s\+255\.248\.0\.0\|\/13\)\s/p' "${ROUTES_FILE}")" ]; then
      echo "found an existing 10.176.0.0/13 route."
      echo -n "Changing existing 10.176.0.0/13 route to 10.176.0.0/12..."

      # Make the change.
      if [ ${FLAG_NO_OP} -eq 0 ]; then
        "${_SED}" -i 's/^\(\s*10\.176\.0\.0\s\+\S*\s\+255\.\)248\(\.0\.0\s\)/\1240\2/;s/^\(\s*10\.176\.0\.0\/\)13\(\s\)/\112\2/' \
          "${ROUTES_FILE}"
      fi
    else
      echo "no 10.176.0.0/13 route found."
      echo -n "Adding route for 10.176.0.0/12..."

      if [ ${FLAG_NO_OP} -eq 0 ]; then
	echo "10.176.0.0 ${SNET_GW} 255.240.0.0 ${SNET_DEV}" >> "${ROUTES_FILE}"
      fi

    fi
    echo "done."
  else
    echo "existing 10.176.0.0/12 route found.  No need to add it."
  fi

  echo -n "Looking for a 10.208.0.0/12 route..."
  if [ -z "$("${_SED}" -ne '/^\s*10\.208\.0\.0\(\s\+\S*\s\+255\.240\.0\.0\|\/12\)\s/p' "${ROUTES_FILE}")" ]; then
    echo "no 10.208.0.0/13 route found."
    echo -n "Adding route for 10.208.0.0/12..."

    if [ ${FLAG_NO_OP} -eq 0 ]; then
      echo "10.208.0.0 ${SNET_GW} 255.240.0.0 ${SNET_DEV}" >> "${ROUTES_FILE}"
    fi

    echo "done."
  else
    echo "existing 10.208.0.0/12 route found.  No need to add it."
  fi
}


function addRoute_RHEL() {
  # There are two places where RHEL could be storing routes:
  #   The old way is to use /etc/sysconfig/static-routes.  This has been deprecated since Redhat 8.
  #   The new way is to use /etc/sysconfig/network-scripts/route-ethN.

  CHECK_OLD=0
  CHECK_NEW=0

  if [ -f /etc/sysconfig/static-routes ]; then
    CHECK_OLD=1
    backup_file /etc/sysconfig/static-routes
  fi

  ROUTES_FILE="/etc/sysconfig/network-scripts/route-${SNET_DEV}"
  if [ -f "${ROUTES_FILE}" ]; then
    CHECK_NEW=1
    backup_file "${ROUTES_FILE}"
  fi

  # Since route-ethN has been supported since RH 8, which is older than any Cloud Server
  # we have, use it as the default if neither file exists.
  if [ ${CHECK_OLD} -eq 0 -a ${CHECK_NEW} -eq 0 ]; then
    # If the code ever reaches here, someone has broken their system soundly.
    echo -n "No route config files found!!!  Generating new one in '${ROUTES_FILE}'..."
    echo "10.176.0.0/12 via ${SNET_GW} dev ${SNET_DEV}" >> "${ROUTES_FILE}"
    echo "10.208.0.0/12 via ${SNET_GW} dev ${SNET_DEV}" >> "${ROUTES_FILE}"
    echo "done."
  fi

  # Not the most elegant solution, but it works.  For the case where we're checking both files,
  # keep track of what routes were found in the old file.
  OLD_HAS_176=0
  OLD_HAS_208=0

  # Check /etc/sysconfig/static-routes
  if [ ${CHECK_OLD} -eq 1 ]; then
    # Routes in this file look like this:
    #   iface type dest-addr netmask netmask gw gateway-addr
    #   eth0 net 192.168.170.0 netmask 255.255.255.0 gw 192.168.168.1

    echo -n "Looking for a 10.176.0.0/12 route in old-style config..."
    if [ -z "$("${_SED}" -ne '/\s10\.176\.0\.0\(\s\+netmask\s\+255\.240\.0\.0\|\/12\)\s/p' /etc/sysconfig/static-routes)" ]; then
      echo "no 10.176.0.0/12 route found."

      echo -n "Looking for a 10.176.0.0/13 route in old-style config to convert..."
      if [ ! -z "$("${_SED}" -ne '/\s10\.176\.0\.0\(\s\+netmask\s\+255\.248\.0\.0\|\/13\)\s/p' /etc/sysconfig/static-routes)" ]; then
        echo "found an existing 10.176.0.0/13 route."
        echo -n "Changing existing 10.176.0.0/13 route to 10.176.0.0/12..."

        # Make the change.
        if [ ${FLAG_NO_OP} -eq 0 ]; then
          "${_SED}" -i 's/\(\s10\.176\.0\.0\s\+netmask\s\+255\.\)248\(\.0\.0\s\)/\1240\2/;s/\(\s10\.176\.0\.0\/\)13\(\s\)/\112\2/' \
            /etc/sysconfig/static-routes
        fi
        OLD_HAS_176=1
      else
        echo "no 10.176.0.0/13 route found."

        # Only add the route to the old config file if we're not checking the new one.
        if [ ${CHECK_NEW} -eq 0 ]; then
          echo -n "Adding route for 10.176.0.0/12 to old-style config..."

          if [ ${FLAG_NO_OP} -eq 0 ]; then
            # CentOS/RHEL no longer support specifying device, must make route "any" or it won't get applied.
            echo "any net 10.176.0.0 netmask 255.240.0.0 gw ${SNET_GW}" >> /etc/sysconfig/static-routes
          fi
        fi
      fi
      echo "done."
    else
      echo "existing 10.176.0.0/12 route found.  No need to add it."
      OLD_HAS_176=1
    fi

    echo -n "Looking for a 10.208.0.0/12 route in old-style config..."
    if [ -z "$("${_SED}" -ne '/\s10\.208\.0\.0\(\s\+netmask\s\+255\.240\.0\.0\|\/12\)\s/p' /etc/sysconfig/static-routes)" ]; then
      echo "no 10.208.0.0/13 route found."

      # Only add the route to the old config file if we're not checking the new one.
      if [ ${CHECK_NEW} -eq 0 ]; then
        echo -n "Adding route for 10.208.0.0/12 to old-style config..."

        if [ ${FLAG_NO_OP} -eq 0 ]; then
          echo "any net 10.208.0.0 netmask 255.240.0.0 gw ${SNET_GW}" >> /etc/sysconfig/static-routes
        fi

        echo "done."
      fi
    else
      echo "existing 10.208.0.0/12 route found.  No need to add it."
      OLD_HAS_208=1
    fi
  fi


  # Check /etc/sysconfig/network-scripts/route-ethN
  if [ ${CHECK_NEW} -eq 1 ]; then

    # RHEL has two different valid formats for this file.
    #
    # Multi-Line style:
    # ADDRESS0=1.2.3.4
    # NETMASK0=255.255.192.0
    # GATEWAY0=4.3.2.1
    #
    # Single-Line style:
    # 1.2.3.4/5 via 4.3.2.1 dev eth1
    #

    # If the old config file has the route, don't add a duplicate here - might break networking if we do.
    if [ ${OLD_HAS_176} -eq 0 ]; then
      # Turn multi-line style entries into something one-line-per-route (Num IP Mask GW).
      ML_ROUTES="$("${_SED}" 's/^\s*\(ADDRESS\|NETMASK\|GATEWAY\)\([0-9]\+\)\s*=\s*\([0-9.]*\)\s*$/\2 \1 \3/' \
                  "${ROUTES_FILE}" | "${_SORT}" -n \
                  | "${_SED}" -ne '1h;:AAA;n;H;x;/^\([0-9]\+\) .*\n\1 /!bBBB;s/\n\S* / /;h;$bBBB;bAAA;:BBB;$!s/\n[^\n]*$//;s/^\([0-9]\+\) ADDRESS \([0-9.]*\) GATEWAY \([0-9.]*\) NETMASK \([0-9.]*\)\s*$/\1 \2 \4 \3/p;$!bAAA' \
                  )"


      # Convert single-line routes to (CIDR GW)
      SL_ROUTES="$("${_SED}" -ne '/^\s*\([0-9.]\+\(\/[0-9]\+\)*\).*\s\+via\s\+\([0-9.]*\).*$/s//\1 \3/p' "${ROUTES_FILE}")"

      echo -n "Looking for a 10.176.0.0/12 route..."
      # If 10.176.0.0/12 isn't in multi-line nor single-line routes, we need to add it.
      if [ -z "$(echo "${ML_ROUTES}" | "${_SED}" -ne '/ 10\.176\.0\.0 255\.240\.0\.0 /p')" ] && \
        [ -z "$(echo "${SL_ROUTES}" | "${_SED}" -ne '/^10\.176\.0\.0\/12 /p')" ]; then
        echo "no 10.176.0.0/12 route found."
        echo -n "Looking for a 10.176.0.0/13 route to convert..."

        # Look for a 10.176.0.0/13 route to convert to /12.
        if [ ! -z "$(echo "${ML_ROUTES}" | "${_SED}" -ne '/ 10\.176\.0\.0 255\.248\.0\.0 /p')" ]; then
          echo "found a multi-line route for 10.176.0.0/13."
          echo -n "Changing existing 10.176.0.0/13 route to 10.176.0.0/12..."

          CHANGE_ROUTE_SED="$(echo "${ML_ROUTES}" \
                              | "${_SED}" -ne '/^\([0-9]\+\) 10\.176\.0\.0 255\.248\.0\.0 .*$/s//s@^\\(\\s*NETMASK\1\\s*=\\s*\\)255\\.248\\.0\\.0@\\1255.240.0.0@/p')"

          # Sanity check.  In theory, shouldn't be possible.
          if [ -z "${CHANGE_ROUTE_SED}" ]; then
            echo "Unable to change multi-line route.  Please edit ${ROUTES_FILE} manually and change the existing entry which looks something like this:"
            echo "      10.176.0.0 255.248.0.0"
            echo "into one that looks like this, then re-run this script:"
            echo "      10.176.0.0 255.240.0.0"
            exit 1
          fi

          # Make the change.
          if [ ${FLAG_NO_OP} -eq 0 ]; then
            "${_SED}" -i "${CHANGE_ROUTE_SED}" "${ROUTES_FILE}"
          fi
        elif [ ! -z "$(echo "${SL_ROUTES}" | "${_SED}" -ne '/^10\.176\.0\.0\/13 /p')" ]; then
          echo "found a single-line route for 10.176.0.0/13."
          echo -n "Changing existing 10.176.0.0/13 route to 10.176.0.0/12..."

          # CIDR notation is much easier to change.
          if [ ${FLAG_NO_OP} -eq 0 ]; then
            "${_SED}" -i 's@^\(\s*\)10\.176\.0\.0\/13@\110.176.0.0/12@' "${ROUTES_FILE}"
          fi
        else
          echo "no 10.176.0.0/13 route found."
          echo -n "Adding route for 10.176.0.0/12..."
          if [ -z "${SL_ROUTES}" ]; then
            # Using multi-line mode.  Figure out last route # and add 1.

            ROUTE_NUM=$(( $(echo "${ML_ROUTES}" | "${_SED}" -ne '$s/ .*$/+1/p;s/^$/0/') ))

            if [ ${FLAG_NO_OP} -eq 0 ]; then
              ( echo "ADDRESS${ROUTE_NUM}=10.176.0.0" ; \
                echo "NETMASK${ROUTE_NUM}=255.240.0.0" ; \
                echo "GATEWAY${ROUTE_NUM}=${SNET_GW}" ) >> "${ROUTES_FILE}"
            fi

          else
            # Using single-line mode.  Just add the route.
            if [ ${FLAG_NO_OP} -eq 0 ]; then
              echo "10.176.0.0/12 via ${SNET_GW} dev ${SNET_DEV}" >> "${ROUTES_FILE}"
            fi
          fi
        fi
        echo "done."
      else
        echo "existing 10.176.0.0/12 route found.  No need to add it."
      fi
    fi

    # If the old config file has the route, don't add a duplicate here - might break networking if we do.
    if [ ${OLD_HAS_208} -eq 0 ]; then
      # Because we may have made changes, re-fetch route lists so line numbers are correct.
      ML_ROUTES="$("${_SED}" 's/^\s*\(ADDRESS\|NETMASK\|GATEWAY\)\([0-9]\+\)\s*=\s*\([0-9.]*\)\s*$/\2 \1 \3/' \
                  "${ROUTES_FILE}" | "${_SORT}" -n \
                  | "${_SED}" -ne '1h;:AAA;n;H;x;/^\([0-9]\+\) .*\n\1 /!bBBB;s/\n\S* / /;h;$bBBB;bAAA;:BBB;$!s/\n[^\n]*$//;s/^\([0-9]\+\) ADDRESS \([0-9.]*\) GATEWAY \([0-9.]*\) NETMASK \([0-9.]*\)\s*$/\1 \2 \4 \3/p;$!bAAA' \
                  )"
      SL_ROUTES="$("${_SED}" -ne '/^\s*\([0-9.]\+\(\/[0-9]\+\)*\).*\s\+via\s\+\([0-9.]*\).*$/s//\1 \3/p' "${ROUTES_FILE}")"

      echo -n "Looking for a 10.208.0.0/12 route..."
      if [ -z "$(echo "${ML_ROUTES}" | "${_SED}" -ne '/ 10\.208\.0\.0 255\.240\.0\.0 /p')" ] && \
        [ -z "$(echo "${SL_ROUTES}" | "${_SED}" -ne '/^10\.208\.0\.0\/12 /p')" ]; then
        echo "no 10.208.0.0/13 route found."
        echo -n "Adding route for 10.208.0.0/12..."
        if [ -z "${SL_ROUTES}" ]; then
          # Using multi-line mode.  Figure out last route # and add 1.

          ROUTE_NUM=$(( $(echo "${ML_ROUTES}" | "${_SED}" -ne '$s/ .*$/+1/p;s/^$/0/') ))

          if [ ${FLAG_NO_OP} -eq 0 ]; then
            ( echo "ADDRESS${ROUTE_NUM}=10.208.0.0" ; \
              echo "NETMASK${ROUTE_NUM}=255.240.0.0" ; \
              echo "GATEWAY${ROUTE_NUM}=${SNET_GW}" ) >> "${ROUTES_FILE}"
          fi
        else
          # Using single-line mode.  Just add the route.
          if [ ${FLAG_NO_OP} -eq 0 ]; then
            echo "10.208.0.0/12 via ${SNET_GW} dev ${SNET_DEV}" >> "${ROUTES_FILE}"
          fi
        fi
        echo "done."
      else
        echo "existing 10.208.0.0/12 route found.  No need to add it."
      fi
    fi
  fi






}


function addRoute() {
  if [[ "${UID}" != "0" ]]; then
    echo "ERROR: In order to make changes, this script must be run as root.  Aborting."
    exit 1
  fi

  BACKUP_DIR="/root/.cloud_routes_backup_$("${_DATE}" '+%s')/"

  if [ ${FLAG_NO_OP} -eq 0 ]; then
    # Create a backup directory for storing the pre-change config files
    "${_MKDIR}" -p "${BACKUP_DIR}"
    "${_IP}" route show > "${BACKUP_DIR}/_old_routes_"
  fi

  if [[ "${os}" == "ubuntu" || "${os}" == "debian" ]]; then
    addRoute_Ubuntu
  elif [[ "${os}" == "arch" ]]; then
    addRoute_Arch
  elif [[ "${os}" == "gentoo" ]]; then
    addRoute_Gentoo
  elif [[ "${os}" == "opensuse" ]]; then
    addRoute_openSUSE
  elif [[ "${os}" == "redhat" ]]; then
    addRoute_RHEL
  else
    echo "OS type '${os}' is not supported by this script."
    exit 1
  fi

  # If we made it this far, route changes will survive a reboot.  Normally would restart networking
  # here, but this change should be as non-disruptive as possible.  Instead, manually add the
  # routes to the routing table.  Ignore errors since the server may have already been configured
  # with 10.176.0.0/12 instead of 10.176.0.0/13.
  if [ ${FLAG_NO_OP} -eq 0 ]; then
    "${_IP}" route add 10.208.0.0/12 via ${SNET_GW} dev ${SNET_DEV} 2>/dev/null
    "${_IP}" route add 10.176.0.0/12 via ${SNET_GW} dev ${SNET_DEV} 2>/dev/null
    [ $? -eq 0 ] && "${_IP}" route del 10.176.0.0/13 via ${SNET_GW} dev ${SNET_DEV} 2>/dev/null
  fi

  echo 'Routes added successfully.'
}


function main() {
  initial_setup "$@"

  gatherData

  [ ${FLAG_CHECK} -eq 1 -o ${FLAG_ADD_ROUTE} -eq 1 ] && checkForConflicts

  [ ${FLAG_ADD_ROUTE} -eq 1 ] && addRoute
}

main "$@"
exit 0

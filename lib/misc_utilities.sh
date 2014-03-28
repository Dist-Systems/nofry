#!/bin/bash

#######################################
# send a notification email
#  @param -recipient email address
#  @param -email subject
#  @param -email message
notify_email(){
  if [ $# -ne 3 ]; then
    echo "$0 requires:\n (string) email\n (string) subject\n (string) message\n"
    return 1;
  fi
  
  local to=$1
  local subject=`printf "$2 %s"`
  local message=`printf "$3 %s"`
  
  mail_success=$(printf "$message %s"| mail -s "$subject" $to)
  return $mail_success
}

#######################################
# send a notification trap
#    @param -recipient ip address
#    @param -enterprise OID of trap
#    @param -OID of trap
#    @param -value of trap
notify_trap(){
  if [ $# -ne 4 ]; then
    echo "$0 requires: ip, e.oid, oid, value"
    return 1;
  fi

  local host=$1
  local eoid=$2
  local my_oid=$3
  local value=$4

  # Since this is an enterprise specific trap, the generic trap will always be '6'
  
  # snmptrap -v1 -ctrap nofry NHDC::shutdownTrapNC "" 6 1 "" NHDC::shutdownFlag.0 i 3
  return_value=$(snmptrap -v1 -ctrap $host $eoid "" 6 1 "" $my_oid i $value)
  return $return_value
}


#######################################
# update_status
#    @param -integer number that the flag should be
update_status(){
  if [ $# -ne 1 ]; then
    echo "$0 requires: integer"
    return 1;
  fi

  re='^[0-3]$'
  if ! [[ $1 =~ $re ]] ; then
     echo "$0 requires: integer [0-3]"
     return 1;
  fi

  local _status=$1
  #TODO this should be in a conf file (NCS 11/19/2013)
  local archive_name=/opt/nofry/status/`date +%s`-status.txt

  # create a subshell with an exclusive lock on the status file
  ( 
    flock -e 200
    # copy the contents of the file to an archive location
    cat $STATUS_FILE>$archive_name

    # put the new status in the file
    local return_value=$(echo $_status>$STATUS_FILE)
    
    # exaggerate the time for this operation while developing
    [[ $DEBUG ]] && sleep 5

    # unlock the file
  )200>$STATUS_FILE

  return $return_value
}

#######################################
# dispatch_action
#    @param -integer number of the current status
dispatch_action(){
  if [ $# -ne 1 ]; then
    echo "$0 requires: integer"
    return 1;
  fi

  re='^[0-3]$'
  if ! [[ $1 =~ $re ]] ; then
     echo "$0 requires: integer [0-3]"
     return 1;
  fi

  local _status=$1
  case $_status in 
    0)
      # everything is operational
      logger "$0: operational state"
      ;;
    1)
      # UPS is on bypass
      logger "$0: ups on bypass"

      #TODO
      notify_email ${SCRIPTADMIN} "UPS on bypass" "UPS on bypass (${0})"
      ;;
    2)
      # NC hightemp
      logger "$0: Non-Critical high temp"
      #TODO

      notify_email ${SCRIPTADMIN} "NC shutdown req." "NC shutdown req. (${0})"
      ;;
    3)
      #C2 hightemp
      logger "$0: Critical 2 high temp"

      #TODO
      notify_email ${SCRIPTADMIN} "C2 shutdown req." "C2 shutdown req. (${0})"
      ;;
    esac
}

#######################################
# set_shutdown_flag
#    @param -integer number that the flag should be
# set_shutdown_flag(){
#   if [ $# -ne 1 ]; then
#     echo "$0 requires: string"
#     return 1;
#   fi
# 
#   local HOST=$1
#   
#   # killbot uses: 'snmpset -v1 -cendor localhost .1.3.6.1.4.1.16772.5.2.1.0 i 0'
#   # RETURN_VALUE=`snmpset -v1 -c endor killbot .1.3.6.1.4.1.16772.5.2.1.0 i $flag`
#   return $RETURN_VALUE
# }

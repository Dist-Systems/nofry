#!/bin/bash

#######################################
# check the temperature of a cabinet distribution unit
#    @param - dns name of the CDU
check_cdu_temp(){
  if [ $# -ne 1 ] ; then
    echo "$0 requires a string (dnsName)"
    return 1;
  fi

  # DNS name of the CDU
  local cdu_name="$1"

  # Query the CDU temperature probe and capture the value 
  local tempx10=`snmpget -v2c -c public $cdu_name enterprises.1718.3.2.5.1.6.1.1| awk  -F 'INTEGER: ' '{print $2}'`
  local return_value=$?

  # Sets the variable as floating point value
  # CDU_TEMP=`bc <<< "scale = 1; ($TEMPx10 / 10)"`

  # Sets the variable as truncated integer (no rounding)
  local cdu_temp=$(($tempx10/10))

  echo $cdu_temp

  return $return_value;
}
 
#######################################
# check the room temperature sensor (weathergoose)
#    @param - dns name of the room sensor
check_room_temp(){

  if [ $# -ne 1 ] ; then
    echo "$0 requires a string (dnsName)"
    return 1;
  fi

  # Re-set the global variable, allowing each method call to be insulated
  unset ROOM_TEMP

  # DNS name of the CDU
  local TEMP_HOST="$1"

  # Query the temperature sensor 
  ROOM_TEMP=`snmpget -v1 -c public $TEMP_HOST enterprises.17373.3.4.1.6.1 | awk -F 'INTEGER: ' '{print $2}' | grep -o '[0-9]*'`

  return 0;
}

#######################################
# check the ups power status to see if it's on bypass
#    @param - dns name of the ups
check_ups_on_bypass(){

  if [ $# -ne 2 ] ; then
    echo "$0 requires 2 strings (dnsName, community)"
    return 1;
  fi

  # Re-set the global variable, allowing each method call to be insulated
  unset ON_BYPASS

  # DNS name of the CDU
  local UPS_DNS_NAME="$1"
  local UPS_COMMUNITY_NAME="$2"

  # Query the temperature sensor for the value of 'Output To Load On Bypass'
  # (True = 1, False=2)
  BYPASS_POLL=`snmpget -v2c -On -c $UPS_COMMUNITY_NAME $UPS_DNS_NAME  enterprises.476.1.42.3.5.3.10.0 | awk '{print $4}'|grep -o '[0-9]*'`

  #TODO check the $? before echoing
  ON_BYPASS=$BYPASS_POLL
  echo $ON_BYPASS

  return 0;
}

#######################################
getMaxTemp_upsRoom() {
  if [ $# -ne 2 ] ; then
    echo "$0 requires 2 strings (tempHost, community)"
    return 1;
  fi

  local _tempHost="$1"
  local _community="$2"
  local oid

  local htemp=0
  for oid in $UPS_ROOM_SENSOROIDS
  do
    local temp=`snmpget -v 1 -c $_community $_tempHost $oid \
                 | awk -F 'INTEGER: ' '{print $2}' \
                 | grep -o '[0-9]*'`
  
    if [ $? -gt 0 ]; then
      echo "Problem fetching temp" | mail -s "Problem fetching temp" $SCRIPTADMIN
      logger "System Problem fetching temp"
      temp=0
      continue
    elif [ $temp -gt $htemp ]; then
      htemp=$temp
    fi
  done
  echo $htemp
  return 0
}

#######################################
# report the highest temperature in the datacenter
# currently, only checks the OIDs that have been set in the config file
#    @param - dns name of the temp sensor, snmp community string
getMaxTemp_nhdc() {
  if [ $# -ne 2 ] ; then
    echo "$0 requires 2 strings (tempHost, community)"
    return 1;
  fi

  local _tempHost="$1"
  local _community="$2"
  local oid

  local htemp=0
  for oid in $NHDC_SENSOROIDS
  do
    local temp=`snmpget -v 1 -c $_community $_tempHost $oid \
                 | awk -F 'INTEGER: ' '{print $2}' \
                 | grep -o '[0-9]*'`
  
    if [ $? -gt 0 ]; then
      echo "Problem fetching temp" | mail -s "Problem fetching temp" $SCRIPTADMIN
      logger "System Problem fetching temp"
      temp=0
      continue
    elif [ $temp -gt $htemp ]; then
      htemp=$temp
    fi
  done
  echo $htemp
  return 0
}

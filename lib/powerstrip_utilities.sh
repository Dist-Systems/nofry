#!/bin/bash

#######################################
# create the database and tables
create_db(){
  if [ $# -eq 0 ] ; then
    echo "$0 requires a string (db name)"
    return 1;
  fi

  # echo "$# args passed to create_db()"

  local db=$1;
  $(sqlite3 $db "CREATE TABLE strips (
                                   'id' INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL UNIQUE, 
                                   'object_id' VARCHAR NOT NULL, 
                                   'dns_name' VARCHAR NOT NULL, 
                                   'ip' VARCHAR NOT NULL UNIQUE, 
                                   'type' INTEGER 
                                 )");
  $(sqlite3 $db "CREATE TABLE outlets (
				    'id' INTEGER PRIMARY KEY  NOT NULL  UNIQUE , 
                                    'strip' INTEGER NOT NULL , 
                                    'bank' INTEGER NOT NULL , 
                                    'outlet' INTEGER NOT NULL ,  
                                    'criticality' CHAR NOT NULL 
                                  )");
  $(sqlite3 $db "CREATE VIEW outlet_info AS 
                    SELECT object_id AS oid,
                           dns_name AS name,
                           ip,type,bank,outlet,criticality 
                    FROM strips strip 
                    LEFT JOIN outlets outlet 
                    ON outlet.strip = strip.id;");
  return 0;
}
 
#######################################
# report_crit_role
# $NAME -> dns name of the outlet
#  - this method takes a DNS name and returns the 'criticality' of that outlet
report_crit_role(){

    local arg_count=$#

    # Was the method called with the correct argument count?
    if [ "$arg_count" -ne "1" ]; then 
      # No, quit here
      echo "report_crit_role() needs requires a the name of an outlet, nothing more (or less)"
      return 1
    fi

    local dns_name="$1"
    local prefix=${dns_name:0:2}

    if [ "$prefix" = "C1" ];then
        CRIT_ROLE="C1"
    elif [ "$prefix" = "C2" ];then
        CRIT_ROLE="C2"
    elif [ "$prefix" = "NC" ]; then
        CRIT_ROLE="NC"
    else
        CRIT_ROLE="UN"
    fi
}

#######################################
# loop_over_one_bank
# $STRIP_LIST -> store argument passed to the script
#  - the name of STRIP_LIST must start with 2 digits
#    those 2 digits are used as the outlet count
#    one bank is assumed
loop_over_one_bank(){
    # $strip_3bank_list -> store argument passed to the script
    local strip_list="$1"; 
    if [ -s $strip_list ];then 

	# echo "loop_over_one_bank() got $STRIP_LIST"
	local db="$2"
	
	# Is the argument a valid file?
	if [ ! -f "$strip_list" ]; then 
	  # No, quit here
	  return 1
	fi
	
	local list=$(basename "$strip_list")
	local outlet_count=${list:0:2}
	local bank=1
	
	# Count the number of lines in the file
	numstrips=$(wc -l $strip_list | awk '{ print $1 }')

	# Does this file contain entries?
	if [ $numstrips -gt 0 ]; then
	  local pdus=$(cat ${strip_list})
	  for pdu in $pdus; do
	    ping -q -c 1 $pdu > /dev/null 2>&1
	    if [ $? -eq 0 ]; then
	      local stripid=$(add_strip $pdu $db)
       	
	      # distinquish [C1,C2,NC] for each outlet on pdu
	      for outlet in $(seq $outlet_count); do
	        # echo "----> outlet: $outlet"
	        value=$(snmpget -v 2c -c $GETCOMMUNITY $pdu $OID.$bank.$outlet | awk '{print $4}' | sed 's/\"//g')
	        # echo "snmpget -v 2c -c $GETCOMMUNITY $pdu $OID.$bank.$outlet"
	
	        # Decide what to do with the outlet based on the name
	        report_crit_role $value 
	        # report_crit_role sets the $CRIT_ROLE variable #TODO don't use globals
	        local outlet_id=$(add_outlet $stripid $OID $bank $outlet $CRIT_ROLE $db)
	      done
	    else
	      echo "$pdu not reachable"
	    fi
	  done
	fi
        return 0
    else # the file either doesn't exist or is empty
        return 1
    fi
}

#######################################
# loop_over_three_bank function
# $strip_3bank_list -> store argument passed to the script
#  - the name of strip_3bank_list has no restrictions
#    3 banks of 8 outlets are assumed
loop_over_three_bank(){
    # $strip_3bank_list -> store argument passed to the script
    local strip_3bank_list="$1"
    local db="$2"
    # Is the first argument a valid file?
    if [ ! -f "$strip_3bank_list" ]; then 
      # No, quit here
      return 1
    fi
    # Count the number of lines in the file
    numstrips=$(wc -l $strip_3bank_list | awk '{ print $1 }')

    # Does this file contain entries?
    if [ $numstrips -gt 0 ]; then
      for pdu in $(cat $strip_3bank_list); do
        ping -q -c 1 $pdu > /dev/null 2>&1
        if [ $? -eq 0 ]; then

          local stripid=$(add_strip $pdu $db)
  
          # distinquish [C1,C2,NC] for each outlet on strip
          for bank in $(seq 3); do
            for outlet in $(seq 8); do
              # echo "----> bank/outlet: $bank/$outlet"
              value=$(snmpget -v 2c -c $GETCOMMUNITY $pdu $OID.$bank.$outlet | awk '{print $4}' | sed 's/\"//g')
              # Decide what to do with the outlet based on the name
              report_crit_role $value 
              # report_crit_role sets the $crit_role variable #TODO don't use globals
              local outlet_id=$(add_outlet $stripid $OID $bank $outlet $CRIT_ROLE $db)
            done 
          done 
        else
          echo "$pdu not reachable"
        fi 
      done
    fi
}

#######################################
add_outlet(){
    local stripid="$1"
    local my_oid="$2"
    local bank="$3"
    local outlet="$4"
    local gravity="$5"
    local db="$6"
    local arg_count=$#

    # Was the method called with the correct argument count?
    if [ "$arg_count" -ne "6" ]; then 
      # No, quit here
      return 1
    fi

    #echo " - add_outlet($stripid,$bank,$outlet,$gravity)"
    local outletid=$(sqlite3 $db "INSERT INTO outlets (strip,bank,outlet,criticality) 
			       VALUES ($stripid, $bank, $outlet,'$gravity');
                               SELECT last_insert_rowid() from outlets LIMIT 1")
    local status=$?
    echo $outletid
    return $status
}

#######################################
add_strip(){
    local dns="$1"
    local db="$2"
    local ip=$(host -t a $pdu|awk '{print $4}') 
    local name=$(snmpget -v 2c -c public $pdu SNMPv2-MIB::sysDescr.0|awk '{print $4 $5 $6}')
    local arg_count=$#

    # Was the method called with the correct argument count?
    if [ "$arg_count" -ne "2" ]; then 
      # No, quit here
      return 1
    fi

    #echo "add_strip('$OID','$DNS','$IP','$TYPE');"
    local stripid=$(sqlite3 $db "INSERT INTO strips (object_id,dns_name,ip,type) 
			  VALUES ('$OID','$dns','$ip','$name');
			  SELECT last_insert_rowid() from strips LIMIT 1;")
    local status=$?
    echo $stripid
    return $status
}

#######################################
cut_power(){
    # @params [url,outlet_number,bank]

    local arg_count=$#

    # Was the method called with the correct argument count?
    if [ "$arg_count" -ne "3" ]; then 
      # No, quit here
      return 1
    fi

    local _dns="$1"
    local _num="$2"
    local _bank="$3"
    #return $(snmpset -v 2c -c endor ${_dns} .1.3.6.1.4.1.1718.3.2.3.1.11.1.1.${_num} i 2)
    local output= $(snmpset -v 2c -c endor ${_dns} .1.3.6.1.4.1.1718.3.2.3.1.11.1.${_bank}.${_num} i 2 > /dev/null 2>&1)
    return $?
}


#######################################
power_on(){
    # @params [url, outlet_number, bank]

    local arg_count=$#

    # Was the method called with the correct argument count?
    if [ "$arg_count" -ne "3" ]; then 
      # No, quit here
      return 1
    fi

    local _dns="$1"
    local _num="$2"
    local _bank="$3"
    #return $(snmpset -v 2c -c endor ${_dns} .1.3.6.1.4.1.1718.3.2.3.1.11.1.1.${_num} i 1)
    local output= $(snmpset -v 2c -c endor ${_dns} .1.3.6.1.4.1.1718.3.2.3.1.11.1.${_bank}.${_num} i 1 > /dev/null 2>&1)
    return $?
}
#######################################

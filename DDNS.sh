#!/bin/bash

source Tencent.sh

ETH0="Network Interface"
RecordList=("Domain.1" "Domain.2")
RemoveList=("Remove.Domain")

LOG_TARGET="Tencet DDNS IPV6"

ip addr 2>/dev/null 1>&2
if [ $? -ne 0 ]; then logger -t "$LOG_TARGET" -p user.error "need ip tool, please install it"; exit 1; fi

ICMP() {
	host=$1
	rate=$(ping -6 -w 6  -c 3 -I $host www.baidu.com | grep "packet loss" | awk '{ print $6 }')
	rate=${rate:0:-1}

	logger -t "$LOG_TARGET" -p user.debug "host: $host, rate: $rate"
	if [ "$rate" == "" -o $rate -eq 100 ]; then
		return 1
	else
		return 0
	fi
}

GetIPV6() {
	IPV6List=$(ip addr show dev "$1" | grep "inet6" | awk '{ print $2 }' | awk -F'/' '{ print $1 }' | grep -v "^fe80")
	total=$(echo "$IPV6List" | wc -l)
	logger -t "$LOG_TARGET" -p user.debug "ipv6: "$IPV6List" total: $total"
	if [ $total -lt 2 ]; then
		echo "$IPV6List"
		return 0
	fi

	for ipv6 in $IPV6List; do
		ICMP $ipv6
		if [ $? -eq 0 ]; then
			echo "$ipv6"
			return 0
		fi
	done

	return 1
}

for Record in "${RemoveList[@]}"; do
	RecordInformation=$(CheckRecord "" "$Record")
	if [ $? -eq 1 ]; then
		DeleteRecord $RecordInformation "$Record"
	fi
done

RecordIPV6=$(GetRecordValue "${RecordList[0]}")
if [ $? -eq 0 ]; then
	for ((index=1; index<${#RecordList[@]}; index++)); do
		IP=$(GetRecordValue "${RecordList[$index]}")
		if [ "$IP" != "$RecordIPV6" ]; then
			RecordIPV6="$IP"
			break;
		fi
	done
fi

while true; do
	IPV6=$(GetIPV6 "$ETH0")

	logger -t "$LOG_TARGET" -p user.debug "IPV6:$IPV6 RecordIPV6:$RecordIPV6"

	if [ "$IPV6" == "$RecordIPV6" -o "$IPV6" == "" ]; then
		if [ "$IPV6" == "" ]; then
			sleep 120
		else
			sleep 300
		fi
		continue;
	fi

	for Record in "${RecordList[@]}"; do
		logger -t "$LOG_TARGET" -p user.debug "Record:$Record"
		RecordInformation=$(CheckRecord "$IPV6" "$Record")
		Ret=$?
		logger -t "$LOG_TARGET" -p user.debug "RecordInformation:$RecordInformation Ret:$Ret"
		if [ $Ret -eq 1 ]; then
			logger -t "$LOG_TARGET" -p user.debug "change record"
			ChangeRecord "$IPV6" "$Record" $RecordInformation
			if [ $? -ne 0 ]; then
				logger -t "$LOG_TARGET" -p user.error "Changle Record failed. IP:$IPV6 Record:$Record"
			fi
		elif [ $Ret -eq 2 ]; then
			logger -t "$LOG_TARGET" -p user.debug "add record"
			AddRecord "$IPV6" "$Record"
			if [ $? -ne 0 ]; then
				logger -t "$LOG_TARGET" -p user.error "Add new Record filead. IP:$IPV6 Record:$Record"
			fi
		fi
	done

	RecordIPV6=$IPV6

	if [ "$IPV6" == "" ]; then
		sleep 120
	else
		sleep 300
	fi
done

#!/bin/bash

source Tencent.sh

ETH0="Network Interface"
RecordList=("Domain.1" "Domain.2")
RemoveList=("Remove.Domain")

export LOG_TARGET="Tencet DDNS IPV6"

ip addr 2>/dev/null 1>&2
if [ $? -ne 0 ]; then logger -t "$LOG_TARGET" -p user.error "need ip tool, please install it"; exit 1; fi

GetIPV6() {
	echo "$(ip addr show dev "$1" | grep inet6 | awk '{ print $2 }' | awk -F'/' '{ print $1 }')"
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
		sleep 300
		continue;
	fi

	for Record in "${RecordList[@]}"; do
		logger -t "$LOG_TARGET" -p user.debug echo "Record:$Record"
		RecordInformation=$(CheckRecord "$IPV6" "$Record")
		Ret=$?
		logger -t "$LOG_TARGET" -p user.debug "RecordInformation:$RecordInformation"
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

	sleep 300
done

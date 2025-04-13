host="dnspod.tencentcloudapi.com"
action=""
rigion=""
timestamp=""
version=""

LOG_TARGET="Tencet DDNS IPV6"

secret_id="Tencent Secret ID, You Can Set it to ENV"
secret_key="Tencent Secret KEY, You Can Set it to ENV"

curl -h 2>/dev/null 1>&2 && openssl -h 2>/dev/null 1>&2 && jq -h 2>/dev/null 1>&2
if [ $? -ne 0 ]; then logger -t "$LOG_TARGET" -p user.error "need install curl & openssl & jq"; exit 1; fi

Authorization() {
	local payload="$1"
	local algorithm="TC3-HMAC-SHA256"
	local service="dnspod"
	local date=$(date -u -d @$timestamp +"%Y-%m-%d")
	local http_request_method="POST"
	local canonical_uri="/"
	local canonical_querystring=""
	local canonical_headers="content-type:application/json; charset=utf-8\nhost:$host\nx-tc-action:$(echo $action | awk '{print tolower($0)}')\n"
	local signed_headers="content-type;host;x-tc-action"
	local hashed_request_payload=$(echo -n "$payload" | openssl sha256 -hex 2>/dev/null | awk '{print $2}')
	local canonical_request="$http_request_method\n$canonical_uri\n$canonical_querystring\n$canonical_headers\n$signed_headers\n$hashed_request_payload"
	local hashed_canonical_request=$(printf "$canonical_request" | openssl sha256 -hex 2>/dev/null | awk '{print $2}')
	local credential_scope="$date/$service/tc3_request"
	local string_to_sign="$algorithm\n$timestamp\n$credential_scope\n$hashed_canonical_request"

	secret_date=$(printf "$date" | openssl sha256 -hmac "TC3$secret_key" | awk '{print $2}')
	#echo $secret_date
	secret_service=$(printf $service | openssl dgst -sha256 -mac hmac -macopt hexkey:"$secret_date" | awk '{print $2}')
	#echo $secret_service
	secret_signing=$(printf "tc3_request" | openssl dgst -sha256 -mac hmac -macopt hexkey:"$secret_service" | awk '{print $2}')
	#echo $secret_signing
	signature=$(printf "$string_to_sign" | openssl dgst -sha256 -mac hmac -macopt hexkey:"$secret_signing" | awk '{print $2}')
	#echo "$signature"

	authorization="$algorithm Credential=$secret_id/$credential_scope, SignedHeaders=$signed_headers, Signature=$signature"

	echo "$authorization"
}

Post() {
	local payload="$1"
	#echo "https://$host" -d "$payload" -H "Authorization: $authorization" -H "Content-Type: application/json; charset=utf-8" -H "Host: $host" -H "X-TC-Action: $action" -H "X-TC-Timestamp: $timestamp" -H "X-TC-Version: $version" $region
	curl -XPOST "https://$host" -d "$payload" -H "Authorization: $authorization" -H "Content-Type: application/json; charset=utf-8" -H "Host: $host" -H "X-TC-Action: $action" -H "X-TC-Timestamp: $timestamp" -H "X-TC-Version: $version" -H "X-TC-Region: $region" 2>/dev/null
}

GetSubDomain() {
	SubDomain=""
	SubLevel=$(echo "$1" | grep -o '\.' 2>/dev/null | wc -l)
	if [ $SubLevel -gt 1 ]; then
		SubDomain=$(echo ${1%.*})
		SubDomain=$(echo ${SubDomain%.*})
	fi

	echo "$SubDomain"
}

GetTopDomain() {
	echo $1 | awk -F'.' '{ printf("%s.%s", $(NF-1), $(NF)) }'
}

CheckRecord() {
	timestamp=$(date +%s)
	action="DescribeRecordList"
	version="2021-03-23"
	SubDomain=$(GetSubDomain $2)
	echo "SubDomain: $SubDomain" 1>&2
	if [ "$SubDomain" != "" ]; then
		SubDomain=", \"Subdomain\": \"$SubDomain\""
	fi
	TopDomain=$(GetTopDomain $2)

	payload=$(echo "{\"Domain\": \"$TopDomain\", \"RecordType\": \"AAAA\"$SubDomain}" | iconv -t utf-8)

	logger -t "$LOG_TARGET" -p user.debug "$payload"

	authorization=$(Authorization "$payload")

	result=$(Post "$payload")

	logger -t "$LOG_TARGET" -p user.debug $result

	echo $result | grep '\"Error\":' 2>/dev/null 1>&2
	if [ $? -eq 0 ]; then
		return 2

	fi

	RecordIP=$(echo "$result" | jq '.Response.RecordList[0].Value')
	logger -t "$LOG_TARGET" -p user.debug "ip=$RecordIP ip=$1"
	if [ "$1" == "" -o "$RecordIP" != "\"$1\"" ]; then
		RecordID=$(echo "$result" | jq '.Response.RecordList[0].RecordId')
		RecordLine=$(echo "$result" | jq '.Response.RecordList[0].Line')
		echo -n "$RecordID $RecordLine"
		return 1
	else
		return 0
	fi
}

ChangeRecord() {
	timestamp=$(date +%s)
	action="ModifyRecord"
	version="2021-03-23"
	SubDomain=$(GetSubDomain $2)
	#echo "SubDomain: $SubDomain" 1>&2
	if [ "$SubDomain" != "" ]; then
		SubDomain=", \"SubDomain\": \"$SubDomain\""
	fi

	TopDomain=$(GetTopDomain $2)

	payload=$(echo "{\"Domain\": \"$TopDomain\", \"RecordType\":\"AAAA\", \"RecordLine\": $4, \"Value\": \"$1\", \"RecordId\": $3 $SubDomain }" | iconv -t utf-8)

	logger -t "$LOG_TARGET" -p user.debug "$payload"

	authorization=$(Authorization "$payload")

	result=$(Post "$payload")

	logger -t "$LOG_TARGET" -p user.debug $result

	echo $result | grep '\"Error\":' 2>/dev/null 1>&2
	if [ $? -eq 0 ]; then
		return 2
	fi

	return 0
}

AddRecord() {
	timestamp=$(date +%s)
	action="CreateRecord"
	version="2021-03-23"
	SubDomain=$(GetSubDomain $2)
	#echo "SubDomain: $SubDomain" 1>&2
	if [ "$SubDomain" != "" ]; then
		SubDomain=", \"SubDomain\": \"$SubDomain\""
	fi
	TopDomain=$(GetTopDomain $2)

	payload=$(echo "{\"Domain\": \"$TopDomain\", \"Value\":\"$1\", \"RecordType\": \"AAAA\", \"RecordLine\": \"默认\" $SubDomain}" | iconv -t utf-8)

	logger -t "$LOG_TARGET" -p user.debug "$payload"

	authorization=$(Authorization "$payload")

	echo $authorization 1>&2

	result=$(Post "$payload")

	logger -t "$LOG_TARGET" -p user.debug $result

	echo $result | grep '\"Error\":' 2>/dev/null 1>&2
	if [ $? -eq 0 ]; then
		return 2
	else
		return 0
	fi
}

DeleteRecord() {
	timestamp=$(date +%s)
	action="DeleteRecord"
	version="2021-03-23"
	SubDomain=$(GetSubDomain $3)
	#echo "SubDomain: $SubDomain" 1>&2
	if [ "$SubDomain" != "" ]; then
		SubDomain=", \"SubDomain\": \"$SubDomain\""
	fi
	TopDomain=$(GetTopDomain $3)

	payload=$(echo "{\"Domain\": \"$TopDomain\", \"RecordId\": $1}" | iconv -t utf-8)

	logger -t "$LOG_TARGET" -p user.debug "$payload"

	authorization=$(Authorization "$payload")

	result=$(Post "$payload")

	logger -t "$LOG_TARGET" -p user.debug $result

	echo $result | grep '\"Error\":' 2>/dev/null 1>&2
	if [ $? -eq 0 ]; then
		return 2
	else
		return 0
	fi

}

GetRecordValue() {
	timestamp=$(date +%s)
	action="DescribeRecordList"
	version="2021-03-23"
	SubDomain=$(GetSubDomain $1)
	#echo "SubDomain: $SubDomain" 1>&2
	if [ "$SubDomain" != "" ]; then
		SubDomain=", \"Subdomain\": \"$SubDomain\""
	fi
	TopDomain=$(GetTopDomain $1)

	payload=$(echo "{\"Domain\": \"$TopDomain\", \"RecordType\": \"AAAA\" $SubDomain}" | iconv -t utf-8)

	logger -t "$LOG_TARGET" -p user.debug "$payload"

	authorization=$(Authorization "$payload")

	result=$(Post "$payload")

	logger -t "$LOG_TARGET" -p user.debug $result

	echo $result | grep '\"Error\":' 2>/dev/null 1>&2
	if [ $? -eq 0 ]; then
		return 2
	fi

	RecordIP=$(echo "$result" | jq '.Response.RecordList[0].Value')
	if [ "$RecordIP" != "" ]; then
		echo -n ${RecordIP:1:-1}
		return 0
	else
		return 1
	fi
}

# TEST CASE
#info=$(CheckRecord "" "Test.Domain.1")
#echo $info
#GetRecordValue "Test.Domain.1"
#AddRecord "fe80::2f2d:198d:6f58:dae3" "Test.Domain.1"

#IPV6="fe80::2f2d:198d:6f58:daee"
#Record="Test.Domain.1"
#RecordInformation=$(CheckRecord "" "$Record")
#if [ $? -eq 1 ]; then
#	flags=$(DeleteRecord $RecordInformation "$Record")
#fi
#exit 0

#IPV6="fe80::2f2d:198d:6f58:daee"
#Record="Test.Domain.1"
#RecordInformation=$(CheckRecord "$IPV6" "$Record")
#if [ $? -eq 1 ]; then
#	echo "Record information:$RecordInformation"
#	ChangeRecord "$IPV6" "$Record" $RecordInformation
#	if [ $? -ne 0 ]; then
#		echo "Changle Record failed. IP:$IPV6 Record:$Record"
#	fi
#elif [ $? -eq 2 ]; then
#	AddRecord "$IPV6" "$Record"
#	if [ $? -ne 0 ]; then
#		echo "Add new Record filead. IP:$IPV6 Record:$Record"
#	fi
#fi

# Tencent Sample:
#https://github.com/TencentCloud/signature-process-demo/blob/main/signature-v3/bash/signv3.sh

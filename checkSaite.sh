#!/usr/bin/env bash
# канал куда падают сообщения https://t.me/checkSiteStatusTMP
lockfile="/var/lock/checkSiteStatus.lock"

function loc {
    (set -o noclobber; echo "$$" >"$lockfile") 2> /dev/null
}

if ! loc; then
    if [ -f $lockfile ] && ! [ -d /proc/$(cat $lockfile) ];then
        rm -f $lockfile
        loc
    else
        echo "попытка повторного запуска"
        exit
    fi
fi

url='minobrnauki.gov.ru ya.ru 192.168.152.155'
pathHtml='./'
interval='5'
status=''

cat <<EOF > $pathHtml/index.html
<!doctype html>
<html lang="ru">
  <head>
    <meta charset="utf-8">
    <title>status</title>
  </head>
  <body>
  <status>
  </status>
  </body>
</html>
EOF


function checkSiteStatus() {  
	bytes=$(wget -T 8 -t 1  -O - -o /dev/null http://$1 |wc -c)
	code=$(curl --max-redirs 10 -L -s -o /dev/null -w "%{http_code}" http://$1)
	
	if [ "$bytes" -lt "1" ] || [ "$code" -ne "200" ]; then
	   return 1
	fi
	return 0
}

function addHtml() {
	sed -i "/<status>/a $1 $2<br>" $pathHtml/index.html
}

function upHtml() {
	sed -i "s/$1.\+/$1 $2<br>/g"  $pathHtml/index.html
}

function sendTelegram() {
	TOKEN='5411481618:AAG-t37ipSpgqYOQDLZ4vCYNW38vS_ld64w'
	CHAT_ID='-1001482387449'
	MESSAGE="$1"
	URL="https://api.telegram.org/bot$TOKEN/sendMessage"
	curl -o /dev/null -s -X POST $URL -d chat_id=$CHAT_ID -d text="$MESSAGE" -d parse_mode=html
}

while [ 1 ]; do
n=0
	for i in $url ; do
		NewStatus=$(checkSiteStatus $i && echo ok || echo no)
		if [ "${status[$n]}" != $NewStatus ]; then
			
			if [ "${status[$n]}" == "" ]; then
				addHtml $i $NewStatus
			fi

			if [ "$NewStatus" == "no" ]; then
				sendTelegram "$i $NewStatus"
			fi
				upHtml $i $NewStatus 
		fi

	status[$n]=$NewStatus
	n=$(($n+1))
	done
	sleep $interval
done

#!/usr/bin/env bash

scriptName=$(basename '/root/bkpDC.sh' | awk -F '.' '{print $1}')
workFile=list.disk
dlist=download.list
lockfile=/var/lock/$scriptName.lock                                 # Файл блокировки, на дает запустить дубль.
logfile=/var/log/$scriptName.log                        # логи

function loc {
    (set -o noclobber; echo "$$" >"$lockfile") 2> /dev/null
}

function mes { #Для отправки уведомлений в телегу
    TOKEN=71***22:AAGwRJ*****BdBpLYbw
    CHAT_ID=81***655
    MESSAGE="$(hostname) $*"
    URL="https://api.telegram.org/bot$TOKEN/sendMessage"
    #curl --socks5 185.***.208.169:12269 --proxy-user login:nsdfq1 -s -X POST $URL -d chat_id=$CHAT_ID -d text="$MESSAGE" -d parse_mode=html >/dev/null &
    curl -s -X POST $URL -d chat_id=$CHAT_ID -d text="$MESSAGE" -d parse_mode=html >/dev/null &
    return 0
}

function log {
        [ "$*" == "" ] && return 1
    #echo -e "$(date +"%Y-%m-%d_%H-%M-%S") $1"
    echo -e "$(date +"%Y-%m-%d_%H-%M-%S") $*" >>$logfile
    [ "$2" == "1" ] && mes "$(date +"%Y-%m-%d_%H-%M-%S") $1"
    return 0
}

log "start"
ping -c 4 172.17.1.2 > /dev/null  || ( log "172.17.1.2 no conntect" 1 && exit )

function download {
    name=$i
    timestamp="$(date +"%Y-%m-%d_%H-%M-%S")"
    id=$(echo -e "$row" |awk -F '|' '{print $2}' | sed 's/ //g')
    sed -i "/${name}/d" $workFile
    echo $timestamp $i >> $dlist
    d1=$(date +%s)
    #wget -o /dev/null -O - "https://api.ru-7.selvpc.ru/image-download/v2/${id}?token=${token}" | pigz -9 -p 3 |  pv -q -L 1875000 | ssh bkp@172.17.1.2 "dd of=/bkp/vm-backup-DC/${name}_${timestamp}.raw.gz" \
    openstack image save "$id" | pigz -9 -p 4 |  pv -q -L 1625000 | ssh bkp@172.17.1.2 "dd of=/bkp/vm-backup-DC/${name}_${timestamp}.raw.gz" \
	&& [ "$(($(date +%s)-$d1))" -gt 60 ] \
        || ( log "error ${id} $name" 1 ) 
    openstack image delete $id 
    sed -i "/${name}/d" $dlist
    log "finish ${id} $name"
}

function faketty {
    script -qefc "$(printf "%q " "$@")"
}


if ! loc; then
    if [ -f $lockfile ] && ! [ -d /proc/$(cat $lockfile) ];then
        rm -f $lockfile && log 'процесс не найден удаляем блокировку'
        log "предыдущий $scriptName завершился не удачно" 1
        loc
    else
        log "попытка повторного запуска" 1
        exit
    fi
fi

source rc.sh
token=$(openstack token issue -c id | grep id | awk -F '|' '{print $3}' |sed 's/ //g')
log "token $token"
echo -e "$(openstack volume list 2>/dev/null |awk '{print $4}'|grep disk)" > $workFile
sed -i '/^$/d' $workFile

[ "$(wc -l $workFile | awk '{print $1}')" -lt "1" ] && exit

for i in $(cat $workFile)
do
	log "$(faketty openstack image create --volume "$i" "$i" --force)"  # Асинхронно
done

sleep 1500 #  Ждем 25 минут потом начинаем проверять образы.

rm $dlist && touch $dlist # чистим download list

while [ true ];
do
    sed -i '/^$/d' $workFile $dlist
    [ "$(wc -l $workFile | awk '{print $1}')" -lt "1" ] && [ "$(wc -l $dlist | awk '{print $1}')" -lt "1" ] && break
    for i in $(cat $workFile)
    do
        [ $(cat $dlist | wc -l) -ge 2 ] && break # выходим, Если грузится больше 3 образов

        [ "$(grep -c $i $dlist)" -gt "0" ] && continue # отменяем итерацию если образ уже грузится

        row=$(openstack image list 2>/dev/null |grep $i )
        [ "$row" == "" ] && sed -i "/${i}/d" $workFile
        status=$(echo -e "$row" |awk -F '|' '{print $4}' | sed 's/ //g')
        [ "$status" != "active" ] && continue
        log "$row"
        download &
    done
    sleep 120
done

rm -f $lockfile
exit 0



#image save <id image> | dd of
#openstack volume list 2>/dev/null |awk '{print $4}'|grep disk
#image create --volume disk-for-vm2CORE-#1 disk-for-vm2CORE-#1 --force # Асинхронно

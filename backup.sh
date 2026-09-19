#!/usr/bin/env bash
timestamp=$(date "+%Y-%m-%d-%H-%M"); dir=''
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

scriptName=backup.sh                                                # Название скрипта
lockfile=/var/lock/$scriptName.lock                                 # Файл блокировки, на дает запустить дубль.
logfile=/var/log/$(basename $scriptName .sh).log                	# логи
dir="/bkp"										# work catalog
incFiles="/root/bkp/incFiles"										# incremental catalog
vmBackup="$dir/backupVM"											# office vm
backupFS="/etc /root /home /lib/systemd/system/keepalived.service" 				# backup dirs
compres=' pigz -9 -p 2 '
typeComress='gz '
exclude='--exclude=/etc/selinux --exclude=/root/bkp'

function mes { #Для отправки уведомлений в телегу
    TOKEN=715---622:AAGwRJInRVmwl**5*3RTY6OBdBpLYbw
    CHAT_ID=81***55
    MESSAGE="$(hostname) $*"
    URL="https://api.telegram.org/bot$TOKEN/sendMessage"
    curl --socks5 172.17.11.13:9898 -s -X POST $URL -d chat_id=$CHAT_ID -d text="$MESSAGE" -d parse_mode=html >/dev/null &
    return 0
}

function log {
	[ "$*" == "" ] && return 1
    #echo -e "$(date +"%Y-%m-%d_%H-%M-%S") $1"
    echo -e "$(date +"%Y-%m-%d_%H-%M-%S") $*" >>$logfile
    [ "$2" == "1" ] && mes "$(date +"%Y-%m-%d_%H-%M-%S") $1"
    return 0
}

function loc {
    (set -o noclobber; echo "$$" >"$lockfile") 2> /dev/null
}

if ! loc; then
    if [ -f $lockfile ] && ! [ -d /proc/$(cat $lockfile) ];then
        rm -f $lockfile && log 'процесс не найден удаляем блокировку'
        log "предыдущий $scriptName завершился не удачно" 1
        loc
    else
        log "попытка повторного запуска"
        exit
    fi
fi

function elections {
	mkdir -p $dir/hosting.nic.ru
	log "backup elections.nichost.ru"
	timestamp=$(date "+%Y-%m-%d-%H-%M");
	ssh elections@ssh.elections.nichost.ru "mysqldump -uelections_mysql -pcytB+Kg4 elections_pobeda " | $compres > $dir/hosting.nic.ru/elections.nichost.ru.${timestamp}_mysqldump.sql.$typeComress
	ssh elections@ssh.elections.nichost.ru "tar -cf - * " | $compres > $dir/hosting.nic.ru/elections.nichost.ru.${timestamp}_bkp.tar.$typeComress
	
	# test 	
	ssh elections@ssh.elections.nichost.ru "ls -1"
	[ "$?" -gt "0" ] && log "Проблемы с бекапом elections" '1'
}

function bkp {
	mkdir -p /mnt/share /mnt/1C
	mount.cifs //172.17.1.4/1C /mnt/1C -o user=bkp,password=PUBrrvpcDB
	if [ 0 != $(mount |grep -c '/mnt/1C') ];then
			log "mount /mnt/1C" 
			backupFS="$backupFS /mnt/1C"
	fi

	mount.cifs //172.17.1.4/share /mnt/share -o user=bkp,password=PUBrrvpcDB
	if [ 0 != $(mount |grep -c '/mnt/share') ];then
			log "mount /mnt/share" 
			backupFS="$backupFS /mnt/share"
			wget -o /dev/null -O /mnt/share/cardBackup/facedb.bkp 'http://admin:F-5****A@172.17.1.101/cgi-bin/facedb_cgi?action=export'
			facedb=$?	
			[ "$facedb" != "0" ] && log "backup domofon error. wget code error: $erCard" '1'
			wget -o /dev/null -O /mnt/share/cardBackup/sysRestoreCfgEx.bkp 'http://admin:F-5***A@172.17.1.101/webs/sysRestoreCfgEx'
			#wget -o /dev/null -O /mnt/share/cardBackup/default_user_config.txt 'http://admin:admin@172.17.1.101/default_user_config.txt' 		#FANVILL i64
			#wget -o /dev/null -O /mnt/share/cardBackup/passwordList.csv 'http://admin:admin@172.17.1.101/cgi-bin/egsData?type=password&mode=csv'	#FANVILL i64
	fi

	for i in $backupFS
	do
		! [ -d $i ] && continue
		timestamp=$(date "+%Y-%m-%d-%H-%M");
		name=$(hostname)_${timestamp}_.$(echo "$i" | sed -e 's/\//-/g' -e 's/_/-/g' )
		mkdir -p $dir/$incremental
		log "$i -> $dir/$incremental/$name.tar.$typeComress"
		log $(tar -cf - $i $exclude --ignore-failed-read --listed-incremental=$incFiles/$incremental/incremental.$(echo $i |sed -e 's/\//-/g' -e 's/^-//g') 2>/dev/null|$compres > $dir/$incremental/$name.tar.$typeComress 2>&1)
		log "$i is done"

	done
}

! [ -f "/usr/bin/pigz" ] && echo install \'pigz\' && log 'pigz не устанлвлен, испольузется bzip2' && compres=' bzip2 -9 ' && typeComress='bz2 '
! [ -f "/usr/bin/bzip2" ] && ! [ -f "/usr/bin/pigz" ] && echo install \'bzip2\' && exit 1

[ "$dir" == "" ] && log 'не указан рабочий католог' 1 && exit 1
mkdir -p $incFiles/day $incFiles/wk $incFiles/month

#если первый день месяца или нет полного архива
if [ 01 == $(date +%d) ] || [ ! "$(ls -A $incFiles/month 2>/dev/null)" ]; then
	[ 01 == $(date +%d) ] && log "первый день месяца"
	[ ! $(ls -A $incFiles/month 2>/dev/null) ] && log "первый backup"
	log $(rm -vrf $incFiles/month/incremental* 2>&1)
	incremental=month
	bkp
	log $(/bin/cp -v $incFiles/month/incremental* $incFiles/day 2>&1)
	log $(/bin/cp -v $incFiles/month/incremental* $incFiles/wk 2>&1)
elif [ 1 == $(date +%u) ]; then #если первый день недели
	log "первый день недели"
	incremental=wk
	
	# bkp резервного диспетчерского роутера	
	ping -w 1 172.17.1.7 > /dev/null && ssh root@172.17.1.7 tar -c /etc | $compres > $dir/$incremental/dispRoutrer_$(date "+%Y-%m-%d-%H-%M")_etc.tar.$typeComress || log 'bkp dispRouter error; no icmp' 1 
	#####
	
	elections
	bkp
else
	log "ежедневный"
	#ежедневный
	incremental=day
	bkp
fi

rm -f $lockfile
exit 0

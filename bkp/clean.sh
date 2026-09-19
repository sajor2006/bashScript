#!/bin/bash 

scriptName=$0                                                # Название скрипта
logfile=/var/log/$(basename $scriptName .sh).log             # логи
dir=/bkp

function log {
	[ "$*" == "" ] && return 0 
	#echo -e "$(date +"%Y-%m-%d_%H-%M-%S") $1"
	echo -e "$(date +"%Y-%m-%d_%H-%M-%S") $1" >>$logfile
	[ "$2" != "" ] &&  echo -e "$(date +"%Y-%m-%d_%H-%M-%S") $1" >> "$2/delete.list"
    return 0
}

function clean {
	[ "$(basename $1)" == "delete.list" ] && exit 0
	name=''
	[ "$2" == "$dir/backupVM" ] && name=$(basename $1 |awk -F '_' '{print $3}')
	[ "$2" == "$dir/vm-backup-DC" ] && name=$(basename $1 |awk -F '#' '{print $1}')
	[ "$2" == "$dir/month" ] && name=$(basename $1 |awk -F '_' '{var=$1".*"$3; print var }')
	[ "$2" == "$dir/hosting.nic.ru" ] && name=$(basename $1 |awk -F '_' '{print $2}')
	[ "$2" == "$dir/MySQL" ] && name=$(basename $1 |awk -F 'mysqldump' '{print $2}')
	
	[ "$name" != "" ] && name=$(echo ${name%.*}) && [ $(ls -1 $2 | grep -c $name) -lt 2 ] && exit 0 # не удаляем последний бекап.
	log "$(du -sh $1 && rm -f $1)" "$2"
	exit 0	
}

[ "$1" != "" ] && clean "$1" "$2" && exit 0

find $dir/day 			-type f -mtime +7 -exec $0 {} "$dir/day" \;
find $dir/day -name "*share*" 	-type f  -size +100G -exec $0 {} "$dir/day" \;
find $dir/wk 			-type f -mtime +30 -exec $0 {} "$dir/wk" \;
find $dir/wk -name "*share*" 	-type f  -size +100G -exec $0 {} "$dir/wk" \;
find $dir/month			-type f -mtime +90 -exec $0 {} "$dir/month" \;

find $dir/vm-backup-DC 		-maxdepth 1 -type f -mtime +61 -exec $0 {} "$dir/vm-backup-DC" \;
find $dir/hosting.nic.ru 	-type f -mtime +181 -exec $0 {} "$dir/hosting.nic.ru" \;
find $dir/MySQL 		-type f -mtime +90 -exec $0 {} "$dir/MySQL" \;


find $dir/vm-backup-DC -maxdepth 1 -regex '.*\(BD2\|BD3\|vm2CORE\).*' 	-type f -mtime +21 -exec $0 {} "$dir/vm-backup-DC" \;
find $dir/vm-backup-DC -maxdepth 1 -regex '.*\(VPN\|vm1CORE\).*' 	-type f -mtime +28 -exec $0 {} "$dir/vm-backup-DC" \;

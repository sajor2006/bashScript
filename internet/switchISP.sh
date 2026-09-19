# !/usr/bin/env  bash
#
#
#
ip='85.119.149.3 185.15.59.224 62.217.160.2 77.88.8.3 77.88.8.7' # <- Лучше редактировать только это
#
#
#
#

ip="$(echo $ip | sed -e 's/^ *//g' -e 's/* $//g')"
declare -A rout
rout[megafon]='11.55.299.197'
rout[mgts]='299.44.163.33'
declare -A vln
vln[megafon]='vlan766'
vln[mgts]='vlan228'
declare -A ISP
ISP[megafon]=0
ISP[mgts]=0
declare -A rate
rate[megafon]=1
rate[mgts]=1


# Check Wan 
for u in ${!ISP[*]}; do
    for i in $ip; do
        ip route add "$i/32" via "${rout[$u]}"
        ping -qw 3 "$i" > /dev/null || ISP[$u]="$((${ISP[$u]}+1))"
        ip route del "$i/32" via "${rout[$u]}"
    done
done

# Get default route main table
mainRourDef="$(ip route show |head -n 1 |awk '{print $3}')"

defRoutReplace(){ # rate процент распредиления
    rate[megafon]=$1
    rate[mgts]=$2

    ip route replace default table $3 nexthop via ${rout[megafon]} dev ${vln[megafon]} weight ${rate[megafon]} nexthop via ${rout[mgts]} dev ${vln[mgts]} weight ${rate[mgts]}    
    if [ $? -ne 0 ];then # На случай если по какой-то не понятной причине интерфейс был отключен
        [ "${rate[mgts]}" -eq "100"  ] && ip route replace default via "${rout[mgts]}" dev ${vln[mgts]} table $3
        [ "${rate[megafon]}" -eq "100"  ] && ip route replace default via "${rout[megafon]}" dev ${vln[megafon]} table $3
    fi

    # меняем маршрутизацию главной таблицы
    if [ "${rate[mgts]}" -eq "100" ] && [ "$mainRourDef" != "${rout[mgts]}" ]; then
        ip route replace default via "${rout[mgts]}" dev ${vln[mgts]}
        ip route flush cache
    elif [ "${rate[megafon]}" -gt "1"  ] && [ "$mainRourDef" != "${rout[megafon]}" ]; then
        ip route replace default via "${rout[megafon]}" dev ${vln[megafon]}
        ip route flush cache
    fi

}

if [ "${ISP[megafon]}" -eq "$(echo $ip | wc -w)" ] || [ "${ISP[mgts]}" -eq "$(echo $ip | wc -w)" ]; then
    # Если проблемы со связью у одного оператора все соединения отправляем на рабочего оператора
    if [ "${ISP[megafon]}" -eq "$(echo $ip | wc -w)" ];then
        defRoutReplace 1 100 125 # 1 наименьший приоритет для мегафона; 100 наивысший приоритет для мгтс; 125 номер таблицы маршрутизацыи 
        defRoutReplace 1 100 100
    else
        defRoutReplace 100 1 125
        defRoutReplace 100 1 100
    fi
else
    # Если все операторы работают выставляем все по умолчанию
    defRoutReplace 30 70 125
    defRoutReplace 70 30 100
fi

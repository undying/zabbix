#! /bin/bash

nc_timeout=1
nc_cmd="nc -w ${nc_timeout}"

timeout_cmd="timeout --preserve-status ${nc_timeout}"

data_json=""
data_json_head='{"data":['
data_json_tail=']}'

data_file="$(mktemp --suffix -zabbix_sender)"
data_json_file=$(mktemp --suffix -zabbix_sender_json)

while getopts 'Z:P:h:p:a:' arg;do
  case ${arg} in
    a)
      redis_addr=${OPTARG}
      ;;
    h)
      redis_host=${OPTARG}
      ;;
    p)
      redis_port=${OPTARG}
      ;;
    Z)
      zabbix_host=${OPTARG}
      ;;
    P)
      zabbix_port=${OPTARG}
      ;;
    *)
  esac
done

redis_host=${redis_host:-127.0.0.1}
redis_addr=${redis_addr:-${redis_host}}
redis_port=${redis_port:-6379}
zabbix_host=${zabbix_host:-127.0.0.1}
zabbix_port=${zabbix_port:-10051}

zbx_sender_cmd="zabbix_sender -vv -z ${zabbix_host} -p ${zabbix_port}"
data_json=${data_json_head}

db_count=0
comma=""
while read line;do
  line=${line//$'\r'/}
  line=${line//$'\n'/}
  line=${line// /}

  [ "${line:0:1}" == "#" ] && continue
  [ "${line:0:1}" == "$" ] && continue

  IFS=: read -r key value <<<"${line}"
  [ -z "${value}" ] && continue

  if [ ${key:0:2} == "db" ];then
    for kv in ${value//,/ };do
      IFS="=" read -r k v <<<"${kv}"
      echo "\"${redis_host}\" redis[${key},${k}] ${v}" >> ${data_file}
    done

    [ "${db_count}" -eq 0 ] && comma="" || comma=","

    data_json="${data_json}${comma}{\"{#DBNAME}\":\"${key}\"}"
    db_count=$[db_count+1]
  else
    echo "\"${redis_host}\" redis[${key}] ${value}" >> ${data_file}
  fi
done < <(echo info|${timeout_cmd} ${nc_cmd} ${redis_addr} ${redis_port})

data_json="${data_json}${data_json_tail}"
echo "\"${redis_host}\" redis.discovery ${data_json}" > ${data_json_file}

${zbx_sender_cmd} -i ${data_json_file}
${zbx_sender_cmd} -i ${data_file}

rm ${data_file} ${data_json_file}


#! /bin/bash

tcp_timeout=1
timeout_cmd="timeout --preserve-status ${tcp_timeout}"

data_json=""
data_json_head='{"data":['
data_json_tail=']}'

data_file="$(mktemp --suffix -zabbix_sender)"
data_json_file=$(mktemp --suffix -zabbix_sender_json)

trap "rm ${data_file} ${data_json_file}" EXIT SIGINT SIGTERM


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


### discover databases and collect metrics ###
comma_count=0
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

    [ "${comma_count}" -eq 0 ] && comma="" || comma=","

    data_json+="${comma}{\"{#DBNAME}\":\"${key}\"}"
    comma_count=$[comma_count+1]
  elif [ ${key:0:7} == "cmdstat" ];then
    for kv in ${value//,/ };do
      IFS="=" read k v <<<"${kv}"
      echo "\"${redis_host}\" redis[${key},${k}] ${v}" >> ${data_file}
    done

    [ "${comma_count}" -eq 0 ] && comma="" || comma=","

    data_json+="${comma}{\"{#CMDNAME\":\"${key}\"}"
    comma_count=$[comma_count+1]
  else
    echo "\"${redis_host}\" redis[${key}] ${value}" >> ${data_file}
  fi
done < <(${timeout_cmd} /bin/bash -c "exec 3<> /dev/tcp/${redis_addr}/${redis_port}; printf 'info all\r\n' >&3; cat <&3")
###


### get the top of clients with qbuf > 0 ###
redis_qbuf_top=""
redis_qbuf_max=0

while read line;do
  redis_qbuf_top+=${line}\\n
  _redis_qbuf_max=${line##*=}

  [ ${_redis_qbuf_max} -gt ${redis_qbuf_max} ] && redis_qbuf_max=${_redis_qbuf_max}
done < <(
  ${timeout_cmd} /bin/bash -c "
    exec 3<> /dev/tcp/${redis_addr}/${redis_port};
    printf 'CLIENT LIST\r\n' >&3;
    grep 'qbuf=[1-9]\+' <&3" | sed -e 's,.*\(addr=[^ ]\+\).*\(qbuf=[^ ]\+\).*,\1 \2,'
  )
###


echo \"${redis_host}\" \"redis[qbuf_top]\" \"${redis_qbuf_top}\" >> ${data_file}
echo \"${redis_host}\" redis[qbuf_max] ${redis_qbuf_max} >> ${data_file}


data_json="${data_json}${data_json_tail}"
echo "\"${redis_host}\" redis.discovery ${data_json}" > ${data_json_file}


${zbx_sender_cmd} -i ${data_json_file}
${zbx_sender_cmd} -i ${data_file}



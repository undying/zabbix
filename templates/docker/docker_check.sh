#! /bin/bash

while getopts 'dh:z:p:' opt;do
  case ${opt} in
    h)
      check_host=${OPTARG}
      ;;
    z)
      zabbix_server=${OPTARG}
      ;;
    p)
      zabbix_port=${OPTARG}
      ;;
    d)
      discovery=1
      ;;
    *)
  esac
done

check_host=${check_host:-${HOSTNAME}}
zabbix_send_data=$(mktemp --suffix=-zabbix_send)
zabbix_send_cmd="$(which zabbix_send) --input-file ${zabbix_send_data}"

[ -n "${zabbix_server}" ] && zabbix_send_cmd+=" --zabbix-server ${zabbix_server}"
[ -n "${zabbix_port}" ] && zabbix_send_cmd+=" --port ${zabbix_port}"

function cleanup(){     rm -f ${zabbix_send_data}; }
trap cleanup EXIT

declare -A docker_stats=()
declare -A docker_stats_multiplier=(
  [B]=1
  [kB]=1024
  [KB]=1024
  [MB]=$[1024 * 1024]
  [GB]=$[1024 * 1024 * 1024]
  [KiB]=1024
  [MiB]=$[1024 * 1024]
  [GiB]=$[1024 * 1024 * 1024]
)
declare -A docker_stats_metric_bytes=(
  [mem_usage]=mem_usage_unit
  [mem_limit]=mem_limit_unit
  [net_read]=net_read_unit
  [net_write]=net_write_unit
  [block_read]=block_read_unit
  [block_write]=block_write_unit
)
declare -A docker_skip_keys=(
  [_]=1
  [id]=1
  [mem_usage_unit]=1
  [mem_limit_unit]=1
  [net_read_unit]=1
  [net_write_unit]=1
  [block_read_unit]=1
  [block_write_unit]=1
)


docker_discovery_json_head='{"data":['
docker_discovery_json_tail=']}'
docker_discovery_json="${docker_discovery_json_head}"

docker_inspect_format='Name:{{.Name}},RestartCount:{{.RestartCount}}'
docker_stats_format="id cpu mem_usage mem_usage_unit _ mem_limit mem_limit_unit mem_percent net_read net_read_unit _ net_write net_write_unit block_read block_read_unit _ block_write block_write_unit pids"

function docker_discovery(){
  local count=0
  for container_id in $(docker ps --quiet);do
    [ ${count} -eq 0 ] || json_comma=,
    docker_discovery_json+="${json_comma}{\"Id\":\"${container_id}\""

    IFS=,
    for line in $(docker inspect --format "${docker_inspect_format}" ${container_id});do
      IFS=":" read key value <<<"${line}"
      docker_discovery_json+=",\"${key}\":\"${value#/}\""
    done
    unset IFS

    docker_discovery_json+='}'
    count=$[count+1]
  done

  docker_discovery_json+=${docker_discovery_json_tail}
  echo ${docker_discovery_json}
}

function docker_stats(){
  local count=0
  while read line;do
    count=$[count+1]
    [ ${count} -eq 1 ] && continue

    read ${docker_stats_format} <<<"${line}"
    for key in ${docker_stats_format};do
      [ -z "${docker_skip_keys[${key}]}" ] || continue

      local unit=${docker_stats_metric_bytes[${key}]}
      if [ -z "${unit}" ];then
        echo "docker_stats[${id},${key}] ${!key//%/}"
        continue
      fi

      echo "docker_stats[${id},${key}]" $(awk "BEGIN {print int(${!key} * ${docker_stats_multiplier[${!unit}]})}")
    done
  done < <(docker stats --no-stream)
}


[ -n "${discovery}" ] && docker_discovery || docker_stats


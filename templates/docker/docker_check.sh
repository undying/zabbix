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
      echo "Usage: $0 [options]"
      exit
  esac
done

check_host=${check_host:-${HOSTNAME}}

zabbix_data=/tmp/.docker_stats
zabbix_data_tmp=$(mktemp --suffix=-zabbix_send)
chmod 644 ${zabbix_data_tmp}

[ -n "${zabbix_server}" ] && zabbix_send_cmd+=" --zabbix-server ${zabbix_server}"
[ -n "${zabbix_port}" ] && zabbix_send_cmd+=" --port ${zabbix_port}"

function cleanup(){ rm -f ${zabbix_data_tmp}; }
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

docker_inspect_format='Name:{{.Name}},RestartCount:{{.RestartCount}},IPAddress:{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
docker_stats_format="id cpu mem_usage mem_usage_unit _ mem_limit mem_limit_unit mem_percent net_read net_read_unit _ net_write net_write_unit block_read block_read_unit _ block_write block_write_unit pids"

function docker_discovery(){
  local count=0
  for container_id in $(docker ps --quiet);do
    [ ${count} -eq 0 ] || json_comma=,
    docker_discovery_json+="${json_comma}{\"{#ID}\":\"${container_id}\""

    IFS=,
    for line in $(docker inspect --format "${docker_inspect_format}" ${container_id});do
      IFS=":" read key value <<<"${line}"
      docker_discovery_json+=",\"{#${key^^}}\":\"${value#/}\""
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
      [ -n "${!key}" ] || continue
      [ -z "${docker_skip_keys[${key}]}" ] || continue

      local unit=${docker_stats_metric_bytes[${key}]}
      if [ -z "${unit}" ];then
        echo "docker_stats[${id},${key}] ${!key//\%/}" >> ${zabbix_data_tmp}
        continue
      fi

      local value=${!key//[a-zA-Z]/}
      local unit_size=${docker_stats_multiplier[${!unit}]}
      [ -n "${unit_size}" ] || unit_size=${docker_stats_multiplier[${!key//[.0-9]/}]}

      echo "docker_stats[${id},${key}]" $(awk "BEGIN {printf \"%f\", ${value} * ${unit_size}}") >> ${zabbix_data_tmp}
    done
  done < <(timeout 4 docker stats --no-stream|sed -e 's,[[:space:]]\([.0-9]\+\)\([a-zA-Z]\+\)[[:space:]], \1 \2 ,g')

  mv ${zabbix_data_tmp} ${zabbix_data}
  echo $[count-1]
}


[ -n "${discovery}" ] && docker_discovery || docker_stats


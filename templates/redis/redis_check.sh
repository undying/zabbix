#! /bin/bash -e

nc_timeout=1
nc_cmd="nc -w ${nc_timeout}"

timeout_cmd="timeout --preserve-status ${nc_timeout}"
data_file="$(mktemp --suffix zabbix_sender)"

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

zbx_sender_cmd="zabbix_sender -z ${zabbix_host} -p ${zabbix_port}"

declare -A allowed_keys=(
  [connected_clients]=1
  [blocked_clients]=1

  [used_memory]=1
  [used_memory_peak]=1
  [maxmemory]=1
  [total_system_memory]=1
  [used_memory_lua]=1
  [mem_fragmentation_ratio]=1

  [loading]=1
  [rdb_changes_since_last_save]=1
  [rdb_bgsave_in_progress]=1
  [rdb_last_save_time]=1
  [rdb_last_bgsave_status]=1
  [rdb_last_bgsave_time_sec]=1
  [rdb_current_bgsave_time_sec]=1
  [aof_enabled]=1
  [aof_rewrite_in_progress]=1
  [aof_rewrite_scheduled]=1
  [aof_last_rewrite_time_sec]=1
  [aof_current_rewrite_time_sec]=1
  [aof_last_bgrewrite_status]=1
  [aof_last_write_status]=1

  [total_connections_received]=1
  [total_commands_processed]=1
  [instantaneous_ops_per_sec]=1
  [total_net_input_bytes]=1
  [total_net_output_bytes]=1
  [instantaneous_input_kbps]=1
  [instantaneous_output_kbps]=1
  [rejected_connections]=1
  [sync_full]=1
  [sync_partial_ok]=1
  [sync_partial_err]=1
  [expired_keys]=1
  [evicted_keys]=1
  [keyspace_hits]=1
  [keyspace_misses]=1
)

while read line;do
  line=${line//$'\n'/}
  line=${line// /}

  [ "${line:0:1}" == "#" ] && continue
  [ "${line:0:1}" == "$" ] && continue

  IFS=: read -r key value <<<"${line}"
  value=${value//$'\r'/}

  [ -z "${value}" ] && continue
  [ -z "${allowed_keys[${key}]}" ] && continue

  echo "\"${redis_host}\" redis[${key}] ${value}" >> ${data_file}
  metrics_count=$[metrics_count+1]
done < <(echo info|${timeout_cmd} ${nc_cmd} ${redis_addr} ${redis_port})

${zbx_sender_cmd} -i ${data_file}
rm ${data_file}


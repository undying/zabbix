#! /bin/bash

while getopts 'c:h:a:p:' arg;do
  case ${arg} in
    c)
      aerospike_command=${OPTARG}
      ;;
    h)
      aerospike_host=${OPTARG}
      ;;
    a)
      aerospike_addr=${OPTARG}
      ;;
    p)
      aerospike_port=${OPTARG}
      ;;
    t)
      filter_type=${OPTARG}
      ;;
    *)
      echo "usage: ${0} -h [aerospike_host] -p [aerospike_port]"
      exit
  esac
done


script_path=${BASH_SOURCE[0]%/*}

[ -e ${script_path}/aerospike.defaults ] && . ${script_path}/aerospike.defaults || exit 1
[ -e ${script_path}/aerospike.scripts ] && . ${script_path}/aerospike.scripts || exit 1

data_json_head='{"data":['
data_json_tail=']}'

data_json="${data_json_head}"
data_json_comma=""


count=0
while read line;do
  [ -n "${line}" ] || continue

  case ${aerospike_command} in
    sets)
      as_ns=${line##ns=}
      as_ns=${as_ns%%:*}
      as_set=${line##*set=}
      as_set=${as_set%%:*}

      IFS=":"
      for set_line in ${line#*:*:};do
        [ ${count} -eq 0 ] && data_json_comma="" || data_json_comma=,
        IFS="=" read key value <<<"${set_line}"
        [ -n "${key}" ] || continue

        value=$(normalize_value ${value})
        v_type=$(value_type ${value})

        [ -n "${metrics_set_counters[${key}]}" ] && v_type=count
        v_unit=${metrics_set_units[${key}]}

        data_json+="${data_json_comma}{\"{#AS_NS}\":\"${as_ns}\",\"{#AS_SET_NAME}\":\"${as_set}\",\"{#AS_SET_METRIC_NAME}\":\"${key}\",\"{#AS_SET_METRIC_TYPE}\":\"${v_type}\",\"{#AS_SET_METRIC_UNIT}\":\"${v_unit}\"}"
        count=$[count+1]
      done
      unset IFS
      ;;

    services)
      as_service_index=${as_service_index:-0}
      as_service_index=$[as_service_index+1]

      [ ${as_service_index} -gt 1 ] && data_json_comma=,

      data_json+="${data_json_comma}{\"{#AS_SERVICE}\":\"${line}\",\"{#AS_SERVICE_HOST}\":\"${line%:*}\",\"{#AS_SERVICE_PORT}\":\"${line#*:}\",\"{#AS_SERVICE_INDEX}\":\"${as_service_index}\"}"
      ;;

    namespace_metrics)
      while read ns_line;do
        IFS="=" read key value <<<"${ns_line}"
        [ -n "${key}" ] || continue

        [ -n "${metrics_namespace_whitelist[${key}]}" ] || continue
        [ ${count} -eq 0 ] && data_json_comma="" || data_json_comma=,

        value=$(normalize_value ${value})
        v_type=$(value_type ${value})

        [ -n "${metrics_namespace_counters[${key}]}" ] && v_type=count
        v_unit=${metrics_namespace_units[${key}]}

        if [ -n "${filter_type}" ];then
          [ "${filter_type}" == "${v_type}" ] || continue
        fi

        data_json+="${data_json_comma}{\"{#AS_NS}\":\"${line}\",\"{#AS_NS_METRIC_NAME}\":\"${key}\",\"{#AS_NS_METRIC_TYPE}\":\"${v_type}\",\"{#AS_NS_METRIC_UNIT}\":\"${v_unit}\"}"
        count=$[count+1]
      done < <(${asinfo_cmd} -v "namespace/${line}")
      ;;

    namespaces)
      while read ns;do
        [ ${count} -eq 0 ] && data_json_comma="" || data_json_comma=,
        data_json+="${data_json_comma}{\"{#AS_NS}\":\"${ns}\"}"

        count=$[count+1]
      done < <(${asinfo_cmd} -v "namespaces")
      ;;

    statistics)
      IFS="=" read key value <<<"${line}"
      [ -n "${key}" ] || continue

      [ -n "${metrics_statistics_whitelist[${key}]}" ] || continue
      [ ${count} -eq 0 ] && data_json_comma="" || data_json_comma=,

      value=$(normalize_value ${value})
      v_type=$(value_type ${value})
      [ -n "${metrics_statistics_counters[${key}]}" ] && v_type=count

      v_unit=${metrics_statistics_units[${key}]}
      v_multiplier=${metrics_statistics_multiplier[${key}]}

      data_json+="${data_json_comma}{\"{#AS_STATISTICS_METRIC_NAME}\":\"${key}\",\"{#AS_STATISTICS_METRIC_TYPE}\":\"${v_type}\",\"{#AS_STATISTICS_METRIC_UNIT}\":\"${v_unit}\",\"{#AS_STATISTICS_METRIC_MULTIPLIER}\":\"${v_multiplier}\"}"
      count=$[count+1]
      ;;

    get-config)
      IFS="=" read key value <<<"${line}"
      [ -n "${key}" ] || continue

      [ -n "${metrics_config_whitelist[${key}]}" ] || continue
      [ ${count} -eq 0 ] && data_json_comma="" || data_json_comma=,

      value=$(normalize_value ${value})
      v_type=$(value_type ${value})
      v_unit=${metrics_config_units[${key}]}
      v_multiplier=${metrics_config_multiplier[${key}]}

      data_json+="${data_json_comma}{\"{#AS_CONFIG_METRIC_NAME}\":\"${key}\",\"{#AS_CONFIG_METRIC_TYPE}\":\"${v_type}\",\"{#AS_CONFIG_METRIC_UNIT}\":\"${v_unit}\",\"{#AS_CONFIG_METRIC_MULTIPLIER}\":\"${v_multiplier}\"}"
      count=$[count+1]
      ;;

    *)
      continue
  esac

  count=$[count+1]
done < <(${asinfo_cmd} -v ${aerospike_command})

data_json+=${data_json_tail}
printf "%s" ${data_json}


#! /bin/bash

while getopts 'c:n:h:a:p:Z:P:' arg;do
  case ${arg} in
    c)
      aerospike_command=${OPTARG}
      ;;
    n)
      aerospike_namespace=${OPTARG}
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
    Z)
      zabbix_host=${OPTARG}
      ;;
    P)
      zabbix_port=${OPTARG}
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

trap cleanup EXIT

script_name=${0%%.sh}
script_name=${script_name##*/}
data_file=$(mktemp --suffix -${script_name})

if [ "${aerospike_command}" == "namespace" -a -z "${aerospike_namespace}" ];then
  echo "passed command \"${aerospike_command}\" but namespace is not set"
  exit 1
fi


case ${aerospike_command} in
  get-config|statistics)
    asinfo_cmd+=" -v ${aerospike_command}"
    ${command_function[${aerospike_command}]} \
      "${aerospike_host}" \
      "${asinfo_cmd}" \
      "${data_file}"
    ;;

  sets|namespace)
    asinfo_cmd+=" -v ${aerospike_command}/${aerospike_namespace}"
    ${command_function[${aerospike_command}]} \
      "${aerospike_namespace}" \
      "${aerospike_host}" \
      "${asinfo_cmd}" \
      "${data_file}"
    ;;

  status)
    ${asinfo_cmd} -v status
    ;;

  *)
    echo "unsupported command \"${aerospike_command}\""
    exit 1
esac

${zabbix_sender_cmd} -i ${data_file}


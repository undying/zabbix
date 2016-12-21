
## Template and script to monitor Aerospike Service

### How to use

You need to place all bash scripts "aerospike*" to the zabbix external scripts directory on the server (or on the proxy if you use them).
Also, you have to install aerospike tools on your proxy for this script to work. It needs asinfo to connect to the aerospike cluster.
Then import this template and assign it to host you need.
That's it.

Aerospike Tools: http://www.aerospike.com/download/tools/3.10.2/

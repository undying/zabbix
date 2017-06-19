
BEGIN {
  output = "/tmp/.socket.stat"
}

/LISTEN/ {
  recv_q = $2
  send_q = $3

  ipaddr_size = split($4, ipaddr, ":")

  if(ipaddr_size > 2)
    ipaddr_version = "6"
  else 
    ipaddr_version = "4"


  printf "socket.recv_q[%d,%d]\t%d\n",
         ipaddr_version,
         ipaddr[ipaddr_size],
         recv_q > output
  printf "socket.send_q[%d,%d]\t%d\n",
         ipaddr_version,
         ipaddr[ipaddr_size],
         send_q > output
}

END {
  print 0
}

# vi:syntax=awk

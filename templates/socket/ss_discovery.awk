
BEGIN {
  ipaddr_size = 0
  ipaddr_version = ""

  json_string = ""
  json_data_size = 0
}


/LISTEN/ {
  ipaddr_size = split($4, ipaddr, ":")

  if(ipaddr_size > 2)
    ipaddr_version = "6"
  else 
    ipaddr_version = "4"

  listen_port = ipaddr[ipaddr_size]

  if(json_data_size > 0)
    json_string = ","

  json_string = json_string"{"

  json_string = json_string"\"{#IP_VERSION}\":\""ipaddr_version"\""
  json_string = json_string",\"{#LISTEN_PORT}\":\""listen_port"\""

  json_string = json_string"}"

  json_data_a[json_data_size++] = json_string
}

END {
  printf "{\"data\":["

  for(i=0;i < json_data_size;i++){
    printf json_data_a[i]
  }

  print "]}"
}

# vi:syntax=awk

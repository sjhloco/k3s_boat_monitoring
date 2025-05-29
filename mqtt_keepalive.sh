#!/bin/sh
i=0
while [ "$i" -le 2880 ]
do
  /usr/bin/mosquitto_pub -h 10.40.10.121 -t 'R/48e7da892735/keepalive' -n
  i=$((i + 1))
  sleep 30
done


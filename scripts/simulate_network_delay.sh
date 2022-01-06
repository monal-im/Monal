#!/bin/bash

iiface="bond0"
oiface="virbr0"
ip="212.21.75.16"

tc qdisc del dev $iiface root
tc qdisc add dev $iiface root handle 1: prio
tc qdisc add dev $iiface parent 1:3 handle 30: tbf rate 16kbit burst 1600 limit 3000
tc qdisc add dev $iiface parent 30:1 handle 31: netem  delay 2000ms 10ms distribution normal
tc filter add dev $iiface protocol ip parent 1:0 prio 3 u32 match ip dst $ip/32 flowid 1:3

tc qdisc del dev $oiface root
tc qdisc add dev $oiface root handle 1: prio
tc qdisc add dev $oiface parent 1:3 handle 30: tbf rate 16kbit burst 1600 limit 3000
#tc qdisc add dev $oiface parent 30:1 handle 31: netem  delay 3000ms 10ms distribution normal
tc filter add dev $oiface protocol ip parent 1:0 prio 3 u32 match ip src $ip/32 flowid 1:3


#!/bin/bash
# spine4,eth1,core2,eth1
# spine4,eth2,core1,eth1
# spine3,eth1,core2,eth2
#b7e89891af16c64599e05a31d5e0161ed0cfbe71df34bf316993e9ddb1eea926,core1,21629,172.17.0.2
#2f772b7d8b9e91396334ec6cd32f6e677928ba24b24f09109c9e416fd3c7b33d,core2,21796,172.17.0.3
#5491649ff892284be536ebf7fa6cc016839b2a81bc2e4b0b1e5de8bbf7d54b59,spine1,21971,172.17.0.4

if [ $# -ne 1 ]; then
  echo "Expected one parameters - filename containing the containers created by the companion script"
  exit 1
fi # if [ $# -ne 1 ]


container_record=$1
if [ ! -r "$container_record" ]; then
  echo "ERROR: Could not read $container_record for parsing."
  exit 1
fi # if [ ! -r "$container_record" ]

IFS=","
echo "BGPGlobal settings"
cat $container_record | while read cid name ns ip; do
  echo "flex --host $ip BGPGlobal config PATCH --json_blob '{\"ASNum\":\"$ns\",\"RouterId\":\"$ip\", \"Disabled\":false}'"
done

echo "LLDPGlobal settings"
cat $container_record | while read cid name ns ip; do
  echo "flex --host $ip LLDPGlobal config PATCH --json_blob '{\"Enable\": true}'"
done

echo "Per-port description"
sort -t "," -k1 netlinks | while read src srcnic dst dstnic; do
  grep "$src" $container_record | while read cid name ns ip; do
    echo "flex --host $ip Port config PATCH --json_blob '{\"Description\":\"$src:$srcnic to $dst:$dstnic\", \"IntfRef\":\"$srcnic\"}'"

    #echo "flex --host $name Port config PATCH --json_blob '{\"Description\":\"$src:$srcnic to $dst:$dstnic\", \"IntfRef\":\"$srcnic\"}'"
  done
done
sort -t "," -k3 netlinks | while read src srcnic dst dstnic; do
  grep "$dst" $container_record | while read cid name ns ip; do
    echo "flex --host $ip Port config PATCH --json_blob '{\"Description\":\"$dst:$dstnic to $src:$srcnic\", \"IntfRef\":\"$dstnic\"}'"
    #echo "flex --host $name Port config PATCH --json_blob '{\"Description\":\"$dst:$dstnic to $src:$srcnic\", \"IntfRef\":\"$dstnic\"}'"
  done
done

# Currently disabled since it seems that the global LLDP enable also auto-sets these.
# There is an argument that automatic enablement is not quite what we want, so at some point, these will be necessary
echo "Per-port LLDP"
sort -t "," -k1 netlinks | while read src srcnic dst dstnic; do
  grep "$src" $container_record | while read cid name ns ip; do
    echo "flex --host $ip LLDPIntf config PATCH --json_blob '{\"Enable\":true, \"IntfRef\":\"$srcnic\"}'"
    #echo "flex --host $name Port config PATCH --json_blob '{\"Description\":\"$src:$srcnic to $dst:$dstnic\", \"IntfRef\":\"$srcnic\"}'"
  done
done
sort -t "," -k3 netlinks | while read src srcnic dst dstnic; do
  grep "$dst" $container_record | while read cid name ns ip; do
    echo "flex --host $ip LLDPIntf config PATCH --json_blob '{\"Enable\":true, \"IntfRef\":\"$dstnic\"}'"
    #echo "flex --host $name Port config PATCH --json_blob '{\"Description\":\"$dst:$dstnic to $src:$srcnic\", \"IntfRef\":\"$dstnic\"}'"
  done
done

# BGP needs the following pieces in place
# An Lo0 with a /32 address in place - we need to have *something* to advertise
# A PolicyCondition describing the IP to be advertised
# A PolicyStmt referencing the PolicyCondition(s)
# A PolicyDefition utilizing a PolicyStmt
# An update to the BGPGlobal setting enable the redistribution of the policy defined by PolicyDefinition
# Yes, we're quite fond of matryoshka dolls, why do you ask?

echo "Meat and guts of BGP now"
network=0
cat $container_record | while read cid name ns ip; do
  # The echo statements are commented out because they'd make it UnPossible to cleanly copy/paste the config 
  # run commands. But, left here in the interests of serving as documentation/intent.
  #echo -e "\tCreating interface Lo0 on $name ($ip)"
  echo "flex --host $ip LogicalIntf config POST --json_blob '{\"Name\": \"Lo0\", \"Type\": \"Loopback\"}'"
  #echo -e "\tAssigning 192.168.$network.1/32 to Lo0 on $name ($ip)"
  echo "flex --host $ip LogicalIntf config POST --json_blob '{\"IntfRef\": \"Lo0\", \"IpAddr\": \"192.168.$network.1/32\"}'"
  #echo -e "\tCreating a PolicyCondition referencing the 192.168.$network.1/32"
  echo "flex --host $ip PolicyCondition config POST --json_blob '{\"Name\": \"MatchLoopbackIPv4\", \"ConditionType\": \"MatchDstIpPrefix\", \"Protocol\": \"\", \"IpPrefix\": \"192.168.$network.1/32\", \"MaskLengthRange\": \"exact\"}'"
  #echo -e "\tCreating a PolicyStmt using the previously-created PolicyCondition"
  echo "flex --host $ip PolicyStmt config POST --json_blob '{\"SetActions\": null, \"Name\": \"RedistLoopback\", \"MatchConditions\": \"any\", \"Conditions\": [\"MatchLoopbackIPv4\"], \"Action\": \"permit\" }'"
  #echo -e "\tCreating a PolicyDefinition referencing the PolicyStmt which references the PolicyCondition..."
  echo "flex --host $ip PolicyDefinition config POST --json_blob '{\"Name\": \"RedistConnect_Policy\", \"Priority\": 1, \"MatchType\": \"any\", \"PolicyType\": \"ALL\", \"StatementList\": [{\"Priority\": 1, \"Statement\": \"RedistLoopback\"}]}'"
  #echo -e "\tWrapping it all with a pretty bow of adjusting the BGPGlobal object to enable the newly-created policy. Note the PATCH method."
  echo "flex --host $ip BGPGlobal config PATCH --json_blob '{\"Redistribution\": [{\"Sources\": \"CONNECTED\", \"Policy\": \"RedistConnect_Policy\"}]}'"
  network=$((network+1))
done

unset IFS

for i in $(ip rule|grep "from all fwmark" |awk '{print $5 }'|xargs -l1 -n1);do
  ip rule del from all fwmark $i
done

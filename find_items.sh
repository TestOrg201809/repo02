#!/bin/bash

PATH=/usr/bin:/bin
hostname=`hostname -s`
fname=/usr/sap/datastage/metis/item_of_interest_${hostname}.txt
perl /usr/sap/datastage/metis/find_items.perl > ${fname}
chmod 644 ${fname}
chown 15560 ${fname} # metis:oracle:uid

#!/usr/bin/perl

use strict;
use warnings;
use Sys::Hostname;
use Time::Piece;

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
$year += 1900;
$mon++;
my $now = sprintf("%d%02d%02d %02d:%02d:%02d", $year,$mon,$mday,$hour,$min,$sec);
#### print $now, "\n";

my $hostname = hostname;
#### print $hostname, "\n";

# fs
my $item_type = 'fs';
open(MOUNTS, '/proc/mounts') or die;
while (my $line = <MOUNTS>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 my @line = split(/\s+/, $line);
 # if (@line != 5) { next; }
 # if ($line[2] ne 'tcp') { next; }
 my $value = $line[1];
 print qq{$now,$hostname,$item_type,$value,1,"$line"\n};
}
close(MOUNTS);

# defined users
my %users = ();
open(PASSWD, '/etc/passwd') or die;
while (my $line = <PASSWD>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 my @line = split(/:/, $line);
 # if (@line != 5) { next; }
 # if ($line[2] ne 'tcp') { next; }
 my $value = $line[0];
 $users{$value} = $line;
 # ($users{$value} = $line) =~ s/"/\\"/g; # works
}
close(PASSWD);

open(SHADOW, '/etc/shadow') or die;
while (my $line = <SHADOW>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 my @line = split(/:/, $line);
 # if (@line != 5) { next; }
 # if ($line[2] ne 'tcp') { next; }
 my $value = $line[0];
 if (exists $users{$value}) {
 $users{$value} .= ' ' . $line;
 } else {
 $users{$value} = '[missing passwd entry]. ' . $line;
 }
}
close(SHADOW);

open(GROUP, '/etc/group') or die;
while (my $line = <GROUP>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 my @line = split(/:/, $line);
 # if (@line != 5) { next; }
 # if ($line[2] ne 'tcp') { next; }
 my $grpname = $line[0];
 if (@line == 4 && length($line[3]) > 0) {
  my $list = $line[3];
  my @list = split(/,/, $list);
  foreach my $member (@list) {
   if (exists $users{$member}) { $users{$member} .= ' member of '.$grpname.'.'; }
   else {
     # user could be defined in AD, not in /etc/password
     print qq{invalid member $member in $line\n};
   }
  }
 } else {
  #### print qq{no members: $line\n};
  #### exit 0;
 }
}
close(GROUP);

$item_type = 'user (ld)';
foreach my $k (sort keys %users) {
 my $notes = $users{$k};
 $notes =~ s/"/'/g;
 $notes =~ s/\$/\\\$/g;
 print qq{$now,$hostname,$item_type,$k,1,"$notes"\n};
}

# logged in users
# w
# who -a
# users
$item_type = 'user (in)';
open(WHO, "/usr/bin/who|") or die;
while (my $line = <WHO>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 $line =~ s/\s+/ /g;
 my @line = split(/\s+/, $line);
 my $username = $line[0];
 print qq{$now,$hostname,$item_type,$username,1,"$line"\n};
}
close(WHO);
my $users = `/usr/bin/users`;
chomp($users);
my @users = split(/\s+/, $users);
my %user_counts = ();
$user_counts{$_}++ for @users;
foreach my $k (sort keys %user_counts) {
 my $cnt = $user_counts{$k};
 print qq{$now,$hostname,$item_type,$k,$cnt,""\n};
}

# processors
# /proc/cpuinfo
# lscpu
# hardinfo lshw nproc dmidecode cpuid inxi
my $nproc = `/usr/bin/nproc`;
chomp($nproc);
$item_type = 'cpu';
print qq{$now,$hostname,$item_type,$item_type,$nproc,""\n};

open(CPUINFO, '/proc/cpuinfo') or die;
# processor       : 0
# model name      : Intel(R) Xeon(R) CPU E5-2680 v2 @ 2.80GHz
while (my $line = <CPUINFO>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 my @line = split(/:/, $line);
 if (@line < 2) { next; }
 # if ($line[0] =~ /processor/) {}
 if ($line[0] =~ /model name/) {
  my $v = $line[1];
  $v =~ s/^\s+//;
  $v =~ s/\s+$//;
  print qq{$now,$hostname,$item_type,$v,1,""\n};
 }
}
close(CPUINFO);

# os
my $uname = `/bin/uname -a`;
chomp($uname);
$item_type = 'os';
print qq{$now,$hostname,$item_type,$uname,1,""\n};

my @issues = qw(/etc/issue /etc/issue.net /etc/redhat-release);
my $qissue = 0;
my $issue = '';
foreach my $fname (@issues) {
 if (open(ISSUE, $fname)) {
  $issue = <ISSUE>;
  close(ISSUE);
  chomp($issue);
  $qissue = 1;
  last;
 }
}
if ($qissue) {
print qq{$now,$hostname,$item_type,$issue,1,""\n};
}

# rpm -qa --last
# https://forums.opensuse.org/printthread.php?t=467685&pp=10
# rpm -q -a --queryformat "%{INSTALLTIME};%{INSTALLTIME:day}; %{BUILDTIME:day}; %{NAME};%{VERSION}-%-7{RELEASE};%{arch}; %{VENDOR};%{PACKAGER};%{DISTRIBUTION};%{DISTTAG}\n" | sort | cut --fields="2-" --delimiter=\; | tee rpmlist.csv | less -S
# rpm -q -a --queryformat "%{INSTALLTIME}\t%{INSTALLTIME:day} %{BUILDTIME:day} %-30{NAME}\t%15{VERSION}-%-7{RELEASE}\t%{arch} %25{VENDOR}%25{PACKAGER} == %{DISTRIBUTION} %{DISTTAG}\n" | sort | cut --fields="2-" > rpmlist
my %rpm_dates = ();
open(RPM, "/bin/rpm -qa --last|") or die;
my $q_rpm_date_format = 0; # 0=not tested yet; 1=tested
my $rpm_date_format = 0; # 0=metis,otho 1=julius
while (my $line = <RPM>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 my @line = split(/\s+/, $line);
 shift(@line);
 # my $rpmdate = join(' ', @line);
 # Mon Sep 17 09:28:24 2018 metis
 # Tue 09 May 2017 03:03:53 PM CDT julius
 my $rpmdate = $line[4].'-'.$line[1].'-'.$line[2];
 if ($q_rpm_date_format == 0) {
   $q_rpm_date_format = 1;
   my $q = is_valid_date_Ybd($rpmdate);
   #### print qq{try 1: $rpmdate: $q\n};
   if ($q == 0) {
    $rpmdate = $line[3].'-'.$line[2].'-'.$line[1];
    $q = is_valid_date_Ybd($rpmdate);
    #### print qq{try 2: $rpmdate: $q\n};
    if ($q == 1) { $rpm_date_format = 1; }
    else {
      print qq{unexpected date format from /bin/rpm -qa --last\n};
      exit 1;
    }
   }
 }
 #### print qq{rpm_date_format $rpm_date_format\n}; exit 0;
 if ($rpm_date_format == 1) { $rpmdate = $line[3].'-'.$line[2].'-'.$line[1]; }
 #### print qq{$rpmdate\n};
 if (! exists $rpm_dates{$rpmdate}) { $rpm_dates{$rpmdate} = 1; }
 else { $rpm_dates{$rpmdate}++; }
}
close(RPM);
$item_type = 'yum-last';
foreach my $k
(sort { Time::Piece->strptime($b, '%Y-%b-%d') <=> Time::Piece->strptime($a, '%Y-%b-%d') } keys %rpm_dates) {
  #### print $k, ' ', $rpm_dates{$k}, "\n";
  my $npackages = $rpm_dates{$k};
  print qq{$now,$hostname,$item_type,$k,$npackages,""\n};
}

# last OS reboot
# last reboot
# reboot   system boot  2.6.32-696.18.7. Tue Apr  3 11:34 - 14:27 (169+02:53)
# reboot   system boot  2.6.32-696.3.2.e Thu Sep 21 13:56 - 11:33 (193+21:36)
# reboot   system boot  2.6.32-696.el6.x Thu Jun 22 10:38 - 13:55 (91+03:17)
# reboot   system boot  2.6.32-642.11.1. Thu Mar 23 09:25 - 10:37 (91+01:11)
# reboot   system boot  2.6.32-642.6.1.e Fri Dec 16 20:06 - 09:24 (96+12:17)
# reboot   system boot  2.6.32-642.3.1.e Tue Sep 20 15:02 - 20:06 (87+06:03)
# reboot   system boot  2.6.32-642.1.1.e Fri Jun 24 19:23 - 15:01 (87+19:38)
# reboot   system boot  2.6.32-642.1.1.e Fri Jun 24 16:10 - 19:23  (03:13)
# reboot   system boot  2.6.32-642.1.1.e Fri Jun 24 16:01 - 16:09  (00:08)
# wtmp begins Fri Jun 24 15:52:58 2016
# no year
open(LAST, "/usr/bin/last reboot|") or die;
my @reboots = ();
while (my $line = <LAST>) {
 chomp($line);
 push(@reboots, $line);
}
close(LAST);
my $year_start;
foreach my $tmps (@reboots) {
 if ($tmps =~ /wtmp/) {
   my @tmps = split(/\s+/, $tmps);
   $year_start = $tmps[-1];
 }
}
#### printf qq{start year $year_start; end year $year\n};

my %reboot_guess = ();
foreach my $tmps (reverse @reboots) {
 if ($tmps =~ /reboot/) {
   $tmps =~ s/^\s+//;
   $tmps =~ s/\s+$//;
   my @tmps = split(/\s+/, $tmps);
   my $w_m_d = $tmps[4] . '-' . $tmps[5] . '-' . $tmps[6];
   $reboot_guess{$w_m_d} = $w_m_d;
   #### print qq{$w_m_d\n};
   for (my $y = $year_start; $y <= $year; $y++) {
     my $retcode = is_valid_date($y . '-' . $w_m_d);
     #### print qq{retcode $retcode\n};
     if ($retcode == 1) {
      #### print qq{$w_m_d-$y\n};
      # $reboot_guess{$w_m_d} = $w_m_d.'-'.$y;
      # $reboot_guess{$w_m_d} = $y . '-' . $tmps[5] . '-' . $tmps[6] . ' ' . $tmps[4] . ' ' . $tmps[7] . ' ' . $tmps[8] . ' ' . $tmps[9] . ' ' . $tmps[10];
      $reboot_guess{$tmps} = $y . '-' . $tmps[5] . '-' . $tmps[6] . ' ' . $tmps[4] . ' ' . $tmps[7] . ' ' . $tmps[8] . ' ' . $tmps[9] . ' ' . $tmps[10];
      last;
     }
   }
 }
}
$item_type = 'reboot';
foreach my $tmps (@reboots) {
 if ($tmps =~ /reboot/) {
   $tmps =~ s/^\s+//;
   $tmps =~ s/\s+$//;
   # my @tmps = split(/\s+/, $tmps);
   # my $w_m_d = $tmps[4] . '-' . $tmps[5] . '-' . $tmps[6];
   # print $reboot_guess{$w_m_d}, "\n";
   #### print $reboot_guess{$tmps}, "\n";
   my $v = $reboot_guess{$tmps};
   print qq{$now,$hostname,$item_type,$v,1,""\n};
 }
}

# https://perlmaven.com/fatal-errors-in-external-modules
sub is_valid_date {
 my $tmps = shift;
 # my $format = shift;
 # if (! defined $format) { $format = "%Y-%a-%b-%d"; }
 my $retcode;
 eval {
        my $tp = Time::Piece->strptime($tmps, "%Y-%a-%b-%d");
        # my $tp = Time::Piece->strptime($tmps, $format);
        #### print qq{$tmps -> $tp\n};
        my $news = $tp->year . '-' . $tp->wdayname . '-' . $tp->monname . '-' . $tp->day_of_month;
        #### print qq{$tmps $news\n};
        if ($news eq $tmps) {
        $retcode = 1; # valid
        } else {
        $retcode = 0;
        }
        1;
    } or do {
        my $error = $@ || 'Unknown failure';
        warn "Could not parse '$tmps' - $error";
        $retcode = 0; # invalid
    };
  $retcode;
}
sub is_valid_date_Ybd {
 my $tmps = shift;
 my $retcode;
 eval {
        my $tp = Time::Piece->strptime($tmps, "%Y-%b-%d");
        #### print qq{$tmps -> $tp\n};
        my $news = $tp->year . '-' . $tp->monname . '-' . $tp->day_of_month;
        #### print qq{$tmps $news\n};
        if ($news eq $tmps) {
        $retcode = 1; # valid
        } else {
        $retcode = 0;
        }
        1;
    } or do {
        # my $error = $@ || 'Unknown failure';
        # warn "Could not parse '$tmps' - $error";
        $retcode = 0; # invalid
    };
  $retcode;
}


# GPU
# https://askubuntu.com/questions/5417/how-to-get-the-gpu-info
# lspci
# /proc/bus/pci
# 00:0f.0 VGA compatible controller: VMware SVGA II Adapter
# 03:00.0 Ethernet controller: VMware VMXNET3 Ethernet Controller (rev 01)
open(LSPCI, "/sbin/lspci|") or die;
my %vga = ();
my %ethernet = ();
while (my $line = <LSPCI>) {
 my @line = split(/: /, $line);
 #### print $line[0], "\n";
 my $v = $line[1];
 $v =~ s/^\s+//;
 $v =~ s/\s+$//;
 if ($line[0] =~ /VGA/) {
   if (! exists $vga{$v}) { $vga{$v} = 1; }
   else { $vga{$v}++; }
 } elsif ($line[0] =~ /Ethernet/) {
   if (! exists $ethernet{$v}) { $ethernet{$v} = 1; }
   else { $ethernet{$v}++; }
 }
}
close(LSPCI);
$item_type = 'pci (GPU)';
foreach my $k (sort keys %vga) {
 my $m = $vga{$k};
 print qq{$now,$hostname,$item_type,$k,$m,""\n};
}
$item_type = 'pci (Ethernet)';
foreach my $k (sort keys %ethernet) {
 my $m = $ethernet{$k};
 print qq{$now,$hostname,$item_type,$k,$m,""\n};
}


# memory
# swap space
# /proc/meminfo
# swapon -s
# /proc/swaps
open(MEMINFO, '/proc/meminfo') or die;
# MemTotal:       32871588 kB
# MemFree:          261844 kB
# SwapTotal:      67108860 kB
# SwapFree:       67108860 kB
while (my $line = <MEMINFO>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 my @line = split(/:/, $line);
 if (@line < 2) { next; }
 if ($line[0] =~ /MemTotal|MemFree|SwapTotal|SwapFree/) {
  my $v = $line[1];
  $v =~ s/^\s+//;
  $v =~ s/\s+$//;
  my $t = $line[0];
  print qq{$now,$hostname,$t,$v,1,""\n};
 }
}
close(MEMINFO);
$item_type = 'memory (parts)';
open(DMIDECODE, '/usr/sbin/dmidecode -t 6|') or die;
#       Installed Size: 8192 MB (Single-bank Connection)
#       Enabled Size: 8192 MB (Single-bank Connection)
#       Installed Size: Not Installed
#       Enabled Size: Not Installed
my %installed = ();
my %enabled = ();
while (my $line = <DMIDECODE>) {
 if ($line =~ /Installed Size|Enabled Size/ && $line !~ /Not Installed/) {
  $line =~ s/^\s+//;
  $line =~ s/\s+$//;
  my @line = split(/:/, $line);
  my $v = $line[1];
  $v =~ s/^\s+//;
  $v =~ s/\s+$//;
  if ($line =~ /Installed Size/) {
   if (! exists $installed{$v}) { $installed{$v} = 1; }
   else { $installed{$v}++; }
  }
  if ($line =~ /Enabled Size/) {
   if (! exists $enabled{$v}) { $enabled{$v} = 1; }
   else { $enabled{$v}++; }
  }
 }
}
close(DMIDECODE);
foreach my $k (sort keys %installed) {
  my $m = $installed{$k};
  print qq{$now,$hostname,memory (installed),$k,$m,""\n};
}
foreach my $k (sort keys %enabled) {
  my $m = $enabled{$k};
  print qq{$now,$hostname,memory (enabled),$k,$m,""\n};
}

$item_type = 'swap (parts)';
open(SWAPS, "/proc/swaps") or die;
# Filename                                Type            Size    Used    Priority
# /dev/dm-0                               partition       2097148 14180   -1
# /swap1                                  file            6291452 0       -2
<SWAPS>;
while (my $line = <SWAPS>) {
  my @line = split(/\s+/, $line);
  my $v = $line[0] . ' ' . $line[1] . '  ' . $line[2];
  print qq{$now,$hostname,$item_type,$v,1,""\n};
}
close(SWAPS);


# NICs
# ifconfig -a
# ip link show
# ip addr show?
# netstat -i
$item_type = 'NIC (netstat)';
open(NETSTAT, "/bin/netstat -i|") or die;
<NETSTAT>;
<NETSTAT>;
while (my $line = <NETSTAT>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 # $line =~ s/\s+/ /g;
 my @line = split(/\s+/, $line);
 my $nic = $line[0];
 print qq{$now,$hostname,$item_type,$nic,1,""\n};
}
close(NETSTAT);
$item_type = 'NIC (link)';
open(IP, "/sbin/ip link show|") or die;
# 1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN
#     link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
# 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP qlen 1000
#     link/ether 00:50:56:a0:72:76 brd ff:ff:ff:ff:ff:ff
while (my $line = <IP>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 # $line =~ s/\s+/ /g;
 my $line2 = <IP>;
 $line2 =~ s/^\s+//;
 $line2 =~ s/\s+$//;
 $line .= ' ' . $line2;
 my @line = split(/\s+/, $line);
 my $nic = $line[1];
 $nic =~ s/:$//;
 my $linktype = '';
 my $mac_addr = '';
 foreach my $linkprop (@line) {
  if ($linkprop =~ /link\//) { $linktype = $linkprop; }
  # last - assumes the mac address comes before the broadcast address
  if ($linktype =~ /ether/ && $linkprop =~ /[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}/) { $mac_addr = $linkprop; last; }
 }
 my $v = $nic;
 if (length($linktype) > 0) { $v .= ' ' . $linktype; }
 if (length($mac_addr) > 0) { $v .= ' ' . $mac_addr; }
 print qq{$now,$hostname,$item_type,$v,1,"$line"\n};
}
close(IP);

# IP addrs
# ip addr show
# hostname -I
$item_type = 'IPaddr';
my $ipaddrs = `/bin/hostname -I`;
chomp($ipaddrs);
my @ipaddrs = split(/\s+/, $ipaddrs);
foreach my $k (sort @ipaddrs) {
 print qq{$now,$hostname,$item_type,$k,1,""\n};
}


# IP routes
# ip route
# netstat -r
$item_type = 'IP_default_gw';
open(IP, "/sbin/ip route|") or die;
# 10.89.128.0/23 dev eth0  proto kernel  scope link  src 10.89.128.55
# 169.254.0.0/16 dev eth0  scope link  metric 1002
# default via 10.89.128.1 dev eth0
my $IP_default_gw = 'NA';
while (my $line = <IP>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 if ($line !~ /default/) { next; }
 my @line = split(/\s+/, $line);
 $IP_default_gw = $line[2];
}
close(IP);
print qq{$now,$hostname,$item_type,$IP_default_gw,1,""\n};

# processes sorted by processor time, memory, swap, open files?
# https://serverfault.com/questions/27887/how-to-sort-ps-output-by-process-start-time
# ps -ef --sort=start_time
# ps aux --sort=start_time
# ps -e -o user,cputime,args --sort -utime
$item_type = 'ps (cputime)';
open(PS, "/bin/ps -e -o user,cputime,args --sort -utime|") or die;
<PS>;
my $max_ps_cputime = 20;
my $ps_i = 0;
# root     10:08:33 java -Xmx128...
while (my $line = <PS>) {
 $line =~ s/^\s+//;
 $line =~ s/\s+$//;
 my @line = split(/\s+/, $line, 3);
 my $user = $line[0];
 my $cputime = $line[1];
 my $args0 = $line[2];
 my $args = args_shortname($line[2]);
 my $v = qq{$user $cputime $args};
 print qq{$now,$hostname,$item_type,$v,1,"$args0"\n};
 $ps_i++;
 if ($ps_i >= $max_ps_cputime) { last; }
}
close(PS);

sub args_shortname {
 my $args = shift;
 if ($args =~ /\/opt\/NetApp\/smsap/) { $args = '[smsap_server]'; }
 if ($args =~ /org.apache.catalina.startup.Bootstrap/) { $args = '[tomcat]'; }
 if ($args =~ /\/usr\/sap\/.+exe\/jlaunch/) {
  # /usr/sap/DEP/JC41/exe/jlaunch pf=/usr/sap/DEP/SYS/profile/DEP_JC41_otho -DSAPINFO=DEP_41_server -nodeId=1 -file=/usr/sap/DEP/JC41/j2ee/cluster/instance.properties -syncSem=16842865 -nodeName=ID417177550 -jvmOutFile=/usr/sap/DEP/JC41/work/jvm_server0.out -jvmOutMode=append -stdOutFile=/usr/sap/DEP/JC41/work/std_server0.out -stdOutMode=append -traceMode=append -locOutFile=/usr/sap/DEP/JC41/work/dev_server0 -mode=JCONTROL -debugMode=yes pf=/usr/sap/DEP/SYS/profile/DEP_JC41_otho
  my $shortname = 'jlaunch';
  if ($args =~ /-DSAPINFO=([^ ]+)/) { $shortname = $1; }
  $args = qq{[$shortname]};
 }
 if ($args =~ /(co|se|dw|en|ms)\.sap/) {
  my @args = split(/\s+/, $args);
  $args = '['.$args[0].']';
 }
 if ($args =~ /\/usr\/sap\/hostctrl\/exe\/saposcol/) { $args = '[saposcol]'; }
 if ($args =~ /\/exe\/sapstartsrv/) { $args = '[sapstartsrv]'; }
 if ($args =~ /\/exe\/igs/) {
  my @args = split(/\s+/, $args);
  my @comm = split(/\//, $args[0]);
  $args = '['.$comm[-1].']';
 }
 if ($args =~ /DAA_SMDA/) { $args = '[DAA]'; }
 $args;
}

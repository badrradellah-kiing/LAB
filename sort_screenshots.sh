#!/bin/bash
BASE="/home/badr/Desktop/Secure-Network-Lab-Doc/screenshots"
U="$BASE/Unsorted"

# Helper: move file to module folder
mv_to() {
  local file="$1"
  local dest="$2"
  [ -f "$U/$file" ] && mv "$U/$file" "$BASE/$dest/"
}

# ===== FILES TO DELETE (NOT LAB) =====
# Jul 7 = waydroid, android, gaming — NOT lab
rm -f "$U/Screenshot from 2026-07-07"*

# Jul 10 = PortSwigger Web Security Academy — different lab
rm -f "$U/Screenshot from 2026-07-10"*

# Jul 11 early = BurpSuite (00:27-00:58) — different lab  
rm -f "$U/Screenshot from 2026-07-11 00-27-11.png"
rm -f "$U/Screenshot from 2026-07-11 00-35-15.png"
rm -f "$U/Screenshot from 2026-07-11 00-46-26.png"
rm -f "$U/Screenshot from 2026-07-11 00-46-30.png"
rm -f "$U/Screenshot from 2026-07-11 00-47-43.png"
rm -f "$U/Screenshot from 2026-07-11 00-50-07.png"
rm -f "$U/Screenshot from 2026-07-11 00-52-01.png"
rm -f "$U/Screenshot from 2026-07-11 00-52-11.png"
rm -f "$U/Screenshot from 2026-07-11 00-57-33.png"
rm -f "$U/Screenshot from 2026-07-11 00-58-30.png"

# Jul 11 12:xx = not lab (browsing)
rm -f "$U/Screenshot from 2026-07-11 12-13-12.png"
rm -f "$U/Screenshot from 2026-07-11 12-18-38.png"

# Jul 15 12:49, 12:50, 12:52, 12:53 = StudyAssur/browsing — NOT lab
rm -f "$U/Screenshot from 2026-07-15 12-49-43.png"
rm -f "$U/Screenshot from 2026-07-15 12-50-37.png"
rm -f "$U/Screenshot from 2026-07-15 12-52-23.png"
rm -f "$U/Screenshot from 2026-07-15 12-53-57.png"

# Jul 15 13:00-13:08 = browsing, not lab
rm -f "$U/Screenshot from 2026-07-15 13-00-37.png"
rm -f "$U/Screenshot from 2026-07-15 13-02-10.png"
rm -f "$U/Screenshot from 2026-07-15 13-03-43.png"
rm -f "$U/Screenshot from 2026-07-15 13-04-35.png"
rm -f "$U/Screenshot from 2026-07-15 13-05-05.png"
rm -f "$U/Screenshot from 2026-07-15 13-06-12.png"
rm -f "$U/Screenshot from 2026-07-15 13-07-22.png"
rm -f "$U/Screenshot from 2026-07-15 13-08-34.png"
rm -f "$U/Screenshot from 2026-07-15 13-15-14.png"

# ===== MODULE 2: AD / Samba / Kerberos =====
# Jun 8: Install Ubuntu client VM + initial AD setup attempts
mv_to "Screenshot from 2026-06-08 19-57-58.png" "Module2-AD-Samba-Kerberos"  # Ubuntu install disk config
mv_to "Screenshot from 2026-06-08 19-59-12.png" "Module2-AD-Samba-Kerberos"  # Ubuntu create account
mv_to "Screenshot from 2026-06-08 19-59-18.png" "Module2-AD-Samba-Kerberos"  # Ubuntu create account (dupe check)
mv_to "Screenshot from 2026-06-08 20-44-54.png" "Module2-AD-Samba-Kerberos"  # ping lab.local + ip a (10.10.10.10)
mv_to "Screenshot from 2026-06-08 20-52-30.png" "Module2-AD-Samba-Kerberos"  # DNS resolv.conf 10.10.10.5 + ping
mv_to "Screenshot from 2026-06-08 20-55-32.png" "Module2-AD-Samba-Kerberos"  # dc-ipa: apt install samba krb5 winbind
mv_to "Screenshot from 2026-06-08 21-25-13.png" "Module2-AD-Samba-Kerberos"  # dc-ipa: samba processes, ss -tulnp DNS
mv_to "Screenshot from 2026-06-08 21-27-12.png" "Module2-AD-Samba-Kerberos"  # AD config continuation
mv_to "Screenshot from 2026-06-08 21-28-19.png" "Module2-AD-Samba-Kerberos"  # AD config
mv_to "Screenshot from 2026-06-08 21-30-04.png" "Module2-AD-Samba-Kerberos"  # realm join lab.local, resolv.conf
mv_to "Screenshot from 2026-06-08 21-35-42.png" "Module2-AD-Samba-Kerberos"  # realm join + DNS resolve
mv_to "Screenshot from 2026-06-08 21-35-53.png" "Module2-AD-Samba-Kerberos"  # DNS + realm
mv_to "Screenshot from 2026-06-08 21-46-57.png" "Module2-AD-Samba-Kerberos"  # apt errors (krb5, realmd)
mv_to "Screenshot from 2026-06-08 21-48-38.png" "Module2-AD-Samba-Kerberos"  # AD install
mv_to "Screenshot from 2026-06-08 21-49-53.png" "Module2-AD-Samba-Kerberos"  # AD install
mv_to "Screenshot from 2026-06-08 21-52-35.png" "Module2-AD-Samba-Kerberos"  # AD config
mv_to "Screenshot from 2026-06-08 21-56-04.png" "Module2-AD-Samba-Kerberos"  # AD config
mv_to "Screenshot from 2026-06-08 22-10-22.png" "Module2-AD-Samba-Kerberos"  # smb.conf / krb5
mv_to "Screenshot from 2026-06-08 22-17-44.png" "Module2-AD-Samba-Kerberos"  # smb.conf
mv_to "Screenshot from 2026-06-08 22-19-07.png" "Module2-AD-Samba-Kerberos"  # smb.conf
mv_to "Screenshot from 2026-06-08 22-20-39.png" "Module2-AD-Samba-Kerberos"  # smb.conf / net ads join
mv_to "Screenshot from 2026-06-08 22-48-49.png" "Module2-AD-Samba-Kerberos"  # apt update errors (normal - DNS issue)
mv_to "Screenshot from 2026-06-08 23-23-34.png" "Module2-AD-Samba-Kerberos"  # AD troubleshoot
mv_to "Screenshot from 2026-06-08 23-26-24.png" "Module2-AD-Samba-Kerberos"  # AD troubleshoot
mv_to "Screenshot from 2026-06-08 23-29-13.png" "Module2-AD-Samba-Kerberos"  # AD troubleshoot
mv_to "Screenshot from 2026-06-08 23-34-22.png" "Module2-AD-Samba-Kerberos"  # AD troubleshoot
mv_to "Screenshot from 2026-06-08 23-55-14.png" "Module2-AD-Samba-Kerberos"  # AD config
mv_to "Screenshot from 2026-06-09 00-00-25.png" "Module2-AD-Samba-Kerberos"  # net ads join attempts
mv_to "Screenshot from 2026-06-09 00-05-17.png" "Module2-AD-Samba-Kerberos"  # net ads join
mv_to "Screenshot from 2026-06-09 00-08-50.png" "Module2-AD-Samba-Kerberos"  # kinit / kerberos
mv_to "Screenshot from 2026-06-09 00-11-45.png" "Module2-AD-Samba-Kerberos"  # kinit / kerberos
mv_to "Screenshot from 2026-06-09 00-20-30.png" "Module2-AD-Samba-Kerberos"  # samba symlinks, net ads join
mv_to "Screenshot from 2026-06-09 00-23-44.png" "Module2-AD-Samba-Kerberos"  # AD join
mv_to "Screenshot from 2026-06-09 00-32-27.png" "Module2-AD-Samba-Kerberos"  # winbind config
mv_to "Screenshot from 2026-06-09 00-34-50.png" "Module2-AD-Samba-Kerberos"  # winbind
mv_to "Screenshot from 2026-06-09 00-35-48.png" "Module2-AD-Samba-Kerberos"  # winbind
mv_to "Screenshot from 2026-06-09 00-39-33.png" "Module2-AD-Samba-Kerberos"  # wbinfo
mv_to "Screenshot from 2026-06-09 00-43-05.png" "Module2-AD-Samba-Kerberos"  # wbinfo
mv_to "Screenshot from 2026-06-09 00-44-13.png" "Module2-AD-Samba-Kerberos"  # getent passwd
mv_to "Screenshot from 2026-06-09 00-45-39.png" "Module2-AD-Samba-Kerberos"  # getent passwd
mv_to "Screenshot from 2026-06-09 12-01-01.png" "Module2-AD-Samba-Kerberos"  # smb.conf options
mv_to "Screenshot from 2026-06-09 12-01-54.png" "Module2-AD-Samba-Kerberos"  # smb.conf
mv_to "Screenshot from 2026-06-09 12-03-39.png" "Module2-AD-Samba-Kerberos"  # smb.conf
mv_to "Screenshot from 2026-06-09 12-46-51.png" "Module2-AD-Samba-Kerberos"  # nsswitch + getent
mv_to "Screenshot from 2026-06-09 12-48-01.png" "Module2-AD-Samba-Kerberos"  # nsswitch
mv_to "Screenshot from 2026-06-09 12-49-22.png" "Module2-AD-Samba-Kerberos"  # getent
mv_to "Screenshot from 2026-06-09 12-50-05.png" "Module2-AD-Samba-Kerberos"  # getent
mv_to "Screenshot from 2026-06-09 12-51-38.png" "Module2-AD-Samba-Kerberos"  # rm secrets.tdb + restart
mv_to "Screenshot from 2026-06-09 12-52-41.png" "Module2-AD-Samba-Kerberos"  # winbind restart
mv_to "Screenshot from 2026-06-09 12-56-48.png" "Module2-AD-Samba-Kerberos"  # wbinfo validation
mv_to "Screenshot from 2026-06-09 12-57-29.png" "Module2-AD-Samba-Kerberos"  # wbinfo
mv_to "Screenshot from 2026-06-09 12-58-40.png" "Module2-AD-Samba-Kerberos"  # getent final
mv_to "Screenshot from 2026-06-09 12-59-59.png" "Module2-AD-Samba-Kerberos"  # getent final
mv_to "Screenshot from 2026-06-09 13-01-19.png" "Module2-AD-Samba-Kerberos"  # smb.conf template shell

# ===== RBAC / PAM =====
mv_to "Screenshot from 2026-06-09 13-03-28.png" "RBAC-PAM"   # getent passwd all (before RBAC)
mv_to "Screenshot from 2026-06-09 13-03-33.png" "RBAC-PAM"   # getent passwd all
mv_to "Screenshot from 2026-06-09 13-03-39.png" "RBAC-PAM"   # getent passwd all
mv_to "Screenshot from 2026-06-09 13-05-51.png" "RBAC-PAM"   # samba-tool create testadmin
mv_to "Screenshot from 2026-06-09 13-07-34.png" "RBAC-PAM"   # getent + smb.conf + id testadmin + visudo + su testadmin
mv_to "Screenshot from 2026-06-09 13-09-00.png" "RBAC-PAM"   # RBAC validation
mv_to "Screenshot from 2026-06-09 15-56-56.png" "RBAC-PAM"   # id testadmin + su testadmin SUCCESS

# ===== MODULE 1: Firewall pfSense =====
mv_to "Screenshot from 2026-07-11 16-32-55.png" "Module1-Firewall-pfSense"  # pfSense console: WAN/LAN/DMZ
mv_to "Screenshot from 2026-07-11 16-43-57.png" "Module1-Firewall-pfSense"  # pfSense GUI
mv_to "Screenshot from 2026-07-11 16-45-17.png" "Module1-Firewall-pfSense"  # pfSense rules LAN
mv_to "Screenshot from 2026-07-11 16-46-03.png" "Module1-Firewall-pfSense"  # pfSense rules
mv_to "Screenshot from 2026-07-11 16-46-49.png" "Module1-Firewall-pfSense"  # pfSense rules
mv_to "Screenshot from 2026-07-11 16-41-20.png" "Module1-Firewall-pfSense"  # pfSense GUI access from VM

# ===== MODULE 4: Proxy Squid =====
# Jul 11: VBox manager + proxy-squid install
mv_to "Screenshot from 2026-07-11 15-19-07.png" "Module4-Proxy-Squid"  # VBox Manager: all VMs listed
mv_to "Screenshot from 2026-07-11 15-42-21.png" "Module4-Proxy-Squid"  # Ubuntu Server install: network config 10.10.10.20
mv_to "Screenshot from 2026-07-11 15-44-48.png" "Module4-Proxy-Squid"  # Ubuntu Server install
mv_to "Screenshot from 2026-07-11 15-45-16.png" "Module4-Proxy-Squid"  # Ubuntu Server install
mv_to "Screenshot from 2026-07-11 15-46-02.png" "Module4-Proxy-Squid"  # Ubuntu Server install
mv_to "Screenshot from 2026-07-11 15-59-08.png" "Module4-Proxy-Squid"  # Ubuntu Server installation progress
mv_to "Screenshot from 2026-07-11 16-01-55.png" "Module4-Proxy-Squid"  # Ubuntu Server install complete
mv_to "Screenshot from 2026-07-11 16-10-37.png" "Module4-Proxy-Squid"  # proxy-squid install progress
mv_to "Screenshot from 2026-07-11 16-25-23.png" "Module4-Proxy-Squid"  # proxy-squid first boot 10.10.10.20
mv_to "Screenshot from 2026-07-11 16-27-19.png" "Module4-Proxy-Squid"  # proxy-squid config
mv_to "Screenshot from 2026-07-11 16-27-26.png" "Module4-Proxy-Squid"  # proxy-squid config
mv_to "Screenshot from 2026-07-11 16-28-56.png" "Module4-Proxy-Squid"  # proxy-squid config
mv_to "Screenshot from 2026-07-12 02-17-00.png" "Module4-Proxy-Squid"  # apt install squid + squid.conf
mv_to "Screenshot from 2026-07-12 02-34-23.png" "Module4-Proxy-Squid"  # squid config
mv_to "Screenshot from 2026-07-12 02-43-05.png" "Module4-Proxy-Squid"  # squid config
mv_to "Screenshot from 2026-07-12 03-22-07.png" "Module4-Proxy-Squid"  # lan-client: DNS 10.10.10.5 + squid logs
mv_to "Screenshot from 2026-07-12 03-22-27.png" "Module4-Proxy-Squid"  # proxy test
mv_to "Screenshot from 2026-07-12 03-24-23.png" "Module4-Proxy-Squid"  # proxy test
mv_to "Screenshot from 2026-07-12 04-18-08.png" "Module4-Proxy-Squid"  # Squid 403 Forbidden + ERR_ACCESS_DENIED
mv_to "Screenshot from 2026-07-12 04-18-59.png" "Module4-Proxy-Squid"  # proxy test  
mv_to "Screenshot from 2026-07-12 04-20-17.png" "Module4-Proxy-Squid"  # proxy config
mv_to "Screenshot from 2026-07-12 04-22-43.png" "Module4-Proxy-Squid"  # proxy config
mv_to "Screenshot from 2026-07-12 04-25-45.png" "Module4-Proxy-Squid"  # proxy logs
mv_to "Screenshot from 2026-07-12 04-26-23.png" "Module4-Proxy-Squid"  # proxy logs
mv_to "Screenshot from 2026-07-12 04-26-59.png" "Module4-Proxy-Squid"  # proxy logs
mv_to "Screenshot from 2026-07-12 04-37-56.png" "Module4-Proxy-Squid"  # proxy logs
mv_to "Screenshot from 2026-07-12 04-42-54.png" "Module4-Proxy-Squid"  # proxy working
mv_to "Screenshot from 2026-07-12 04-47-02.png" "Module4-Proxy-Squid"  # proxy working
mv_to "Screenshot from 2026-07-12 04-48-15.png" "Module4-Proxy-Squid"  # proxy working
mv_to "Screenshot from 2026-07-16 13-21-21.png" "Module4-Proxy-Squid"  # squid.conf with blocked_sites ACL
mv_to "Screenshot from 2026-07-16 13-38-37.png" "Module4-Proxy-Squid"  # squid config
mv_to "Screenshot from 2026-07-16 13-39-40.png" "Module4-Proxy-Squid"  # squid config
mv_to "Screenshot from 2026-07-16 13-54-58.png" "Module4-Proxy-Squid"  # squid config / test
mv_to "Screenshot from 2026-07-16 13-58-57.png" "Module4-Proxy-Squid"  # squid test
mv_to "Screenshot from 2026-07-16 14-00-45.png" "Module4-Proxy-Squid"  # squid test
mv_to "Screenshot from 2026-07-16 14-02-09.png" "Module4-Proxy-Squid"  # squid test
mv_to "Screenshot from 2026-07-16 14-14-24.png" "Module4-Proxy-Squid"  # squid transparent or advanced

# ===== MODULE 4: Proxy Auth AD =====
mv_to "Screenshot from 2026-07-16 15-21-51.png" "Module4-Proxy-Auth-AD"  # squid.conf with kerberos auth
mv_to "Screenshot from 2026-07-16 15-23-14.png" "Module4-Proxy-Auth-AD"  # proxy auth
mv_to "Screenshot from 2026-07-16 15-24-50.png" "Module4-Proxy-Auth-AD"  # proxy auth

# ===== NETWORK DIAGNOSTICS =====
mv_to "Screenshot from 2026-07-12 03-03-46.png" "Network-Diagnostics"  # lan-client: ip a, ping 10.10.10.1, ping 1.1.1.1
mv_to "Screenshot from 2026-07-12 13-30-43.png" "Network-Diagnostics"  # network diag
mv_to "Screenshot from 2026-07-12 13-34-39.png" "Network-Diagnostics"  # network diag
mv_to "Screenshot from 2026-07-12 15-30-03.png" "Network-Diagnostics"  # dc login, ss -tulnp :53

# ===== MODULE 3: DMZ / Nginx =====
mv_to "Screenshot from 2026-07-12 15-33-16.png" "Module3-DMZ-Nginx"  # DMZ related
mv_to "Screenshot from 2026-07-12 15-36-55.png" "Module3-DMZ-Nginx"  # nginx/DMZ
mv_to "Screenshot from 2026-07-12 15-39-10.png" "Module3-DMZ-Nginx"  # nginx/DMZ
mv_to "Screenshot from 2026-07-12 15-41-40.png" "Module3-DMZ-Nginx"  # nginx/DMZ
mv_to "Screenshot from 2026-07-12 15-44-02.png" "Module3-DMZ-Nginx"  # nginx/DMZ
mv_to "Screenshot from 2026-07-12 15-44-28.png" "Module3-DMZ-Nginx"  # nginx/DMZ
mv_to "Screenshot from 2026-07-12 15-48-23.png" "Module3-DMZ-Nginx"  # nginx/DMZ
mv_to "Screenshot from 2026-07-12 15-58-26.png" "Module3-DMZ-Nginx"  # nginx config
mv_to "Screenshot from 2026-07-12 16-00-03.png" "Module3-DMZ-Nginx"  # nginx config  
mv_to "Screenshot from 2026-07-12 16-02-56.png" "Module3-DMZ-Nginx"  # nginx config
mv_to "Screenshot from 2026-07-12 16-09-53.png" "Module3-DMZ-Nginx"  # nginx validation
mv_to "Screenshot from 2026-07-12 16-11-21.png" "Module3-DMZ-Nginx"  # nginx validation

# ===== MODULE 2 (additional): AD from Jul 15-16 =====
mv_to "Screenshot from 2026-07-15 12-13-33.png" "Module2-AD-Samba-Kerberos"  # AD re-join session
mv_to "Screenshot from 2026-07-15 12-18-08.png" "Module2-AD-Samba-Kerberos"  # AD re-join
mv_to "Screenshot from 2026-07-15 12-21-51.png" "Module2-AD-Samba-Kerberos"  # AD re-join
mv_to "Screenshot from 2026-07-16 00-32-37.png" "Module2-AD-Samba-Kerberos"  # AD session
mv_to "Screenshot from 2026-07-16 00-36-33.png" "Module2-AD-Samba-Kerberos"  # AD session
mv_to "Screenshot from 2026-07-16 05-38-21.png" "Module2-AD-Samba-Kerberos"  # AD session
mv_to "Screenshot from 2026-07-16 14-17-10.png" "Module2-AD-Samba-Kerberos"  # lan-client: jdoe@lab.local, su
mv_to "Screenshot from 2026-07-16 14-18-56.png" "Module2-AD-Samba-Kerberos"  # AD user test
mv_to "Screenshot from 2026-07-16 14-20-51.png" "Module2-AD-Samba-Kerberos"  # AD user test

# ===== MODULE 5: VPN =====
mv_to "Screenshot from 2026-07-16 15-03-42.png" "Module5-VPN"  # VPN config
mv_to "Screenshot from 2026-07-16 15-04-37.png" "Module5-VPN"  # VPN config
mv_to "Screenshot from 2026-07-16 15-09-41.png" "Module5-VPN"  # VPN config
mv_to "Screenshot from 2026-07-16 15-09-55.png" "Module5-VPN"  # VPN config
mv_to "Screenshot from 2026-07-16 15-11-44.png" "Module5-VPN"  # VPN config
mv_to "Screenshot from 2026-07-16 15-27-22.png" "Module5-VPN"  # VPN config
mv_to "Screenshot from 2026-07-16 15-30-23.png" "Module5-VPN"  # VPN config
mv_to "Screenshot from 2026-07-16 15-32-53.png" "Module5-VPN"  # OpenVPN service interface
mv_to "Screenshot from 2026-07-16 15-33-39.png" "Module5-VPN"  # VPN validation
mv_to "Screenshot from 2026-07-16 15-34-48.png" "Module5-VPN"  # VPN tunnel successful
mv_to "Screenshot from 2026-07-16 15-39-03.png" "Module5-VPN"  # pfSense WireGuard interface

echo "=== Sorting complete ==="
echo "Remaining unsorted files:"
ls "$U" 2>/dev/null | wc -l

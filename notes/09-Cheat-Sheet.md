# 📋 Cheat Sheet — Commandes Essentielles du Lab

## 🔑 Kerberos (Authentification)

```bash
kinit Administrator@LAB.LOCAL

klist
```

## 🌉 Winbind (Pont AD ↔ Linux)

```bash
wbinfo -t

wbinfo -u

wbinfo --online
```

## 🐧 Validation NSS (Système Linux)

```bash
getent passwd administrator

id administrator
```

## 🔗 Administration Domaine (Samba-Tool)

```bash
sudo net ads join -U Administrator -S 10.10.10.5

sudo net ads changetrustpw

sudo samba-tool user create <username>

sudo samba-tool group addmembers '<group name>' <username>

sudo samba-tool user setpassword Administrator --newpassword=<password>
```

## 🌐 Diagnostic Réseau

```bash
ss -tulnp

ip route get 1.1.1.1

ip link show

ip addr show

ip route show

dig google.com

dig @8.8.8.8 google.com
```

## 🦑 Proxy Squid

```bash
sudo systemctl restart squid

sudo squid -k parse

sudo tail -f /var/log/squid/access.log

sudo awk '{print $7}' /var/log/squid/access.log | sort | uniq -c | sort -rn | head

sudo grep '10.10.10.10' /var/log/squid/access.log
```

## 🕸️ Nginx (Reverse Proxy)

```bash
sudo nginx -t

sudo systemctl reload nginx

sudo ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
```

## ⏰ Gestion du temps (Critique pour Kerberos !)

```bash
sudo timedatectl set-ntp no
sudo timedatectl set-time "12:45:00"

date
timedatectl
```

## 🔧 Services Samba/Winbind

```bash
sudo systemctl enable smbd winbind
sudo systemctl restart smbd winbind

sudo rm -f /var/lib/samba/private/secrets.tdb
```

## 🧹 DNS (Résolution de noms)

```bash
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

sudo bash -c 'echo "nameserver 10.10.10.5" > /etc/resolv.conf'
```

## 🔐 SSL / Certificats (SSL Bump)

```bash
sudo openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -keyout /etc/squid/bump.key -out /etc/squid/bump.crt \
  -subj "/CN=Lab Squid Proxy CA"

sudo /usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 4MB
sudo chown -R proxy:proxy /var/lib/squid/ssl_db
```

## 🛡️ RBAC & PAM

```bash
sudo visudo

```

## 🔒 VPN WireGuard

```bash
```

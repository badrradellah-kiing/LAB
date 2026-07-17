# 📋 Cheat Sheet — Commandes Essentielles du Lab

## 🔑 Kerberos (Authentification)

```bash
# Demander un ticket (TGT) — teste le mot de passe AD
kinit Administrator@LAB.LOCAL

# Lister les tickets en cache
klist
```

## 🌉 Winbind (Pont AD ↔ Linux)

```bash
# Tester le canal sécurisé (secret de confiance RPC)
wbinfo -t

# Lister tous les utilisateurs de l'AD
wbinfo -u

# Forcer la synchronisation en ligne avec le DC
wbinfo --online
```

## 🐧 Validation NSS (Système Linux)

```bash
# Vérifier le mapping utilisateur AD → UID/GID/Shell
getent passwd administrator

# Afficher les groupes AD d'un utilisateur
id administrator
```

## 🔗 Administration Domaine (Samba-Tool)

```bash
# Joindre la machine au domaine AD
sudo net ads join -U Administrator -S 10.10.10.5

# Réinitialiser le mot de passe machine (trust account)
sudo net ads changetrustpw

# Créer un utilisateur sur le DC
sudo samba-tool user create <username>

# Ajouter un utilisateur à un groupe
sudo samba-tool group addmembers '<group name>' <username>

# Changer le mot de passe admin
sudo samba-tool user setpassword Administrator --newpassword=<password>
```

## 🌐 Diagnostic Réseau

```bash
# Ports ouverts (liste complète)
ss -tulnp

# Route vers une IP spécifique
ip route get 1.1.1.1

# Carte réseau active (couche 1-2 : Physique + Liaison)
ip link show

# Adresse IP attribuée (couche 3 : Réseau)
ip addr show

# Table de routage complète
ip route show

# Test DNS (utilise le serveur de /etc/resolv.conf)
dig google.com

# Test DNS en forçant un serveur spécifique
dig @8.8.8.8 google.com
```

## 🦑 Proxy Squid

```bash
# Redémarrer Squid
sudo systemctl restart squid

# Valider la syntaxe de la configuration
sudo squid -k parse

# Voir les derniers logs en temps réel
sudo tail -f /var/log/squid/access.log

# Top 10 URLs les plus visitées
sudo awk '{print $7}' /var/log/squid/access.log | sort | uniq -c | sort -rn | head

# Filtrer par IP (investiguer une machine suspecte)
sudo grep '10.10.10.10' /var/log/squid/access.log
```

## 🕸️ Nginx (Reverse Proxy)

```bash
# Tester la syntaxe de configuration
sudo nginx -t

# Recharger sans arrêter le service
sudo systemctl reload nginx

# Créer un lien symbolique pour activer un site
sudo ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/
```

## ⏰ Gestion du temps (Critique pour Kerberos !)

```bash
# Désactiver NTP et forcer l'heure manuellement
sudo timedatectl set-ntp no
sudo timedatectl set-time "12:45:00"

# Vérifier l'heure actuelle
date
timedatectl
```

## 🔧 Services Samba/Winbind

```bash
# Activer et démarrer les services au boot
sudo systemctl enable smbd winbind
sudo systemctl restart smbd winbind

# Purger les secrets corrompus (reset du trust)
sudo rm -f /var/lib/samba/private/secrets.tdb
```

## 🧹 DNS (Résolution de noms)

```bash
# Forcer un DNS temporaire (Google, pour Internet)
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

# Remettre le DNS du DC (pour le domaine AD)
sudo bash -c 'echo "nameserver 10.10.10.5" > /etc/resolv.conf'
```

## 🔐 SSL / Certificats (SSL Bump)

```bash
# Générer la CA maître pour le SSL Bump
sudo openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -keyout /etc/squid/bump.key -out /etc/squid/bump.crt \
  -subj "/CN=Lab Squid Proxy CA"

# Initialiser la base de données de certificats
sudo /usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 4MB
sudo chown -R proxy:proxy /var/lib/squid/ssl_db
```

## 🛡️ RBAC & PAM

```bash
# Éditer le fichier sudoers de manière sécurisée
sudo visudo
# → Ajouter : %domain\ admins ALL=(ALL:ALL) ALL

# Bloquer su pour les non-membres du groupe sudo
# Dans /etc/pam.d/su :
# auth required pam_wheel.so group=sudo
```

## 🔒 VPN WireGuard

```bash
# (Dans pfSense GUI : VPN > WireGuard > Tunnels)
# Port par défaut : 51820
# Interface : tun_wg0
```

# 🔥 Module 1 : Firewall pfSense

## L'idée de base

Le **firewall** est le **premier élément** qu'on installe dans un réseau — avant même les clients.  
Il gère le DHCP, impose les règles de trafic, et dicte les "lois" du réseau à chaque machine qui s'y connecte.

> En activant le DHCP sur pfSense, dès qu'une VM est créée et connectée au réseau interne, elle reçoit automatiquement une adresse IP et se soumet aux règles du firewall.

---

## Comment j'ai configuré ça des interfaces

Le pfSense possède **3 cartes réseau** (interfaces) :

| Interface | Rôle | Adresse IP | Réseau |
|-----------|------|-----------|--------|
| `em0` (WAN) | Internet (NAT) | `10.0.2.15/24` (DHCP) | Accès Internet sortant |
| `em1` (LAN) | Réseau local interne | `10.10.10.1/24` | Machines internes |
| `em2` (DMZ) | Zone démilitarisée | `10.10.30.1/24` | Serveur web isolé |

### Console pfSense au démarrage

![Console pfSense — 3 interfaces WAN/LAN/DMZ](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-07-11%2016-32-55.png)

> On voit les 3 interfaces assignées : **WAN** (em0, DHCP), **LAN** (em1, `10.10.10.1/24`), **DMZ** (opt1/em2, `10.10.30.1/24`). Le menu console permet l'administration de base.

### Interface Assignments dans le Web Configurateur

![pfSense — Interface Assignments WAN/LAN/DMZ](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-07-16%2015-33-39.png)

> Les 3 cartes réseau sont bien assignées dans le GUI pfSense : **WAN** → em0, **LAN** → em1, **DMZ** → em2. Chacune avec sa propre adresse MAC.

---

## Web Configurateur

- Le GUI d'administration pfSense est accessible via HTTP ou HTTPS
- En lab : `http://10.10.10.1` (plus simple)
- En production : **toujours HTTPS** !

---

## Règles de Firewall

### ⚠️ L'ordre des règles = question de vie ou de mort

> **Le piège classique en production :** Si tu places une règle générique *"Autoriser tout le monde"* à la ligne 2, et une règle restrictive *"Bloquer la DMZ vers le LAN"* à la ligne 5, la règle restrictive ne sera **jamais** lue. pfSense lit les règles **de haut en bas** et s'arrête à la première qui matche.

### Création d'un Alias (ex: AD_DC)

Dans pfSense, il est fortement recommandé d'utiliser des **Aliases** plutôt que des IP brutes. Cela rend les règles lisibles.

![pfSense — Création Alias AD_DC](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-06-15%2017-48-11.png)

> Création d'un Alias nommé **AD_DC** pour l'IP `10.10.10.5` (notre contrôleur de domaine Samba/Kerberos).

### Règles LAN créées dans le lab

![pfSense — Règles LAN](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-07-11%2016-43-57.png)

> Les règles LAN en place :
> 1. **Anti-Lockout Rule** — Empêche de se bloquer soi-même hors du GUI
> 2. **LAN vers WEB** (TCP, ports 80-443) — Autorise la navigation web depuis le LAN
> 3. **LAN vers DNS ok** (UDP, port 53 → AD_DC) — Autorise les requêtes DNS vers le DC

### Ajout d'une nouvelle règle + Apply Changes

![pfSense — Ajout de règle et application](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-07-11%2016-45-17.png)

![pfSense — Vue des règles LAN vers WEB et DNS](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-06-15%2019-07-31.png)

> Après ajout d'une règle, pfSense affiche un bandeau "Apply Changes" pour recharger les filtres.

![pfSense — Règles appliquées avec succès](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-07-11%2016-46-03.png)

> Confirmation : *"The changes have been applied successfully. The firewall rules are now reloading in the background."*

### Récapitulatif des règles créées

| # | Direction | Action | Description |
|---|-----------|--------|-------------|
| 1 | LAN → Any | ✅ Allow | Autoriser le trafic sortant depuis le LAN |
| 2 | DMZ → WAN | ✅ Allow | Autoriser la DMZ à accéder à Internet |
| 3 | DMZ → LAN | ❌ Block | **Bloquer** la DMZ vers le LAN (isolation) |
| 4 | WAN → DMZ (port 80) | ✅ Allow | Port forwarding / DNAT vers Nginx |

### Invert Match

- Dans pfSense, **"invert match"** = **tous SAUF cette adresse**

![pfSense — Configuration Invert Match LAN Address](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-06-15%2019-10-58.png)

- Utilisé pour le proxy transparent : redirect port 80 **sauf** le trafic destiné à pfSense lui-même (pour éviter la **boucle infinie**)

---

## Commandes réseau de diagnostic

```bash
# Voir les ports ouverts sur la machine
ss -tulnp

# Quel chemin le noyau prend pour atteindre une IP
ip route get 1.1.1.1

# Vérifier que la carte réseau est UP (Couche 1-2 : Physique + Liaison)
ip link show

# Vérifier l'adresse IP (Couche 3 : Réseau)
ip addr show

# Table de routage (passerelle par défaut / default gateway)
ip route show

# Test DNS avec le serveur configuré dans /etc/resolv.conf
dig google.com

# Test DNS en forçant un serveur spécifique (ignore la config locale)
dig @8.8.8.8 google.com
```

---

## VLAN (optionnel)

```bash
# Créer un VLAN
sudo ip link add link eth0 name eth0.30 type vlan id 30

# Attribuer une IP à un VLAN
sudo ip addr add 192.168.10.1/24 dev eth0.10
```

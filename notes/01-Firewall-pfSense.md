# 🔥 Module 1 : Firewall pfSense

## L'idée de base

First of all, dans un système le premier truc qu'on crée c'est le firewall, avant même les clients. 
Comme ça par exemple, on active le DHCP direct dessus, et une fois qu'une nouvelle machine est créée, elle chope son IP toute seule, et surtout elle prend direct les lois du firewall.

---

## Configuration des interfaces

D’abord dans la config de pfSense, j'ai mis 3 cartes réseaux (le minimum syndical pour faire une DMZ plus tard) :

| Interface | Rôle | Adresse IP | Réseau |
|-----------|------|-----------|--------|
| `em0` (WAN) | Internet (NAT) | `10.0.2.15/24` (DHCP) | Accès Internet sortant |
| `em1` (LAN) | Réseau local interne | `10.10.10.1/24` | Machines internes |
| `em2` (DMZ) | Zone démilitarisée | `10.10.30.1/24` | serveur web isolé |

### Console pfSense au démarrage

![Console pfSense — 3 interfaces WAN/LAN/DMZ](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-07-11%2016-32-55.png)

> On voit les 3 interfaces assignées : **WAN** (em0, DHCP), **LAN** (em1, `10.10.10.1/24`), **DMZ** (opt1/em2, `10.10.30.1/24`). Le menu console permet l'administration de base.

### Interface Assignments dans le Web Configurateur

![pfSense — Interface Assignments WAN/LAN/DMZ](../screenshots/Module1-Firewall-pfSense/Screenshot%20from%202026-07-16%2015-33-39.png)

> Les 3 cartes réseau sont bien assignées dans le GUI pfSense : **WAN** → em0, **LAN** → em1, **DMZ** → em2. Chacune avec sa propre adresse MAC.

---

## Web Configurateur

Le webconfigurateur du firewall permet d’utiliser un GUI pour administrer pfSense. 
On peut utiliser http ou https pour le faire. J'ai pris HTTP parce que c'est plus simple en lab, mais en prod c'est HTTPS obligé !

---

## Règles de Firewall

### ⚠️ Attention à l'ordre des règles !

Petit rappel pour pas se faire avoir : pfSense lit les règles de haut en bas et s'arrête à la première qui matche.
Si on met "Allow All" en haut, les règles "Block" en bas serviront à rien.

### Création d'un Alias (ex: AD_DC)

C'est beaucoup plus propre de créer des "Alias" au lieu de taper des IP brutes partout.

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
# Voir les ports ouverts sur la VM
ss -tulnp

# Quel chemin le noyau prend pour atteindre une IP
ip route get 1.1.1.1

# Vérifier que la carte réseau est UP (Couche 1-2 : Physique + Liaison)
ip link show

# Vérifier l'adresse IP (Couche 3 : Réseau)
ip addr show

# Table de routage (passerelle par défaut (de base) / default gateway)
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

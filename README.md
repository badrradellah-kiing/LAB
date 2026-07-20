# 🔐 Secure Network Engineering Lab

Un lab de sécurité réseau construit de A à Z dans des VMs isolées :
réseau segmenté, firewall, proxies, VPN, IDS/IPS, durcissement,
cloud, PKI, conteneurs, et exercices attaque/défense. Chaque
contrôle défensif est testé en l'attaquant soi-même.

> ⚠️ **Usage lab uniquement.** Tous les outils offensifs ne visent
> que des machines que je possède, sur un réseau isolé d'Internet.

## Architecture

Réseau segmenté autour d'un firewall pfSense, avec trois zones ;
le trafic entre zones passe obligatoirement par le firewall.

| Segment | Réseau | Machines |
|---------|--------|----------|
| WAN | NAT Network | kali (attaquant) |
| LAN | 10.10.10.0/24 | dc-ipa, lan-client, proxy-squid |
| DMZ | 10.10.30.0/24 | web-dmz, ids-sensor |

## Documentation

Le détail de chaque module (commandes, pièges rencontrés, solutions)
est dans le dossier [`notes/`](./notes).

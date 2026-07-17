# 🔐 Mon Secure Network Lab — Le carnet de bord

> **Par :** Badr (aka le gars qui monte des infras from scratch)  
> **Mission :** Construire un réseau d'entreprise ultra-sécurisé de A à Z (Firewall, AD, Proxy, VPN).  
> **Statut :** En plein dedans (j'en suis au VPN)  
> **Hyperviseur :** Oracle VirtualBox

---

## 📁 Structure du Répertoire

```
Secure-Network-Lab-Doc/
├── notes/
│   ├── 00-README.md              ← Ce fichier
│   ├── 01-Firewall-pfSense.md    ← Config pfSense, WAN/LAN/DMZ, DHCP, règles
│   ├── 02-AD-Samba-Kerberos.md   ← Active Directory, DNS, Kerberos, Jonction
│   ├── 03-DMZ-Nginx.md           ← DMZ, Nginx, Port Forwarding, Reverse Proxy
│   ├── 04-Proxy-Squid.md         ← Forward/Transparent Proxy, Filtrage, Logs
│   ├── 05-SSL-Bump.md            ← Interception HTTPS, CA, certificats
│   ├── 06-Proxy-Auth-AD.md       ← Authentification proxy via AD/Kerberos
│   ├── 07-RBAC-PAM.md            ← Contrôle d'accès, sudoers, PAM
│   ├── 08-VPN.md                 ← VPN WireGuard (module en cours)
│   └── 09-Cheat-Sheet.md         ← Commandes essentielles de référence
├── screenshots/                  ← Captures d'écran par module
│   ├── Module1-Firewall-pfSense/
│   ├── Module2-AD-Samba-Kerberos/
│   ├── Module3-DMZ-Nginx/
│   ├── Module4-Proxy-Squid/
│   ├── Module4-Proxy-Auth-AD/
│   ├── Module4-SSL-Bump/
│   ├── Module5-VPN/
│   ├── Network-Diagnostics/
│   └── RBAC-PAM/
└── pdfs/                         ← PDFs de référence du lab
```

---

## 🏗️ Architecture du Lab

```
                        ┌──────────────────────┐
                        │      INTERNET         │
                        │    (WAN / NAT)        │
                        └──────────┬───────────┘
                                   │
                        ┌──────────┴───────────┐
                        │      pfSense          │
                        │    (Firewall)         │
                        │  em0 = WAN (DHCP)     │
                        │  em1 = LAN 10.10.10.1 │
                        │  em2 = DMZ 10.10.30.1 │
                        └──┬─────────┬─────┬───┘
                           │         │     │
            ┌──────────────┤         │     ├──────────────┐
            │              │         │     │              │
     ┌──────┴──────┐ ┌────┴─────┐ ┌─┴──────────┐ ┌──────┴───────┐
     │   dc-ipa    │ │lan-client│ │proxy-squid  │ │   web-dmz    │
     │  (Samba AD  │ │10.10.10  │ │10.10.10.20  │ │ 10.10.30.10  │
     │  DC / DNS / │ │   .10    │ │  (Squid)    │ │  (Nginx)     │
     │  Kerberos)  │ │          │ │             │ │   (DMZ)      │
     │ 10.10.10.5  │ │          │ │             │ │              │
     └─────────────┘ └──────────┘ └─────────────┘ └──────────────┘
```

### Les VMs du Lab (VirtualBox)

![VMs du lab dans VirtualBox](../screenshots/Module4-Proxy-Squid/Screenshot%20from%202026-07-11%2015-19-07.png)

> Les 5 machines virtuelles : **pfsens** (firewall), **lan-client** (poste utilisateur), **dc-ipa** (contrôleur de domaine), **web-dmz** (serveur web isolé en DMZ), **proxy-squid** (proxy Squid).

---

## 📋 Modules Complétés

- [x] **Module 1** : Firewall pfSense — WAN/LAN/DMZ, DHCP, règles de filtrage
- [x] **Module 2** : Active Directory — Samba DC, DNS, Kerberos, jonction client Ubuntu
- [x] **Module 2+** : Création d'utilisateurs, RBAC, vérification avec `id` / `getent`
- [x] **Module 3** : DMZ + Nginx — isolation réseau, port forwarding, DNAT
- [x] **Module 4.1** : Forward Proxy explicite (Squid)
- [x] **Module 4.2** : Filtrage de sites (blocked_sites.txt)
- [x] **Module 4.4** : Proxy transparent (interception pfSense + DNAT)
- [x] **Module 4.5** : Reverse Proxy (Nginx en DMZ)
- [x] **Module 4.6** : SSL Bump (interception HTTPS, CA auto-signée)
- [x] **Module 4.7** : Authentification proxy via AD (Kerberos SSO)
- [x] **RBAC & PAM** : sudoers pour Domain Admins, `pam_wheel`, `pam_mkhomedir`
- [ ] **Module 5** : VPN WireGuard ← **EN COURS**

---

## 🗺️ Schéma global du trafic

```
Trafic Sortant (Employés naviguent sur le web) :
  lan-client → Squid (Forward Proxy, 10.10.10.20) → pfSense → Internet

Trafic Entrant (Visiteurs accèdent au site de l'entreprise) :
  Internet → pfSense (DNAT port 80) → Nginx (Reverse Proxy, 10.10.30.10) → App backend

Authentification centralisée :
  Toute machine → Kerberos (dc-ipa, 10.10.10.5) → Ticket TGT → Accès SSO
```

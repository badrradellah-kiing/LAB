# 🔐 Secure Network Engineering Lab

Mon lab de sécurité réseau, construit de zéro sur des VMs isolées. 20 modules, du premier firewall jusqu'à un exercice purple-team complet. L'idée c'est simple : chaque truc que je monte côté défense, je l'attaque moi-même pour prouver que ça marche (ou pas).

C'est pas un tuto copié-collé. C'est mes notes perso — les commandes qui ont marché, les trucs qui ont cassé, les pièges que j'ai pris en pleine face et comment je les ai résolus. Si un truc m'a fait galérer 2h, c'est dedans.


---

## L'architecture

Tout tourne autour d'un pfSense qui segmente le réseau en 3 zones. Rien ne passe entre les zones sans passer par le firewall — exactement comme en entreprise.

```
                    ┌─────────────┐
     WAN / Kali ────┤   pfSense   ├──── MGMT (10.10.99.0/24)
     (attaquant)    │  (firewall) │         mgmt-ansible
                    └──┬──────┬───┘
                       │      │
              LAN ─────┘      └───── DMZ
         10.10.10.0/24           10.10.30.0/24
                                     
    dc-ipa (FreeIPA)             web-dmz (Nginx + WAF)
    DC01 (Windows AD)            ids-sensor (Suricata + Wazuh)
    lan-client
    proxy-squid
    win-endpoint
```

| Zone | Réseau | Ce qu'il y a |
|------|--------|-------------|
| WAN | NAT | Kali (mon poste d'attaquant) |
| LAN | 10.10.10.0/24 | dc-ipa, DC01, lan-client, proxy-squid, win-endpoint |
| DMZ | 10.10.30.0/24 | web-dmz (serveur web exposé), ids-sensor (SIEM) |
| MGMT | 10.10.99.0/24 | mgmt-ansible (administration) |

---

## Les modules

Chaque module a ses notes complètes (commandes, screenshots, galères) dans [`notes/`](./notes).

### Fondations réseau
| # | Module | Ce que j'ai fait |
|---|--------|-----------------|
| 1 | [Firewall pfSense](./notes/01-Firewall-pfSense.md) | Segmentation 3 zones, règles inter-VLAN, NAT |
| 2 | [AD / Samba / Kerberos](./notes/02-AD-Samba-Kerberos.md) | FreeIPA, annuaire centralisé, auth Kerberos |
| 3 | [DMZ & Nginx](./notes/03-DMZ-Nginx.md) | Reverse proxy, zone démilitarisée |
| 4 | [Proxy Squid](./notes/04-Proxy-Squid.md) | Filtrage web, cache proxy |
| 5 | [SSL Bump](./notes/05-SSL-Bump.md) | Interception HTTPS (inspection TLS) |
| 6 | [Proxy Auth AD](./notes/06-Proxy-Auth-AD.md) | Auth Kerberos sur le proxy |
| 7 | [RBAC & PAM](./notes/07-RBAC-PAM.md) | Contrôle d'accès, sudo, PAM |
| 8 | [VPN WireGuard](./notes/08-VPN.md) | Tunnel chiffré site-to-site |

### Détection & défense
| # | Module | Ce que j'ai fait |
|---|--------|-----------------|
| 6b | [IDS/IPS & WAF](./notes/10-Module6-IDS-IPS-WAF.md) | Suricata + ModSecurity + OWASP CRS |
| 7b | [Host Hardening](./notes/11-Module7-Host-Hardening.md) | CIS, audit, durcissement Linux |
| 8b | [SIEM & Detection](./notes/12-Module8-SIEM-Detection.md) | Wazuh, centralisation des logs, alertes |

### Infra avancée
| # | Module | Ce que j'ai fait |
|---|--------|-----------------|
| 9 | [Cloud Security](./notes/13-Module9-Cloud-Security.md) | AWS VPC, Security Groups, IAM |
| 10 | [PKI](./notes/14-Module10-PKI.md) | CA racine + intermédiaire, certificats TLS |
| 11 | [Linux Internals](./notes/15-Module11-Linux-Internals.md) | Namespaces, cgroups, capabilities |
| 12 | [Windows Security](./notes/16-Module12-Windows-Security.md) | AD Windows, Sysmon, GPO, Kerberoasting |

### Offensive & réponse
| # | Module | Ce que j'ai fait |
|---|--------|-----------------|
| 18 | [Detection Engineering](./notes/17-Module18-Detection-Engineering.md) | MITRE ATT&CK, Atomic Red Team, règles Sigma |
| 19 | [Incident Response](./notes/18-Module19-IR-Forensics.md) | IR drill complet (PICERL), forensics, timeline |
| 20 | [Capstone Purple Team](./notes/19-Module20-Capstone-Purple-Team.md) | Kill chain complète, rouge vs bleu, score de couverture |

---

## Le résultat du purple-team (Module 20)

Le dernier module c'est l'examen final : j'attaque mon lab de bout en bout et je regarde ce qui tient.

| Étape | Attaque | Défense | Résultat |
|-------|---------|---------|----------|
| Recon | Nmap | Suricata | 🟢 Détecté |
| Initial Access | Exploit web | WAF (ModSecurity) | 🟢 Bloqué |
| Execution + Persistence | Implant + C2 + cron | IR manuel | 🟡 Partiel |
| Discovery | Énum LDAP | Logs AD | 🟢 Détecté |
| Credential Access | Kerberoasting | Wazuh 4769 | 🟢 Détecté |
| Brute Force | Atomic T1110 | Wazuh 4625 | 🟢 Validé |
| Lateral Movement | Pass-the-Hash | — | 🔴 Angle mort |
| Objective | Pivot cloud | Partiel | 🟡 Partiel |

**5 verts, 2 partiels, 1 angle mort.** Les trous sont identifiés et dans ma backlog.

---

## Ce qui me reste à faire

- [ ] Détection auto sur process depuis `/tmp` + nouveau cron + port non standard
- [ ] Combler Pass-the-Hash (4624 type 3 + NTLM anormal)
- [ ] Exporter ma couverture en JSON ATT&CK Navigator
- [ ] Commencer le lab DevSecOps & Cloud Security (Docker, K8s, cloud-native)

---

## Refs

- [Cheat Sheet](./notes/09-Cheat-Sheet.md) — toutes mes commandes en un seul endroit

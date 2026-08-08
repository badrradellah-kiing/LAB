# Module 20 — Capstone Purple-Team : rapport d'exercice

> Rapport de mon exercice purple-team de fin de lab. Le but : attaquer mon propre lab de
> bout en bout, puis vérifier que ma défense a réagi à chaque étape. C'est l'examen final
> qui prouve que mon lab n'est pas une pile d'outils séparés, mais un **système de défense
> en couches** cohérent.

---

## Sommaire
- [Ce qu'est cet exercice](#ce-quest-cet-exercice)
- [20.1 — Threat model de mon lab](#201--threat-model-de-mon-lab)
- [20.2 + 20.3 — La kill chain et la vérification](#202--203--la-kill-chain-et-la-vérification-de-la-défense)
- [Tableau de synthèse](#le-tableau-de-synthèse-attaque--défense)
- [Plan d'amélioration](#mon-plan-damélioration-issu-de-lexercice)
- [Bilan du lab](#bilan-du-lab-réseau-modules-1--20)

---

## Ce qu'est cet exercice

Purple team = rouge (attaquant) + bleu (défenseur) dans le même exercice. Je joue les deux : j'attaque mon lab comme un vrai adversaire, et pour chaque coup je vérifie ce que ma défense a fait (bloqué, détecté, ou raté). Ça rassemble en une seule démonstration tout ce que j'ai construit dans les 19 modules précédents.

Le principe défensif que ça valide : **la défense en profondeur**. Un attaquant ne se fait pas arrêter par un mur unique, mais par une succession de contrôles, chacun rattrapant ce que le précédent a laissé passer.

---

## 20.1 — Threat model de mon lab

Avant d'attaquer, je réfléchis comme l'adversaire. Trois questions :

**Qu'est-ce qui a de la valeur (les joyaux) ?**
- Mon annuaire / DC (`adlab.local` sur DC01) — les identités du domaine
- Les secrets et l'accès cloud
- Les données sur mes serveurs

**Par où on entre (surface d'attaque) ?**
- Le serveur web exposé en DMZ (`web-dmz`) — la porte la plus évidente, exposée à l'extérieur

**Quel chemin l'attaquant prendrait ?**
```
Internet
   │  (1) reconnaissance : scan
   ▼
web-dmz (DMZ)  ──(2) exploit web / entrée──▶ prise de pied (shell)
   │  (3) exécution + persistence
   ▼
Réseau interne ──(4) découverte de l'annuaire──▶ DC01 (adlab.local)
   │  (5) vol de credentials (Kerberoasting)
   ▼
(6) mouvement latéral ──▶ (7) objectif : données / cloud
```

C'est ma carte de bataille. Chaque flèche = une étape que je vais exécuter puis vérifier.

---

## 20.2 + 20.3 — La kill chain et la vérification de la défense

Je déroule le chemin du threat model. Pour chaque étape : l'attaque (rouge), la défense qui a réagi (bleu), et le résultat. La plupart de ces attaques, je les ai réellement exécutées dans les modules précédents.

### Étape 1 — Reconnaissance (scan de ports)
- **Rouge** : scan Nmap depuis Kali vers la DMZ (Module 6)
- **ATT&CK** : T1046 (Network Service Discovery)
- **Bleu** : Suricata sur l'ids-sensor lève une alerte de scan ; les logs remontent au SIEM
- **Résultat** : 🟢 **DÉTECTÉ**

### Étape 2 — Accès initial (exploit web)
- **Rouge** : requêtes malveillantes vers le serveur web (SQLi/XSS/path traversal) — Module 6
- **ATT&CK** : T1190 (Exploit Public-Facing Application)
- **Bleu** : ModSecurity + OWASP CRS bloque la requête (règle CRS déclenchée), log au SIEM
- **Résultat** : 🟢 **BLOQUÉ**

### Étape 3 — Exécution + persistence (compromission du serveur)
- **Rouge** : prise de pied sur web-dmz — payload distant, implant, C2 sur port 4444, persistence cron (rejoué au Module 19)
- **ATT&CK** : T1059 (Command/Scripting), T1571 (Non-Standard Port), T1053.003 (Cron)
- **Bleu** : à ce stade, détection partielle. Le triage IR (Module 19) a identifié le process depuis /tmp, le port 4444 et le cron — mais **aucune alerte automatique** n'existait encore sur ces indicateurs
- **Résultat** : 🟡 **DÉTECTÉ EN IR, mais angle mort en détection auto** → todo

### Étape 4 — Découverte (énumération de l'annuaire)
- **Rouge** : énumération LDAP/AD des comptes et SPN (Module 1/12)
- **ATT&CK** : T1087 (Account Discovery)
- **Bleu** : requêtes LDAP visibles dans les logs AD / SIEM
- **Résultat** : 🟢 **DÉTECTÉ** (visibilité présente)

### Étape 5 — Credential Access (Kerberoasting)
- **Rouge** : `impacket-GetUserSPNs` contre DC01 pour récupérer le ticket de `svc-sql` (Module 12) ; validé aussi via Atomic Red Team (Module 18)
- **ATT&CK** : T1558.003 (Kerberoasting)
- **Bleu** : Event 4769 côté DC, remonté dans Wazuh. Détection validée par émulation au Module 18. Note : Windows 2025 bloque RC4 par défaut → l'attaque classique a été partiellement neutralisée par le durcissement lui-même
- **Résultat** : 🟢 **DÉTECTÉ** (+ durcissement natif bonus)

### Étape 5bis — Brute force (password guessing)
- **Rouge** : brute force AD via SMB, rejoué avec Atomic Red Team T1110.001 (Module 18)
- **ATT&CK** : T1110 (Brute Force)
- **Bleu** : pic de 4625 → règle Wazuh déclenchée, alerte vue dans le SIEM (preuve du déclenchement obtenue au Module 18). Fail2Ban en complément
- **Résultat** : 🟢 **DÉTECTÉ ET VALIDÉ**

### Étape 6 — Mouvement latéral
- **Rouge** : Pass-the-Hash / réutilisation de credentials vers d'autres machines
- **ATT&CK** : T1550.002 (Pass the Hash)
- **Bleu** : pas de détection dédiée en place
- **Résultat** : 🔴 **ANGLE MORT** → todo

### Étape 7 — Objectif (données / cloud)
- **Rouge** : accès aux données, pivot vers le cloud avec identité détournée
- **ATT&CK** : T1078 (Valid Accounts)
- **Bleu** : couverture partielle (dépend du durcissement cloud, Modules 14-16)
- **Résultat** : 🟡 **PARTIEL** → à renforcer au DevSecOps/Cloud

---

## Le tableau de synthèse (attaque → défense)

| # | Étape (ATT&CK) | Attaque (rouge) | Défense (bleu) | Résultat |
|---|----------------|-----------------|----------------|----------|
| 1 | T1046 Recon | Nmap scan | Suricata | 🟢 Détecté |
| 2 | T1190 Initial Access | Exploit web | ModSecurity CRS | 🟢 Bloqué |
| 3 | T1059/T1571/T1053 Exec+Persist | Implant + C2 + cron | Triage IR (pas d'alerte auto) | 🟡 Partiel |
| 4 | T1087 Discovery | Énum LDAP/AD | Logs AD/SIEM | 🟢 Détecté |
| 5 | T1558.003 Kerberoasting | GetUserSPNs | Wazuh 4769 + durci RC4 | 🟢 Détecté |
| 5b | T1110 Brute Force | Atomic T1110.001 | Wazuh 4625 + Fail2Ban | 🟢 Validé |
| 6 | T1550.002 Lateral Move | Pass-the-Hash | — | 🔴 Angle mort |
| 7 | T1078 Objective | Identité détournée | Durcissement partiel | 🟡 Partiel |

**Score de couverture : 5 verts, 2 partiels, 1 angle mort.** Une défense en profondeur qui tient sur la majorité de la kill chain, avec des trous clairement identifiés.

---

## Ce que le Capstone m'a fait comprendre

La sécurité n'est pas une pile d'outils, c'est un **système en couches**. En regardant le tableau, je vois qu'un attaquant qui veut aller d'Internet jusqu'à mes joyaux doit franchir plusieurs contrôles successifs : le scan est vu (Suricata), l'exploit est bloqué (WAF), le Kerberoasting est détecté (Wazuh)… Même là où un étage laisse passer, le suivant peut rattraper. C'est ça la défense en profondeur, et le fait de l'avoir vue à l'œuvre de bout en bout, c'est ce qui compte.

Les cases rouges/jaunes ne sont pas des échecs — c'est ma **backlog de sécurité**, priorisée par une attaque réelle et non par une liste théorique.

---

## Mon plan d'amélioration (issu de l'exercice)

Priorisé par les trous que l'attaque a révélés :

1. **Étape 3** — écrire des règles Sigma : process lancé depuis `/tmp`, nouveau fichier dans `/etc/cron.d`, port en écoute hors 80/443/22 (Modules 8/18)
2. **Étape 6 (angle mort)** — détection Pass-the-Hash : 4624 type 3 + NTLM depuis source anormale (T1550.002)
3. **Étape 7** — renforcer le durcissement cloud et le moindre privilège (Modules 14-16, puis DevSecOps)
4. **Transverse** — diffuser les IOCs de l'incident (Module 19) sur pfSense + chasse sur le parc ; vérifier la synchro NTP sur toutes les sources pour des timelines fiables

---

## Baseline atteinte

Cet état — "voici ce que j'attaque, voici ce que je détecte, voici mes trous" — est ma **baseline de sécurité de référence**. C'est le point de départ que le lab DevSecOps/Cloud me demande d'avoir avant de tout faire évoluer vers le cloud-native. Le cycle reste le même (attaquer → vérifier → améliorer), seuls les artefacts changeront (conteneurs, K8s, cloud).

---

## Bilan du lab réseau (Modules 1 → 20)

- Segmentation réseau, firewall, DMZ (M1-3)
- Proxy, WAF, durcissement web (M2, 6)
- IDS/IPS, SIEM, détection (M7-9)
- PKI, internals Linux (M10-11)
- Windows Enterprise Security & Sysmon (M12)
- Detection engineering + validation par émulation (M18)
- Incident Response & Forensics complet (M19)
- Capstone purple-team de bout en bout (M20) ← ce rapport

**Lab réseau terminé.** Prochaine étape : le lab **DevSecOps & Cloud Security** — Docker, Kubernetes, sécurité cloud-native — en partant de cette baseline.

# Module 8 — Détection Intégrée (De l'attaque au Dashboard)

### Ma doc perso du lab

Dans ce module, l'objectif n'est plus de laisser chaque équipement dans son coin : je centralise tous mes logs dans un SIEM, je trace des attaques réelles de bout en bout, et j'apprends à écrire mes propres règles de détection portables.

L'objectif final est d'avoir une vraie visibilité sur ce qui se passe sur mon réseau.

---

## Sommaire
- [8.1 — Construire mon Dashboard (Le SIEM Wazuh)](#81--construire-mon-dashboard-le-siem-wazuh)
- [8.2 — Centraliser les logs (Syslog & Filebeat)](#82--centraliser-les-logs-syslog--filebeat)
- [8.3 — Détection de force brute SSH (Fail2Ban & Wazuh)](#83--détection-de-force-brute-ssh-fail2ban--wazuh)
- [8.4 — Détection de scan réseau (Suricata & Nmap)](#84--détection-de-scan-réseau-suricata--nmap)
- [8.5 — Ingénierie de la détection (Règles sur mesure et Sigma)](#85--ingénierie-de-la-détection-règles-sur-mesure-et-sigma)

---

## 8.1 — Construire mon Dashboard (Le SIEM Wazuh)

### Le principe
Je transforme ma machine `ids-sensor` (10.10.30.50) en un SIEM central capable d'ingérer les logs de mon pare-feu, de mes services SSH, de mon IDS (Suricata) et de mon proxy. L'outil choisi est **Wazuh** car il fournit un gestionnaire, un indexeur et un dashboard intégré.

### L'installation et ses galères (beaucoup de galères)

Je pensais que l'installation "All-in-one" allait passer toute seule avec :
```bash
curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh
sudo bash wazuh-install.sh -a
```

Mais la réalité m'a vite rattrapé. J'ai fait face à de gros problèmes de ressources. Wazuh est extrêmement gourmand.

**Problème 1 : Manque d'espace disque**
L'installation échouait, et je me suis rendu compte que mon disque VDI était plein.
J'ai dû redimensionner le disque VirtualBox de 20GB à 40GB.
![Resize VDI](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-24%2021-34-04.png)

Puis étendre la partition LVM dans la VM avec `growpart`, `pvresize` et `lvextend`.
![LVM Resize](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-24%2021-37-57.png)

**Problème 2 : Manque de RAM et installation cassée**
Même avec le disque étendu, le dashboard crashait (`wazuh-dashboard service failed`). Wazuh demande au moins 4GB de RAM. J'ai upgradé la RAM de la VM, purgé l'installation échouée avec `apt purge` et des `rm -rf /var/ossec`, puis j'ai repris l'installation étape par étape (certificats, indexer, manager, dashboard).

### Le succès
Finalement, l'installation s'est terminée avec succès.
![Install Success](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-25%2001-04-53.png)

Et j'ai enfin pu accéder au Dashboard Wazuh fonctionnel avec mes agents connectés.
![Agents List](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-25%2021-16-42.png)
![Dashboard Overview](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-25%2022-33-13.png)

---

## 8.2 — Centraliser les logs (Syslog & Filebeat)

Maintenant que le SIEM est prêt, il faut le nourrir.

Sur pfSense, j'ai configuré `rsyslog` pour envoyer tous les journaux du pare-feu vers l'IP de mon SIEM (10.10.30.50) sur le port 514 (UDP). 

Sur mon `ids-sensor`, j'ai configuré rsyslog pour écouter sur ce port et écrire les logs dans `/var/log/pfsense.log`.
Ensuite, on dit à Filebeat de lire ce fichier pour l'envoyer à l'indexeur Wazuh.

---

## 8.3 — Détection de force brute SSH (Fail2Ban & Wazuh)

C'est l'heure de tester si tout ça sert à quelque chose. Je lance une attaque par force brute depuis ma machine Kali (`10.10.10.104`) vers le proxy (`10.10.10.20`) avec Hydra.

Après avoir réglé quelques problèmes de routage depuis Kali (Kali cherchait à joindre le réseau DMZ par défaut sans passer par pfSense), l'attaque est lancée :
```bash
hydra -l testuser -P /usr/share/wordlists/rockyou.txt ssh://10.10.10.20 -t 4 -V
```

![Hydra Brute Force](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-25%2022-55-39.png)

Immédiatement, `Fail2Ban` que j'avais configuré au Module 7 repère les échecs et bannit l'IP de Kali. Sur Kali, je commence à recevoir des "Connection refused".
Sur le proxy, je vérifie le statut de Fail2Ban :
![Fail2Ban Ban](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-25%2023-13-50.png)

Wazuh, qui collecte les logs du proxy (via son agent), remonte aussi les alertes critiques d'authentification SSH échouée, avec les tags MITRE ATT&CK correspondants (Credential Access / Brute Force).

---

## 8.4 — Détection de scan réseau (Suricata & Nmap)

Je teste ensuite l'IDS (Suricata) en lançant un scan Nmap depuis Kali vers la machine `web-dmz` (10.10.30.10).

```bash
nmap -sS -p- 10.10.30.10
```
![Nmap Scan](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-27%2014-53-11.png)

Suricata, configuré en mode IDS sur l'interface, capte le trafic et génère des alertes dans son fichier `eve.json`. 
![Suricata Alerts](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-27%2015-20-10.png)

L'agent Wazuh transmet ensuite ce fichier `eve.json` au manager. Sur le dashboard Wazuh, je retrouve les événements Suricata parfaitement parsés. L'IDS et le SIEM communiquent bien.

---

## 8.5 — Ingénierie de la détection (Règles sur mesure et Sigma)

Wazuh vient avec beaucoup de règles par défaut, mais un bon ingénieur SIEM doit savoir créer les siennes.
J'ai simulé une application (Nginx) qui génère un log d'erreur spécifique : `AUTH_FAIL client=10.10.10.104 reason=invalid_password`.

### 1. Création du décodeur
Il faut d'abord apprendre à Wazuh à lire ce format spécifique avec une expression régulière. Dans `/var/ossec/etc/decoders/local_decoder.xml` :
![Local Decoder](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-27%2015-38-17.png)

### 2. Création de la règle et test
Ensuite, j'écris la règle qui déclenche l'alerte dans `/var/ossec/etc/rules/local_rules.xml`. 
Pour être sûr que ça fonctionne avant de redémarrer le serveur, j'utilise l'outil `wazuh-logtest` en lui balançant la ligne de log :
![Logtest Success](../screenshots/Module8-SIEM-Detection/Screenshot%20from%202026-07-27%2015-55-51.png)
Boum ! L'alerte de niveau 12 ("CRITICAL: web auth brute force") est générée avec succès.

### Sigma
En bonus, j'ai traduit cette logique en règle **Sigma**. Sigma est au SIEM ce que Snort est à l'IDS : un format générique. L'avantage, c'est que je peux écrire ma règle de détection en Sigma, puis utiliser l'outil `sigma-cli` pour la convertir automatiquement pour Wazuh, Splunk, ou ElasticSearch, ce qui la rend portable si je change de SIEM un jour.

Fin du module 8 ! Le réseau est surveillé.

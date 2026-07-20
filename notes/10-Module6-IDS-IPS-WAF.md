# 🛡️ Module 6 — IDS/IPS & WAF : Journal de lab complet

> **Secure Network Engineering Lab** — Journal de bord de la session.
> Tout ce qu'on a construit, dans l'ordre, avec **les réussites ET les galères** — parce que c'est le débogage qui apprend le vrai métier.
>
> Machine principale du module : `ids-sensor` (10.10.30.50) + `web-dmz` (10.10.30.10)
> Utilisateur : `badr` · Hyperviseur : VirtualBox · Cible : lab isolé uniquement.

---

## Sommaire

1. [État initial du lab](#1-état-initial-du-lab)
2. [Objectif du module 6](#2-objectif-du-module-6)
3. [Création du capteur `ids-sensor`](#3-création-du-capteur-ids-sensor)
4. [Installation & configuration de Suricata (6.1)](#4-installation--configuration-de-suricata-61)
5. [Premier test de détection en direct](#5-premier-test-de-détection-en-direct)
6. [Recâblage de Kali Linux (le lab devient réaliste)](#6-recâblage-de-kali-linux-le-lab-devient-réaliste)
7. [Deuxième test : attaque "Brute Force" SSH](#7-deuxième-test--attaque-brute-force-ssh)
8. [Le mode IPS](#8-le-mode-ips)
9. [Suricata en mode IPS (Inline) - Le mur de feu](#9-suricata-en-mode-ips-inline---le-mur-de-feu)
10. [Web Application Firewall (WAF) avec ModSecurity et Nginx](#10-web-application-firewall-waf-avec-modsecurity-et-nginx)
11. [Résolution de problèmes (WAF et Nginx)](#11-résolution-de-problèmes-waf-et-nginx)
12. [Activation du WAF](#12-activation-du-waf)
13. [Fin du module 6 et suite logique](#13-fin-du-module-6-et-suite-logique)

---

## 1. État initial du lab

Au début de cette session, j'avais 6 VMs qui tournaient tranquillement. L'architecture de base (AD, pfSense, DMZ, Proxy) était bien en place et fonctionnait correctement.

![État initial du lab](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-17%2023-31-25.png)

## 2. Objectif du module 6

L'idée ici, c'était d'arrêter d'être aveugle sur ce qui se passe sur le réseau. Le but : mettre en place un IDS/IPS avec Suricata pour renifler et bloquer les attaques réseau, et blinder le serveur web avec un WAF (ModSecurity). En gros, transformer la DMZ en forteresse.

## 3. Création du capteur `ids-sensor`

### 3.1 Snapshot de sécurité (réflexe pro)

Avant de tout casser, j'ai pris le réflexe de faire un snapshot sur `web-dmz`. On ne sait jamais. Nommé sobrement : `avant-module-6`.

![Snapshot de sécurité web-dmz](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-18%2000-01-37.png)

### 3.2 Spécifications de la VM

Déploiement d'une VM Ubuntu Server toute neuve.
- Utilisateur : `badr`
- Hostname : `ids-sensor`
- IP statique : `10.10.30.50` (branchée sur la DMZ).

![Installation Ubuntu - Utilisateur](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-18%2000-22-58.png)

### 3.3 Réglage réseau — LE point critique

Pour qu'un IDS serve à quelque chose, il faut qu'il puisse voir passer les paquets des autres. Dans VirtualBox, j'ai dû forcer le mode Promiscuous sur `Allow All` pour l'interface de la VM. Sans ça, Suricata serait resté totalement aveugle et n'aurait écouté que son propre trafic.

![Mode Promiscuous](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-18%2000-14-09.png)

### 3.4 Installation Ubuntu

Petite vérif réseau après le boot.
Ici, j'ai remarqué un truc marrant (le détour réseau) : mon ping vers la passerelle (`10.10.30.1`) ou vers internet (`1.1.1.1`) donnait "100% packet loss" parce que pfSense bloquait l'ICMP pour cette nouvelle machine. Par contre, le ping vers `web-dmz` (`10.10.30.10`) passait crème. Le réseau n'était pas cassé, c'était juste le firewall qui faisait son job.

![Validation Connectivité LAN DMZ](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-18%2000-45-11.png)

## 4. Installation & configuration de Suricata (6.1)

### 4.1 Installation + règles

Un coup d'apt, on installe Suricata, puis je lance un `suricata-update` pour télécharger le jeu de règles officiel d'Emerging Threats. Plus de 51 000 règles activées !

![suricata-update](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-18%2000-51-57.png)

### 4.2 Piège n°1 — le nom de l'interface (`enp0s3`)

Par défaut, le fichier de conf de Suricata (`suricata.yaml`) s'attend à écouter sur `eth0`. Mon interface s'appelait `enp0s3`. J'ai utilisé l'astuce du `grep -n "interface:" /etc/suricata/suricata.yaml` pour trouver direct les bonnes lignes à changer dans ce fichier énorme.

![grep interface suricata.yaml](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-18%2000-51-57.png)

### 4.5 Piège n°3 — la syntaxe cassée par le copier-coller

En voulant modifier une règle locale, grosse erreur de frappe. J'ai collé `->$HOME_NET` au lieu de `-> $HOME_NET` (avec l'espace). Suricata m'a directement insulté avec une erreur `detect-parse` au démarrage. Toujours vérifier la syntaxe !

![Erreur de syntaxe Suricata](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-18%2020-35-29.png)

### 4.6 Validation + démarrage

Correction faite, je valide la conf avec `sudo suricata -T -c /etc/suricata/suricata.yaml -v`. 
Boum : `Notice: Configuration provided was successfully loaded`. 
On peut relancer et activer le service sereinement !

![Démarrage Suricata](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-18%2020-38-03.png)

## 5. Premier test de détection en direct

Pour voir si la bête fonctionne, je tail le fichier `eve.json` avec un petit `grep` ciblé sur les alertes.
Je balance un simple ping sur le réseau et direct, ça pop à l'écran : `LAB ICMP PING DETECTED`. Ça marche à merveille !

![Détection Ping ICMP](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-18%2020-40-44.png)

## 6. Recâblage de Kali Linux (le lab devient réaliste)

Pour rendre le test plus réaliste, j'ai sorti Kali du NAT simple pour l'intégrer au réseau, histoire de simuler une vraie attaque de brute force en conditions quasi-réelles vers la DMZ.

## 7. Deuxième test : attaque "Brute Force" SSH

### 7.3 L'attaque (depuis ids-sensor)

On sort l'artillerie légère : `hydra` avec une petite wordlist (`/tmp/wordlist.txt`) pour bombarder le port SSH de la `web-dmz`.
En quelques secondes, Hydra me sort le mot de passe éclaté de mon compte test : `password123`.

![Attaque Hydra SSH](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2001-27-39.png)

### 7.4 Les trois vues de la même attaque

Ce screen est stylé, on voit la totale en temps réel :
- En haut : L'attaquant (Hydra) qui trouve le mot de passe.
- En bas : La victime (`web-dmz`) qui accumule les logs d'échec dans `/var/log/auth.log` avant de valider la session.
*(Et au même moment, Suricata gueulait ses alertes `LAB SSH connexion attempt`).*

![Les 3 vues de l'attaque](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2001-28-39.png)

## 8. Le mode IPS

L'IDS, c'est bien, il prévient. Mais moi, je veux qu'il bloque les attaques de lui-même. On passe aux choses sérieuses : transformer Suricata en mode IPS (Intrusion Prevention System).

## 9. Suricata en mode IPS (Inline) - Le mur de feu

### 9.1 La théorie vs la pratique (NFQUEUE)

Le concept est simple : dire au firewall Linux d'envoyer les paquets à Suricata via une file d'attente (NFQUEUE) avant de décider s'ils passent ou non. 

### 9.4 Piège n°4 — NFQUEUE introuvable

Je balance ma commande `iptables -I input -j NFQUEUE --queue-num 0` comme d'habitude. Et là : `iptables: No chain/target/match by that name`. Le module NFQUEUE semblait totalement introuvable. 

![Piège NFQUEUE iptables](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2012-59-18.png)

### 9.5 La solution en nftables natif

J'ai vite compris : sur Ubuntu 24.04, `iptables` c'est de l'histoire ancienne. Tout tourne sous `nftables` par défaut.
J'ai dû tout refaire avec la nouvelle syntaxe `nft` pour créer la table, la chaîne, et linker ça avec la `queue num 0`. Du beau boulot natif et plus propre au final.

![Solution nftables natif](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2013-01-53.png)

### 9.7 Nettoyage propre (obligatoire)

Un pkill bien placé (`sudo pkill -f "suricata -q 0"`) pour tuer les instances qui tournent en fond avant de recharger la conf IPS proprement. Sinon, c'est le conflit assuré sur la file d'attente.

![Nettoyage Suricata pkill](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2013-09-36.png)

## 10. Web Application Firewall (WAF) avec ModSecurity et Nginx

### 10.2 Installation

Maintenant, on sécurise le serveur web lui-même pour bloquer les attaques de couche 7. J'ai installé le module ModSecurity directement sur la machine `web-dmz`.

![Installation ModSecurity](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2015-25-15.png)

### 10.3 Récupérer le jeu de règles OWASP (CRS)

ModSecurity tout nu, ça ne sert à rien, il lui faut de l'intelligence. J'ai fait un `git clone` du CoreRuleSet (CRS) de l'OWASP pour lui donner le meilleur dictionnaire d'attaques web possible.

![Installation OWASP CRS](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2015-34-22.png)

### 10.5 Intégration Nginx (le reverse proxy)

J'ai édité le block serveur de Nginx (`/etc/nginx/sites-enabled/app`) pour activer le WAF (`modsecurity on;`) et balancer le trafic proxy sur un backend local que je comptais faire tourner sur le port `8080`.

![Intégration Nginx WAF](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2015-52-59.png)

### 10.6 Premier test (sans les règles CRS)

Pour comparer l'avant/après, j'ai lancé une attaque XSS/SQLi toute bête avec un `curl` (`?q=<script>alert(1)</script>`) alors que le CRS n'était pas encore actif.
Résultat : la requête passe sans problème et Nginx répond 200. Normal, le WAF dort encore.

![Test XSS sans WAF](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2015-59-58.png)

## 11. Résolution de problèmes (WAF et Nginx)

### 11.1 Le fichier d'audit introuvable

En voulant vérifier les logs, impossible de lire `/var/log/modsec_audit.log`. Fichier inexistant. J'ai dû aller fouiller dans `modsecurity.conf` pour corriger le chemin du fichier d'audit.

![Erreur fichier audit](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-19%2016-03-41.png)

### 11.2 L'erreur 502 Bad Gateway

Après avoir configuré le reverse proxy, je teste un accès HTTP basique et paf : `502 Bad Gateway`. Dans le `error.log`, je vois que Nginx refuse la connexion (Connection refused) parce que rien n'écoute sur le port `8080`. Logique.

![Erreur 502 Bad Gateway](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-20%2001-46-08.png)

### 11.3 La vraie solution : démarrer le backend

La gaffe bête : j'avais oublié de lancer le fameux service web backend ! J'ai réglé ça en une ligne en levant un serveur avec `python3 -m http.server 8080 &`. Le trafic est repassé au vert (code HTTP 200).

![Démarrage Backend Python](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-20%2012-17-10.png)

## 12. Activation du WAF

### 12.2 Passage en mode blocage (On)

C'est l'heure de vérité. Je passe `SecRuleEngine DetectionOnly` à `SecRuleEngine On`. Fini de rigoler, maintenant le WAF va tuer les requêtes malveillantes.

![SecRuleEngine On](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-20%2012-24-52.png)

### 12.3 Le test ultime (le blocage 403)

Je retente mon attaque `curl` basique avec un payload SQLi.
BAM ! Le WAF l'attrape au vol et me jette un superbe `403 Forbidden` à la figure. 
Dans les logs d'erreur de Nginx, ModSecurity m'informe froidement : `Access denied... Inbound Anomaly Score Exceeded`. Le mur est solide, le WAF fait le job.

![Test blocage WAF 403](../screenshots/Module6-IDS-IPS-WAF/Screenshot%20from%202026-07-20%2012-27-48.png)

## 13. Fin du module 6 et suite logique

Mission accomplie. Le réseau est sous écoute IPS et la couche web est barricadée derrière l'OWASP CRS.
La suite logique, c'est de durcir directement l'OS de nos hôtes via des outils comme Fail2Ban (Module 7).

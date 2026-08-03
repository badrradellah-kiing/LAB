# Module 11 — Linux Internals & nftables

### Mes notes perso

Ce module c'est pour comprendre ce qui se passe sous le capot de Linux. Parce que quand je déploie un conteneur Docker ou que j'écris une règle firewall, y'a des mécanismes noyau derrière qui font le vrai travail. Ici je les manipule directement à la main.

---

## Sommaire
- [11.1 — nftables : le pare-feu moderne](#111--nftables--le-pare-feu-moderne)
- [11.2 — Namespaces & cgroups (isolation des processus)](#112--namespaces--cgroups-isolation-des-processus)
- [11.3 — Capabilities (fractionnement du pouvoir root)](#113--capabilities-fractionnement-du-pouvoir-root)
- [11.4 — Audit du noyau (AppArmor & auditd)](#114--audit-du-noyau-apparmor--auditd)

---

## 11.1 — nftables : le pare-feu moderne

### Le principe
`nftables` c'est le successeur d'`iptables`. En fait, sur Ubuntu, `iptables` est déjà traduit en nftables en arrière-plan (on le voit avec le warning `table ip filter is managed by iptables-nft, do not touch!`). Autant apprendre la syntaxe native directement.

### Ce que j'ai fait

J'ai créé une table et une chaîne de filtrage, puis ajouté une règle pour compter et accepter les pings ICMP :

```bash
sudo nft add table inet lab_table
sudo nft add chain inet lab_table filtre_entrant '{ type filter hook input priority 0 ; }'
sudo nft add rule inet lab_table filtre_entrant icmp type echo-request counter accept
sudo nft list ruleset
```

Petite galère avec Zsh : les accolades `{}` sont interprétées par le shell, donc il faut les protéger avec des guillemets simples. Un truc qui m'a pris 5 minutes à comprendre.

![nft list ruleset](../screenshots/Module11-Linux-Internals/Screenshot%20from%202026-08-01%2000-47-48.png)
![nft add chain + rules](../screenshots/Module11-Linux-Internals/Screenshot%20from%202026-08-01%2000-49-14.png)

Le `list ruleset` montre que ma table `lab_table` coexiste avec les tables UFW et Docker existantes. Chaque outil a son propre espace, ils ne se marchent pas dessus.

---

## 11.2 — Namespaces & cgroups (isolation des processus)

### Le principe
Les namespaces c'est la base de Docker. Un conteneur c'est juste un processus Linux isolé dans son propre namespace PID/réseau/mount. Ici je fais la même chose à la main pour comprendre ce que Docker fait en coulisses.

### Isolation PID

```bash
# Sur l'hôte : 464 processus visibles
ps aux | wc -l
# → 464

# On crée une bulle isolée
sudo unshare --pid --fork --mount-proc /bin/bash

# Dans la bulle : 2 processus seulement
ps aux
# → /bin/bash (PID 1) et ps aux
```

![Namespace PID Isolation](../screenshots/Module11-Linux-Internals/Screenshot%20from%202026-08-01%2000-29-30.png)

Le résultat est spectaculaire : on passe de 464 processus visibles à seulement 2. Le bash hérite du PID 1 comme s'il était le `init` du système. Le processus est **totalement aveugle** au reste de la machine. C'est exactement ce que fait Docker quand il lance un conteneur.

### Cgroups

Après être sorti de la bulle, j'ai vérifié les contrôleurs cgroups disponibles :

```bash
cat /proc/$$/cgroup
cat /sys/fs/cgroup/cgroup.controllers
# → cpuset cpu io memory hugetlb pids rdma misc
```

![Cgroups Controllers](../screenshots/Module11-Linux-Internals/Screenshot%20from%202026-08-01%2000-33-01.png)

Les cgroups c'est le complément des namespaces : les namespaces isolent la **visibilité**, les cgroups limitent les **ressources** (CPU, RAM, nombre de processus). Ensemble, ils forment le moteur de conteneurisation.

### Bonus : strace

J'ai aussi tracé les appels système d'une commande simple avec `strace` :

```bash
strace echo "Hack the planet"
```

![strace syscalls](../screenshots/Module11-Linux-Internals/Screenshot%20from%202026-08-01%2000-38-32.png)

On voit tous les appels noyau : `execve()`, `mmap()`, `write(1, "Hack the planet\n", 16)`. Le `write` à la fin c'est l'appel système qui affiche réellement le texte à l'écran. Tout le reste c'est le chargement du binaire et de ses bibliothèques.

---

## 11.3 — Capabilities (fractionnement du pouvoir root)

### Le principe
Historiquement sous Linux, soit t'es root et tu peux tout faire, soit t'es user et tu peux rien faire. Les capabilities découpent les privilèges root en permissions granulaires. On peut donner à un programme le droit de binder un port < 1024 sans lui filer les droits root complets.

### Ce que j'ai fait

```bash
# Copier netcat
sudo cp /bin/nc /usr/bin/myserver

# Tenter d'écouter sur le port 30 (< 1024) → Permission denied
/usr/bin/myserver -l -p 30

# Donner la capability spécifique
sudo setcap 'cap_net_bind_service=+ep' /usr/bin/myserver

# Vérifier
getcap /usr/bin/myserver
# → /usr/bin/myserver cap_net_bind_service=ep
```

![Capabilities setcap](../screenshots/Module11-Linux-Internals/Screenshot%20from%202026-08-03%2013-49-26.png)

En relançant `/usr/bin/myserver -l -p 30` sans sudo, ça passe. Le binaire a uniquement le droit de binder un port bas, rien d'autre. C'est du moindre privilège appliqué au niveau du noyau. En prod, c'est comme ça qu'un Nginx peut écouter sur le port 80 sans tourner en root.

---

## 11.4 — Audit du noyau (AppArmor & auditd)

### AppArmor
```bash
sudo aa-status
# → 129 profils en mode "enforce"
```

AppArmor c'est du MAC (Mandatory Access Control). Même si un processus tourne en root, AppArmor peut lui interdire de lire certains fichiers ou d'exécuter certains binaires. C'est la dernière ligne de défense.

### auditd — journalisation forensique

J'ai installé auditd et posé un piège sur `/etc/passwd` :

```bash
sudo apt install auditd -y
sudo auditctl -w /etc/passwd -p wa -k passwd_changes
```

Le `-p wa` surveille les écritures et modifications d'attributs. Le `-k passwd_changes` c'est un tag pour retrouver les logs facilement.

Puis j'ai simulé un attaquant :
```bash
sudo useradd hacker_test
sudo userdel hacker_test
sudo ausearch -k passwd_changes
```

![auditd ausearch](../screenshots/Module11-Linux-Internals/Screenshot%20from%202026-08-03%2014-24-34.png)

Le log brut du noyau capture tout : l'exécutable utilisé (`exe="/usr/sbin/useradd"`), le timestamp, et surtout `auid=1000` — c'est mon UID **réel** d'origine. Même si j'ai fait `sudo` pour escalader, le noyau trace qui j'étais avant l'escalade. Un attaquant ne peut pas masquer son identité réelle dans les logs auditd.

---

### Ce que je retiens

Linux c'est un OS de sécurité si on sait quels boutons tourner. Les namespaces + cgroups = conteneurs, les capabilities = moindre privilège granulaire, AppArmor = MAC, et auditd = forensics. Tous ces mécanismes sont déjà là dans le noyau, il suffit de les activer. C'est la différence entre un serveur Linux "installé" et un serveur Linux "durci".

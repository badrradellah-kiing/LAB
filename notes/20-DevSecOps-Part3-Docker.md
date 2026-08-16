# Docker & conteneurs (mes notes) — Partie 3 DevSecOps

Je note tout ici comme si je l'expliquais à quelqu'un qui débute, pour que ça reste clair quand je relirai.

Mon setup : une VM `k8s-node` (Ubuntu Server) en NAT, avec Docker installé. J'y accède en SSH depuis mon hôte via un port forwarding (2222 → 22), du coup le copier-coller marche.

![Docker hello-world test](../screenshots/Module20-Docker/Screenshot%20from%202026-08-09%2002-17-47.png)

---

## Sommaire
- [C'est quoi VRAIMENT un conteneur](#cest-quoi-vraiment-un-conteneur)
- [Le truc du "groupe docker"](#le-truc-du-groupe-docker-et-de-root-ce-qui-ma-bloqué-au-début)
- [Voir l'isolation](#voir-lisolation-le-déclic)
- [Construire une image durcie](#construire-une-image-durcie)
- [Durcir l'exécution](#durcir-lexécution-le-runtime)
- [Scanner avec Trivy](#scanner-les-vulnérabilités-trivy)

---

## C'est quoi VRAIMENT un conteneur

Le truc le plus important à désapprendre : **"un conteneur c'est comme une VM mais en plus léger"** → c'est FAUX, et cette phrase cause plus de failles que n'importe quelle mauvaise config.

La différence :
- une **VM a son propre noyau** (un Linux séparé, avec un hyperviseur entre elle et le matériel)
- un **conteneur partage le noyau de l'hôte**. Pas de mur matériel, pas d'hyperviseur.

La vraie définition à retenir mot pour mot (c'est LA question d'entretien) :

> Un conteneur n'est pas un objet. C'est un **processus Linux ordinaire** à qui on a menti sur le monde. On lui a donné une vue restreinte du système de fichiers, des autres processus, du réseau, et on lui a retiré une partie de ses pouvoirs.

Un conteneur = **4 mécanismes du noyau** appliqués à un processus. Si un seul est mal configuré, l'isolation est percée :
- **namespaces** : lui mentent sur ce qu'il VOIT (ses process, son réseau, ses fichiers)
- **cgroups** : limitent ce qu'il CONSOMME (CPU, RAM, I/O)
- **capabilities** : réduisent ce qu'il PEUT FAIRE (root découpé en ~40 privilèges)
- **seccomp / LSM** : filtrent ce qu'il DEMANDE au noyau

Conséquence énorme : comme il partage le noyau de l'hôte, **une évasion de conteneur = une faille noyau**. Et surtout : **"root dans le conteneur = root sur l'hôte"** par défaut (le user namespace n'est pas activé, donc l'UID 0 du conteneur EST l'UID 0 de l'hôte).

C'est pour ça que **faire tourner un conteneur en non-root est le contrôle de sécurité le plus rentable** : un attaquant qui s'échappe d'un conteneur non-root arrive sur l'hôte comme un user sans droits, et la chaîne d'évasion ne démarre même pas.

---

## Le truc du "groupe docker" et de root (ce qui m'a bloqué au début)

J'ai mis du temps à capter ça, donc je le note bien.

Quand je tape `docker run`, il y a deux choses :
- le **client docker** (la commande que je tape) — juste un programme qui envoie des ordres
- le **démon dockerd** — un service qui tourne en permanence, EN ROOT, et qui fait le vrai boulot (créer les conteneurs, etc.). Il DOIT être root car créer des namespaces et configurer le réseau demande des privilèges noyau.

Le **groupe docker** = ceux qui ont le droit de parler au démon docker. Et comme le démon est root → **être dans le groupe docker = être root sur la machine**. Pas "presque root", root tout court. Preuve : un membre du groupe docker peut faire `docker run -v /:/host alpine ...` et lire/modifier tout le disque de l'hôte en root.

Il y a DEUX menaces différentes que je confondais :
- **menace interne** (groupe docker) : un user local escalade jusqu'à root via docker → protection = faire gaffe à qui on met dans le groupe docker
- **menace externe** (mon exemple) : un hacker compromet mon appli DANS un conteneur exposé sur Internet, puis tente de s'évader vers l'hôte → protection = tourner le conteneur en non-root + durci

Le point commun qui relie les deux : **root dans le conteneur = root sur l'hôte**. C'est ce qui rend le groupe docker dangereux ET une évasion catastrophique. D'où le contrôle qui neutralise les deux : ne pas tourner en root.

---

## Voir l'isolation (le déclic)

Le manuel insiste : on prouve, on ne suppose pas. Deux manips :

```bash
docker run --rm -it alpine sh -c 'ps aux; ip a; ls /'

docker run --rm -it --pid=host alpine ps aux | head
```

Le déclic : le conteneur n'a pas changé de nature. On lui a juste enlevé un mensonge (`--pid=host`). **L'isolation n'est pas une propriété du conteneur, c'est une CONFIGURATION.** Toute la sécurité conteneur tient dans cette phrase.

---

## Construire une image durcie

L'objectif du manuel : une image de quelques dizaines de Mo, non-root, sans shell ni gestionnaire de paquets, qui passe un scan sans CVE HIGH/CRITICAL.

### D'abord comprendre un Dockerfile

Un Dockerfile = une **recette** pour fabriquer une image. Les 4 mots-clés :
- `FROM` = l'image de base dont on part
- `RUN` = exécuté PENDANT la construction (installer/compiler)
- `COPY` = copier un fichier dans l'image
- `CMD` / `ENTRYPOINT` = exécuté au DÉMARRAGE du conteneur

Exemple bête pour capter :
```dockerfile
FROM ubuntu
CMD echo "Bonjour depuis mon conteneur !"
```
`docker build -t test:1.0 .` puis `docker run --rm test:1.0` → ça affiche le message. Voilà le mécanisme de base : recette → build → image → run.

### Le Dockerfile durci (le vrai)

```dockerfile
# ÉTAGE 1 — la cuisine (on compile, avec tous les outils)
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/api .

# ÉTAGE 2 — l'assiette finale (juste le binaire)
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/api /api
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/api"]
```

![Création du Dockerfile multi-stage](../screenshots/Module20-Docker/Screenshot%20from%202026-08-09%2013-43-00.png)

**Le concept que j'ai capté : c'est une FILTRATION.** L'étage 1 fait tout le sale boulot (compiler, avec le compilateur, les sources, les outils). L'étage 2 ne récupère QUE le binaire (`COPY --from=build`) et jette tout le reste. Comme un filtre : je garde le produit fini, je jette l'atelier.

Les 3 choix de sécurité :
1. **multi-stage** (2 `FROM`) : le compilateur et les sources ne partent PAS en prod
2. **distroless** : pas de shell, pas d'apt, pas de curl. Un attaquant qui rentre n'a aucun outil sous la main. Le gain le plus rentable.
3. **USER nonroot** : l'appli tourne non-root avant même Kubernetes.

En fait il y a DEUX filtrations qui se cumulent : le multi-stage filtre mon build, et le choix distroless filtre l'OS de base (pas de shell contrairement à ubuntu).

```bash
docker build -t mon-api:1.0 .
```

![Build de l'image Docker](../screenshots/Module20-Docker/Screenshot%20from%202026-08-09%2013-50-58.png)

### Prouver que l'image est durcie (on suppose pas, on prouve)

```bash
docker images | grep -E 'mon-api|ubuntu'

docker run --rm -it mon-api:1.0 sh

docker inspect <conteneur> --format '{{.Config.User}}'
```

Un truc qui échoue (le shell), et c'est exactement ce qu'on veut. Contre-intuitif mais c'est LA preuve que l'image est minimale.

---

## Durcir l'EXÉCUTION (le runtime)

Durcir l'image c'est la moitié. L'autre moitié : durcir COMMENT on la lance. Parce qu'une bonne image lancée avec `--pid=host` ou `--privileged` reste dangereuse.

La commande durcie :
```bash
docker run -d --name X \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --security-opt=no-new-privileges \
  --memory=256m --cpus=0.5 \
  --user 65532:65532 \
  mon-image
```

### L'épisode nginx qui m'a tout appris

J'ai voulu durcir nginx avec `--cap-drop=ALL --read-only`. **Il a CRASHÉ** (Exited). `docker logs` m'a dit pourquoi :
```
chown("/var/cache/nginx/client_temp") failed (Operation not permitted)
```

![nginx-durci Exited (crash)](../screenshots/Module20-Docker/Screenshot%20from%202026-08-12%2001-09-00.png)
nginx voulait faire un `chown`, qui a besoin de la capability `CAP_CHOWN`. Mais j'avais fait `cap-drop=ALL` → il ne l'avait plus → crash.

**Double leçon :**
1. le durcissement MORD vraiment — cap-drop a littéralement bloqué un chown au niveau noyau
2. le vrai dilemme : trop durcir = l'appli ne démarre plus. Le boulot c'est de trouver le MINIMUM : tout retirer, puis rajouter juste ce qu'il faut.

La réparation :
```bash
docker run -d --name nginx-durci --read-only \
  --tmpfs /var/cache/nginx --tmpfs /var/run --tmpfs /tmp \
  --cap-drop=ALL --cap-add=NET_BIND_SERVICE \
  --cap-add=CHOWN --cap-add=SETUID --cap-add=SETGID \
  --security-opt=no-new-privileges nginx
```
Cette fois : `Up` (il tourne) ET `docker exec ... touch /x` → `Read-only file system` (il est protégé). L'équilibre parfait : durci ET fonctionnel.

![nginx-durci fonctionnel avec filesystem en lecture seule](../screenshots/Module20-Docker/Screenshot%20from%202026-08-12%2001-10-50.png)

**Morale** : c'est plus facile de construire durci dès le départ (ma distroless n'avait AUCUN de ces problèmes) que de durcir après coup une image classique qui suppose avoir des privilèges. C'est pour ça qu'on construit durci d'abord.

---

## Scanner les vulnérabilités (Trivy)

Même une image bien construite peut cacher des bibliothèques avec des failles connues (CVE), invisibles à l'œil nu. On scanne AVANT de déployer (shift left), pas après l'incident.

```bash
trivy image mon-api:1.0
trivy image --severity HIGH,CRITICAL node:18
```

![Trivy scan ubuntu sans vulnérabilités](../screenshots/Module20-Docker/Screenshot%20from%202026-08-12%2001-12-27.png)

### Ce que j'ai observé (le contraste)
- `mon-api` (distroless + binaire Go) → **0 CVE**
- `ubuntu:26.04` (récent) → **0 CVE** (surprise, mais logique : image fraîche, patchée)
- `node:18` (image applicative lourde + vieillissante) → **plein de CVE HIGH/CRITICAL**

**La vraie leçon** : le nombre de CVE dépend de 2 choses :
1. la **surface** (combien de composants — node:18 embarque un OS Debian complet + des dizaines de libs, ma distroless en a ~1)
2. la **fraîcheur** (une image figée accumule des CVE avec le temps, à mesure qu'on découvre des failles dans ses composants)

Ma distroless gagne sur les deux. → **Le choix de l'image de base est ma première décision de sécurité.**

### Les flags pro
```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed node:18
```
- `--severity HIGH,CRITICAL` → ignorer le bruit LOW/MEDIUM
- `--ignore-unfixed` → ne montrer que les CVE CORRIGEABLES (patch dispo). Transforme "3000 CVE effrayantes" en "12 que je peux corriger maintenant".

Face à une image pleine de CVE, on ne panique pas : on filtre (severity + ignore-unfixed), on reconstruit sur une base à jour (beaucoup disparaissent), et ce qui reste se décide au cas par cas. "Du bruit à la décision" — c'est un chapitre à part plus tard (Partie 15).

---

## Ce que je retiens (takeaways)

1. un conteneur = un processus à qui on ment, isolé par 4 mécanismes noyau (namespaces, cgroups, capabilities, seccomp). Pas une VM.
2. root dans le conteneur = root sur l'hôte → **non-root est le contrôle roi**.
3. groupe docker = root sur la machine (menace interne ≠ menace externe/évasion, mais même cause racine).
4. l'isolation est une CONFIGURATION, pas une propriété (`--pid=host` la fait disparaître).
5. image durcie = filtration multi-stage + distroless + non-root. Construire durci dès le départ, pas après coup.
6. durcissement runtime : read-only, cap-drop=ALL puis rajouter le minimum, no-new-privileges. Trop durcir peut casser l'appli (l'épisode nginx).
7. on PROUVE toujours par un test qui doit échouer (shell absent, touch bloqué).
8. le choix de l'image de base = première décision sécu. Minimal + frais = quasi 0 CVE.

## Les pièges que je veux plus refaire
- `mkdir X && cd X` qui échoue si X existe déjà → mes fichiers finissent dans le mauvais dossier (mes cat > créés dans ~ au lieu de ~/mon-api).
- conflit de nom de conteneur → `docker rm -f <nom>` avant de relancer.
- `docker ps -a` pour voir les conteneurs arrêtés qui traînent (ils se suppriment pas seuls sans `--rm`).
- en NAT, SSH via port forwarding : `ssh -p 2222 badr@localhost` (localhost = mon hôte, pas la VM — l'hôte redirige vers la VM).

---

## Statut
- [x] Ce qu'est un conteneur (4 mécanismes noyau) — compris
- [x] Voir l'isolation exister et disparaître — fait
- [x] Construire une image durcie (multi-stage/filtration, distroless, non-root) — fait
- [x] Prouver le durcissement image (taille, pas de shell, non-root) — fait
- [x] Durcir le runtime + trouver l'équilibre (épisode nginx) — fait
- [x] Scanner avec Trivy + comprendre le contraste — fait

Chapitre Docker terminé. C'est le socle de tout Kubernetes (le manuel insiste : les capabilities et namespaces vus ici reviennent en Pod Security plus tard).

Prochain : rattraper **Git (Partie 2)** puis monter la **zone réseau CLUSTER (Partie 1)** avant d'attaquer Kubernetes.

# Partie 6 — Cycle de vie et exploitation d'un cluster Kubernetes
## Mes notes complètes


**Ce que j'ai fait :** monté un cluster Kubernetes volontairement vieux, puis je l'ai mis à jour jusqu'à la version actuelle sans jamais couper le service. Et j'ai cassé plein de trucs au passage.
**Mon environnement :** VM `k8s-node` (Ubuntu), cluster kind `lab-n2` à 3 nœuds.
**Trajet fait :** 1.34.8 → 1.35.5 → 1.36.1

---

# SOMMAIRE

**Partie A — Comprendre le problème**
1. [Pourquoi cette partie existe](#a1)
2. [Le vocabulaire des versions : N, N−1, N−2](#a2)
3. [La règle du version skew](#a3)

**Partie B — Le drain, découvert en cassant**
4. [Ma première tentative : le drain sur un seul nœud](#b4)
5. [Le pod orphelin qui bloque tout](#b5)
6. [Monter un vrai cluster à 3 nœuds (et la panne inotify)](#b6)
7. [Le drain qui marche vraiment](#b7)
8. [Cordon, drain, uncordon : le cycle complet](#b8)

**Partie C — L'upgrade**
9. [Pourquoi le control-plane en premier](#c9)
10. [Pourquoi `apt install` ne marchait pas chez moi](#c10)
11. [`kubeadm upgrade plan` : regarder avant de toucher](#c11)
12. [L'erreur SystemVerification](#c12)
13. [Ce qui se passe vraiment : les static pods](#c13)
14. [La rotation des certificats](#c14)
15. [Le piège du `kubectl get nodes`](#c15)
16. [Copier un binaire ne suffit pas](#c16)
17. [Le 403 après le redémarrage](#c17)
18. [Les workers, un par un](#c18)

**Partie D — Le PodDisruptionBudget**
19. [Le problème que j'ai vu de mes yeux](#d19)
20. [Créer un PDB et le voir travailler](#d20)
21. [Provoquer un upgrade qui ne finit jamais](#d21)

**Partie E — Les pannes d'environnement**
22. [Le disque plein, et LVM qui me sauve](#e22)

**Partie F — L'autre méthode**
23. [Patching en place vs remplacement immuable](#f23)

**Partie G — Ce qu'il faut faire AVANT un upgrade**
24. [Les APIs dépréciées : la cause n°1 des upgrades ratés](#g24)
25. [Sauvegarder etcd (et vérifier la sauvegarde)](#g25)

**Partie H — Exploiter au quotidien**
26. [Capacity planning : requests vs réel](#h26)
27. [kured : automatiser les redémarrages](#h27)

**Partie I — Le livrable**
28. [Mon runbook d'upgrade](#i28)
29. [Ce que je dois savoir dire en entretien](#i29)
30. [Ce qui reste à faire](#i30)

---
---

# PARTIE A — COMPRENDRE LE PROBLÈME

<a name="a1"></a>
## 1. Pourquoi cette partie existe

### Le problème en une phrase

Kubernetes sort une nouvelle version tous les 4 mois environ. L'ancienne finit par ne plus recevoir de correctifs de sécurité. Donc un jour, il faut mettre le cluster à jour.

**Sauf qu'un cluster fait tourner des applications.** Et personne n'a le droit de dire « je coupe le service deux heures pour faire une mise à jour ».

Donc il faut le faire **pendant que ça tourne**.

### À quoi ça me sert

C'est une question d'entretien standard pour un poste plateforme : *« raconte-moi ton dernier upgrade de cluster »*. La plupart des candidats n'en ont jamais fait un — ils récitent la doc officielle.

Moi je peux raconter celui-là, avec les emmerdes que j'ai rencontrées et les durées que j'ai mesurées. Ça ne s'invente pas.

### Pourquoi on fait ça sur kind et pas sur du vrai

Cette partie est à faire intégralement sur k8s-lab (kind) : c'est exactement pour ces exercices destructifs qu'on a gardé un cluster jetable.

**La raison :** on va délibérément casser des choses. Provoquer un upgrade qui échoue, bloquer un drain, faire expirer des certificats. On ne fait pas ça sur une infra qu'on veut garder.

---

<a name="a2"></a>
## 2. Le vocabulaire des versions : N, N−1, N−2

### Ce que ça veut dire

**N n'est pas un nombre. C'est une position dans une file.**

N = la dernière version disponible. Quand une nouvelle sort, tout le monde recule d'un cran.

Dans `1.34.8` :

| Chiffre | Nom | Ce que c'est |
|---|---|---|
| `1` | majeur | ne bouge jamais |
| `34` | **mineur** | **c'est lui qui compte** |
| `8` | patch | correctifs à l'intérieur de la mineure |

Chez moi, en août 2026 :

| Position | Version |
|---|---|
| **N** | 1.36 |
| **N−1** | 1.35 |
| **N−2** | 1.34 |

« Cluster N−2 » veut juste dire **« cluster qui a deux versions de retard »**.

### Pourquoi parler en N et pas en « 1.34 »

Parce que dans six mois, 1.37 sera sortie. Mon N−2 ne sera plus 1.34, ce sera 1.35.

Si on disait « monte un cluster 1.34 », l'exercice serait vite périmé. En écrivant N−2, on décrit une **situation** — « être en retard de deux crans » — qui reste vraie pour toujours.

C'est le même réflexe que dans mon lab réseau : on ne dit pas « la machine 10.10.10.5 », on dit « l'annuaire ».

### Pourquoi DEUX de retard, et pas un ou trois

Une version Kubernetes est supportée **environ 14 mois**. Trois sorties par an = une tous les 4 mois. Donc si je ne fais rien pendant **8 mois**, je suis à N−2.

Une entreprise qui a eu un trimestre chargé, un départ dans l'équipe, un projet prioritaire — elle est à N−2 sans avoir rien décidé. **C'est la situation la plus banale du monde réel.**

Et à N−2, **je ne peux plus sauter** (voir la règle du skew juste après). Je dois faire **deux upgrades enchaînés**, avec un cluster qui doit rester sain entre les deux.

| Point de départ | Ce que ça apprend |
|---|---|
| N−1 | un seul upgrade → la mécanique, mais pas la contrainte |
| **N−2** | **deux upgrades → la contrainte du skew mord vraiment** |
| N−3 ou pire | trois ou quatre montées → « l'exercice le plus risqué qui soit » |

**N−2 est le point d'équilibre.** Assez en retard pour que le skew m'impose un palier, pas assez pour que ce soit ingérable.

### L'image mentale que je garde

Un escalier où une marche apparaît en haut tous les 4 mois. Je suis deux marches sous le sommet. Je ne peux monter qu'**une marche à la fois**. Et pendant que je monte, une nouvelle marche peut apparaître en haut : je n'ai pas reculé, mais l'écart s'est recreusé.

**C'est pour ça qu'on ne « finit » jamais un upgrade — on entretient un rythme.**

---

<a name="a3"></a>
## 3. La règle du version skew

### Qui parle à qui dans un cluster

Il faut d'abord que je sache qui est qui :

- **`lab-n2-control-plane`** = le chef. Il donne les ordres et garde la mémoire du cluster.
- **`lab-n2-worker`** et **`lab-n2-worker2`** = les ouvriers. Ils font tourner mes pods.

Et deux programmes :

**L'API server** vit sur le chef. C'est le guichet unique : quand je tape `kubectl get pods`, ma commande lui parle. Il est le seul à écrire dans la base du cluster. Tout passe par lui.

**Le kubelet** vit sur chaque machine (le chef en a un aussi). C'est l'agent qui exécute. Son travail : demander à l'API server « qu'est-ce que je dois faire tourner ? », puis le faire.

**Donc en permanence, le kubelet parle à l'API server.** Ils discutent sans arrêt.

### Le problème

Ils discutent dans un langage. Et ce langage évolue à chaque version : la 1.35 ajoute des mots que la 1.34 ne connaît pas.

| Cas | Situation | Verdict | Pourquoi |
|---|---|---|---|
| **A** | API server 1.35, kubelet 1.34 | ✅ **OK** | Le chef sait encore parler l'ancien langage. Les développeurs de Kubernetes l'ont fait exprès. Il s'adapte à l'ouvrier. |
| **B** | API server 1.34, kubelet 1.35 | ❌ **INTERDIT** | L'ouvrier utilise des mots que le chef ne connaît pas. Personne n'a prévu ça — le chef n'a aucune raison de comprendre le futur. |

### La règle, en une phrase

> **Le kubelet peut être en RETARD sur l'API server. Jamais en AVANCE.**

En pratique, l'écart toléré est d'une ou deux mineures selon les composants, mais le sens compte plus que le chiffre : **le chef devant, les ouvriers derrière**.

### Ce que ça implique pour l'ordre de l'upgrade

- Si je monte un worker en premier → je suis dans le **cas B** pendant tout le temps où le chef est encore en 1.34. **Interdit.**
- Si je monte le chef en premier → je suis dans le **cas A** : chef en 1.35, ouvriers en 1.34. **Autorisé.** Je peux prendre mon temps ensuite.

> **Le chef d'abord, parce que c'est le seul ordre qui ne traverse jamais une situation interdite.**

### Je l'ai vu en vrai

Après l'upgrade du control-plane, mon cluster affichait :

```
Server Version: v1.35.5        ← le chef
lab-n2-worker    v1.34.8       ← les ouvriers
lab-n2-worker2   v1.34.8
```

Chef en avance, ouvriers en retard. C'était le **cas A**, et le cluster tournait très bien. **Ce n'est pas un état sale, c'est un état de transition prévu.**

---
---

# PARTIE B — LE DRAIN, DÉCOUVERT EN CASSANT

<a name="b4"></a>
## 4. Ma première tentative : le drain sur un seul nœud

### Ce que j'ai voulu faire

Retirer un nœud du service pendant qu'une application tourne dessus. C'est ce qu'on fait en vrai avant de mettre un serveur à jour : on le vide d'abord.

```bash
kubectl drain lab-control-plane --ignore-daemonsets --delete-emptydir-data
```

### Ce que fait `drain`

Il dit à Kubernetes : *« je vais toucher à ce serveur, sors-moi tout ce qui tourne dessus »*.

**Les deux options, expliquées :**

**`--ignore-daemonsets`**
Un DaemonSet est un type de charge qui tourne **sur chaque nœud par définition** — le CNI (le réseau), `kube-proxy`, un agent de logs. Les évincer n'a aucun sens : ils reviendraient aussitôt puisque leur raison d'être est d'être partout. Donc on dit à drain de les laisser tranquilles.

**`--delete-emptydir-data`**
Un volume `emptyDir` est un espace disque temporaire attaché à un pod. Si le pod part, le volume meurt avec. Cette option autorise drain à le faire.

> ⚠️ **Piège :** si une application y stocke de l'état métier, je le détruis pour de bon. Cache reconstructible = pas de problème. État métier = problème.

### Le résultat

```
node/lab-control-plane drained
```

**La commande a réussi.** Aucune erreur. Aucun avertissement.

Et pourtant : mes pods sont passés en **`Pending`**. Pas déplacés — **en attente**. Ils ne tourneraient jamais, parce qu'il n'existait aucun autre nœud où aller.

![Drain mono-nœud — pods Pending, aucun nœud disponible](../screenshots/Part6-Kubernetes-Lifecycle/drain-single-pending.png)

### Ce que j'ai compris

> **Le drain sur un nœud unique n'est pas une maintenance sans coupure. C'est une panne.**

Kubernetes m'a obéi. **Il ne m'a pas protégé de moi-même.**

C'est ce qui rend ce piège dangereux : la commande dit `drained`, tout semble s'être bien passé, et l'application est par terre.

**C'est la raison pour laquelle il faut plusieurs nœuds.** J'ai compris ça en le vivant, pas en le lisant.

### Réparer

```bash
kubectl uncordon lab-control-plane
```

![uncordon — pods repartent immédiatement en Running](../screenshots/Part6-Kubernetes-Lifecycle/drain-uncordon-recovery.png)

Les pods `Pending` sont repartis dans les secondes qui ont suivi.

---

<a name="b5"></a>
## 5. Le pod orphelin qui bloque tout

### L'erreur

Avant même que le drain fonctionne, il a refusé :

```
node/lab-control-plane cordoned
error: unable to drain node "lab-control-plane" due to error:
cannot delete Pods that declare no controller (use --force to override): gouv/test-ok
```

Traduction : *« ton pod `test-ok` n'a personne au-dessus de lui. Si je le supprime, il ne reviendra jamais. Je refuse de prendre cette décision à ta place. »*

### Le diagnostic

J'ai comparé les deux pods :

```bash
kubectl get pod test-ok -n gouv -o jsonpath='{.metadata.ownerReferences}'
kubectl get pod web-7887448d46-72p8j -o jsonpath='{.metadata.ownerReferences}'
```

**Résultat :**
```
(rien du tout pour test-ok)
[{"apiVersion":"apps/v1","kind":"ReplicaSet","name":"web-7887448d46",...}]
```

**Il n'y a eu qu'une seule ligne de sortie.** `test-ok` n'a rien retourné.

### Ce que ça veut dire

`ownerReferences` = « qui est mon propriétaire ».

| Pod | Propriétaire | Ce qui se passe si on le supprime |
|---|---|---|
| `test-ok` | **aucun** | **perdu à jamais** |
| `web-...-72p8j` | ReplicaSet `web-7887448d46` | **recréé ailleurs automatiquement** |

Le ReplicaSet a un seul travail : maintenir 3 pods `web` en vie. J'en supprime un, il en refait un.

`test-ok`, je l'avais créé à la main pendant la Partie 5. Personne ne veille sur lui.

### Le principe fondamental

> **Un drain déplace, il ne détruit pas. Donc je ne peux vider un serveur sans coupure que si ce qui tourne dessus est REMPLAÇABLE.**

**Un seul pod orphelin bloque toute la maintenance d'un nœud.**

### Comment débloquer — et ce que ça dit de moi

Deux options qui ont le même effet technique mais pas le même sens :

| Option | Commentaire |
|---|---|
| `--force` | tue le pod et on n'en parle plus. Rapide, mais **aveugle et destructif** |
| Le supprimer sciemment avant | même effet, mais **c'est moi qui décide** |

```bash
kubectl delete pod test-ok -n gouv
```

> **En production, on ne met jamais `--force` sans avoir regardé ce qu'il y a dedans.** C'est le réflexe qui distingue quelqu'un qui a déjà fait des maintenances de quelqu'un qui a lu la doc.

---

<a name="b6"></a>
## 6. Monter un vrai cluster à 3 nœuds (et la panne inotify)

### Pourquoi un nouveau cluster

Mon cluster `lab` était déjà en 1.36 — la version d'arrivée. **On ne peut pas s'entraîner à monter en version sur un cluster déjà à jour.** Il faut délibérément se mettre en retard pour vivre le trajet.

### Le fichier de topologie

```bash
mkdir -p ~/lab-p6 && cd ~/lab-p6
```

```bash
cat > kind-n2.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: lab-n2
nodes:
  - role: control-plane
    image: kindest/node:v1.34.8
  - role: worker
    image: kindest/node:v1.34.8
  - role: worker
    image: kindest/node:v1.34.8
EOF
```

### Pourquoi un fichier et pas des options en ligne de commande

**Raison 1 — les images sont épinglées explicitement.**
C'est la plus importante. Sans la ligne `image:`, kind prend l'image par défaut de son binaire. Le mien est un `v0.33.0-alpha`, dont le défaut est probablement 1.36. **Je croirais monter un N−2 et j'obtiendrais un N — sans le moindre message d'erreur.** Toute la partie s'effondrerait en silence.

**Raison 2 — c'est rejouable.**
Quand je casse le cluster (et c'est le programme), je le recrée à l'identique en une commande.

**Raison 3 — c'est traçable.**
Dans six mois, ce fichier dit encore en quelle version le cluster a été monté. Un `--image` tapé en ligne de commande, je ne le retrouve nulle part.

### Pourquoi 3 nœuds

- **1 control-plane** : le chef.
- **2 workers** : parce qu'un pod évincé doit avoir un endroit où atterrir. Avec un seul worker, drainer ne produit que des `Pending` — c'est ce que j'ai vécu au chapitre 4.

### Pourquoi `name: lab-n2`

Ça produit un contexte kubectl `kind-lab-n2`, distinct de `kind-lab`. **C'est ma protection contre le drain lancé sur le mauvais cluster.**

### Le premier échec

```
✗ Joining worker nodes 🚜
[kubelet-check] The kubelet is not healthy after 4m0.000364606s
ERROR: failed to create cluster: failed to join node with kubeadm
```

Le control-plane est monté, les workers ont refusé de rejoindre. Et kind a tout supprimé derrière lui, donc plus de logs.

### Le diagnostic

```bash
sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches
free -h
docker ps -a --format '{{.Names}}\t{{.Status}}'
```

**Résultat :**
```
fs.inotify.max_user_instances = 128       ← LE COUPABLE
fs.inotify.max_user_watches = 59508
Mem: 7,3Gi   available 5,9Gi              ← RAM hors de cause
```

### Ce qu'est `inotify` et pourquoi ça m'a bloqué

`inotify` est le mécanisme du noyau Linux qui permet à un programme de dire : *« préviens-moi si ce fichier change »*.

**Le kubelet s'en sert énormément** — il surveille ses ConfigMaps, ses secrets, ses manifests. Chaque programme qui l'utilise ouvre une « instance ».

Le noyau en autorise **128 par utilisateur, pour toute la machine**.

**Le point clé que je dois retenir :** mes nœuds kind sont des **conteneurs**, donc ils **partagent le noyau de la VM**. Ce n'est pas 128 par nœud — c'est **128 pour tout le monde**.

Avec `lab` qui tournait déjà plus trois nouveaux nœuds, le quota a explosé. Le kubelet du worker n'a pas pu s'initialiser, **il est mort en silence**, et kubeadm a juste constaté qu'il ne répondait pas au bout de 4 minutes.

### Le correctif

```bash
sudo sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_user_watches=524288
```

```bash
echo -e "fs.inotify.max_user_instances=1024\nfs.inotify.max_user_watches=524288" \
  | sudo tee /etc/sysctl.d/99-kind.conf
```

**Pourquoi deux commandes :**
- La première applique **immédiatement**, mais c'est perdu au prochain reboot.
- La seconde écrit le réglage dans `/etc/sysctl.d/`, qui est lu au démarrage. **C'est ce qui le rend permanent.**

### Le succès

```bash
docker stop lab-control-plane
kind create cluster --config ~/lab-p6/kind-n2.yaml
```

![inotify corrigé + cluster 3 nœuds lab-n2 créé en v1.34.8](../screenshots/Part6-Kubernetes-Lifecycle/inotify-cluster-success.png)

```
✓ Joining worker nodes 🚜
Set kubectl context to "kind-lab-n2"
```

```
NAME                   STATUS   ROLES           AGE   VERSION
lab-n2-control-plane   Ready    control-plane   56s   v1.34.8
lab-n2-worker          Ready    <none>          45s   v1.34.8
lab-n2-worker2         Ready    <none>          46s   v1.34.8
```

### La leçon

> **Ce n'est presque jamais Kubernetes qui casse.** Cette panne venait d'une limite du noyau de l'hôte, et elle n'est dans aucune doc basique.

---

<a name="b7"></a>
## 7. Le drain qui marche vraiment

### Déployer quelque chose à déplacer

```bash
kubectl create deployment web --image=nginx:alpine --replicas=4
kubectl get pods -o wide
```

**Résultat :**
```
web-6d689fbfdf-6qbzl   lab-n2-worker
web-6d689fbfdf-85wm9   lab-n2-worker2
web-6d689fbfdf-r7hww   lab-n2-worker
web-6d689fbfdf-vgfrw   lab-n2-worker2
```

**Deux observations :**

1. **Le scheduler a réparti 2/2 tout seul.** Je ne lui ai rien demandé.
2. **Zéro pod sur le control-plane.** Il porte une marque (un *taint*) qui le protège des charges applicatives — son travail c'est de piloter, pas de faire tourner mes apps.

**Pourquoi 4 réplicas :** il m'en faut assez pour qu'ils se répartissent sur mes deux workers, et que je voie la migration quand j'en viderai un.

### Le drain

```bash
kubectl drain lab-n2-worker --ignore-daemonsets --delete-emptydir-data
```

**Sortie :**
```
node/lab-n2-worker cordoned
Warning: ignoring DaemonSet-managed Pods: kube-system/kindnet-jlqw7, kube-system/kube-proxy-vj68t
evicting pod default/web-6d689fbfdf-r7hww
evicting pod default/web-6d689fbfdf-6qbzl
pod/web-6d689fbfdf-r7hww evicted
pod/web-6d689fbfdf-6qbzl evicted
node/lab-n2-worker drained
```

![Drain multi-nœuds — pods évincés de worker, recréés sur worker2](../screenshots/Part6-Kubernetes-Lifecycle/drain-multi-node.png)

**La sortie raconte tout l'ordre des opérations :**

| Ligne | Ce qui se passe |
|---|---|
| `cordoned` | le nœud est marqué « ne plus rien planifier ici » |
| `ignoring DaemonSet-managed Pods` | le CNI et kube-proxy sont laissés tranquilles |
| `evicting pod...` | Kubernetes demande poliment aux pods de partir |
| `evicted` | ils sont sortis |
| `drained` | le nœud est vide |

### Le résultat

```bash
kubectl get pods -o wide
```

```
web-6d689fbfdf-85wm9   Running   61m   lab-n2-worker2   ← n'a pas bougé
web-6d689fbfdf-g6jr7   Running   5s    lab-n2-worker2   ← RECRÉÉ
web-6d689fbfdf-r4h2b   Running   5s    lab-n2-worker2   ← RECRÉÉ
web-6d689fbfdf-vgfrw   Running   61m   lab-n2-worker2   ← n'a pas bougé
```

### La comparaison avec ma première tentative

| | `lab` (1 nœud) | `lab-n2` (3 nœuds) |
|---|---|---|
| Résultat | pods en `Pending` | pods `Running` sur `worker2` |
| Service | **mort** | **debout** |

**C'est ça, une maintenance sans coupure.**

### Le point le plus important de tout le chapitre

> **Les pods n'ont pas été « déplacés ». Ils ont été TUÉS et REFAITS ailleurs.**

**Un pod ne voyage jamais.**

Les âges le prouvent : `61m` pour ceux qui n'ont pas bougé, `5s` pour les nouveaux. Ce ne sont pas les mêmes pods — ils ont même des noms différents.

**C'est pour ça qu'ils doivent être remplaçables**, et pourquoi mon pod orphelin `test-ok` bloquait tout au chapitre 5. Tout se tient.

### Le nouveau problème que ça crée

Mes 4 pods sont maintenant sur **un seul** nœud. **Si `worker2` tombe maintenant, je perds tout.**

C'est le prix de la maintenance : **pendant qu'un nœud est en travaux, je suis plus fragile.** Et rien ne m'a empêché de tout entasser — Kubernetes m'a laissé faire, comme il m'a laissé tuer mon appli au chapitre 4.

Le garde-fou qui manque s'appelle un **PDB**. → chapitre 19.

---

<a name="b8"></a>
## 8. Cordon, drain, uncordon : le cycle complet

### Ce que j'ai vu

```bash
kubectl get nodes
```

```
lab-n2-worker   Ready,SchedulingDisabled   <none>   v1.34.8
```

### Ce que veut dire `SchedulingDisabled`

Le **scheduler** est le composant de Kubernetes qui décide **sur quel nœud** va tourner chaque nouveau pod. À chaque création de pod, c'est lui qui choisit.

`SchedulingDisabled` = **le scheduler a interdiction de choisir ce nœud**. Il est exclu de la liste des candidats.

### Deux choses à bien distinguer

**1. `cordon` ne vide pas le nœud.**
Il empêche les **nouveaux** pods d'arriver. C'est `drain` qui fait sortir les pods **existants**. Ma commande a fait les deux à la suite : d'abord `cordoned`, puis `evicting`.

**2. Le nœud reste `Ready`.**
Regarde bien : `Ready,SchedulingDisabled`. Il est en parfaite santé, il répond, il pourrait travailler. **Il est juste mis de côté volontairement.**

### Pourquoi cet ordre est vital

Si Kubernetes vidait le nœud **sans** le cordonner d'abord, le scheduler pourrait y remettre des pods pendant que je le vide. **Je viderais d'un côté pendant que ça se remplit de l'autre. À l'infini.**

> **Le cordon ferme la porte, le drain sort les gens.**

**L'image que je garde :** le panneau « caisse fermée » au supermarché. Plus de nouveaux clients dans la file, mais on finit de servir ceux qui y sont.

### Le cycle complet

```
cordon  →  drain  →  [je fais mes travaux]  →  uncordon
```

```bash
kubectl uncordon lab-n2-worker
```

![uncordon — pods restent sur worker2, pas de rééquilibrage automatique](../screenshots/Part6-Kubernetes-Lifecycle/uncordon-no-rebalance.png)

### La surprise après `uncordon`

```
web-6d689fbfdf-85wm9   Running   99m   lab-n2-worker2
web-6d689fbfdf-g6jr7   Running   38m   lab-n2-worker2
web-6d689fbfdf-r4h2b   Running   38m   lab-n2-worker2
web-6d689fbfdf-vgfrw   Running   99m   lab-n2-worker2
```

**Les pods ne sont PAS revenus.** `worker` est vide, `worker2` est chargé.

### Pourquoi — à retenir absolument

> **Kubernetes ne rééquilibre pas.**

Le scheduler ne décide qu'au moment où un pod **naît**. Un pod déjà en vie **ne bouge jamais tout seul**.

Pour rééquilibrer, il faut :
- soit tuer des pods (ils renaîtront ailleurs)
- soit un outil dédié (`descheduler`)

**C'est une question d'entretien fréquente.**

---
---

# PARTIE C — L'UPGRADE

<a name="c9"></a>
## 9. Pourquoi le control-plane en premier

*(Voir chapitre 3 pour le raisonnement complet.)*

**En résumé :** le kubelet peut être en retard sur l'API server, jamais en avance. Donc :

```
1. Control-plane (le chef)
2. Workers, un par un (les ouvriers)
```

C'est **le seul ordre qui ne traverse jamais une situation interdite**.

---

<a name="c10"></a>
## 10. Pourquoi `apt install` ne marchait pas chez moi

### Ce que dit la doc standard

```
sudo apt install -y kubeadm=1.31.4-1.1
```

Traduction : *« apt, va chercher le programme `kubeadm` dans cette version et installe-le »*. C'est la façon normale d'installer un logiciel sur Ubuntu.

### J'ai vérifié si ça marcherait chez moi

```bash
docker exec -it lab-n2-worker bash
kubelet --version
which kubelet kubeadm
apt-cache policy kubelet
```

**Résultat :**
```
Kubernetes v1.34.8
/usr/bin/kubelet
/usr/bin/kubeadm
(RIEN pour apt-cache policy)
```

### Ce vide est la réponse

`apt` ne connaît que les logiciels **qu'il a lui-même installés**, depuis des dépôts qu'on lui a déclarés.

Or dans mon nœud, `kubelet` et `kubeadm` **n'ont jamais été installés par apt**. Les gens de kind les ont **copiés directement** dans `/usr/bin/` quand ils ont fabriqué l'image du conteneur.

**Comparaison :** c'est comme un fichier `.exe` que quelqu'un aurait posé sur mon bureau. Windows Update ne le mettra jamais à jour — il ne sait même pas qu'il existe.

### Ce que j'ai dû faire à la place

Puisque `apt` ne peut pas faire le travail, je l'ai fait moi-même. **Deux gestes.**

**1. Télécharger les binaires depuis le site officiel de Kubernetes :**

```bash
cd ~/lab-p6
curl -sSLO https://dl.k8s.io/v1.35.5/bin/linux/amd64/kubelet
curl -sSLO https://dl.k8s.io/v1.35.5/bin/linux/amd64/kubeadm
chmod +x kubelet kubeadm
```

Deux binaires seulement. `kubectl` n'est pas nécessaire sur un worker.

**2. Vérifier qu'ils sont bien ce qu'ils prétendent :**

```bash
./kubeadm version -o short
./kubelet --version
```
```
v1.35.5
Kubernetes v1.35.5
```

**Pourquoi cette vérification est obligatoire :** je vais remplacer les binaires qui font tourner un nœud Kubernetes par des fichiers téléchargés sur Internet. Un `curl -sSL` **silencieux** peut très bien avoir récupéré une page d'erreur HTML de 70 Mo. Et tester la version prouve aussi que le fichier **s'exécute**.

*(En production, on vérifie aussi la somme de contrôle publiée par le projet — c'est ce qui garantit que personne n'a substitué le binaire en route.)*

**3. Les copier dans le conteneur, par-dessus les anciens :**

```bash
docker cp kubeadm lab-n2-control-plane:/usr/bin/kubeadm
```

`docker cp` = « copie ce fichier de ma VM vers l'intérieur du conteneur ». La destination `/usr/bin/kubeadm` est exactement là où était l'ancien → **je l'écrase**.

---

<a name="c11"></a>
## 11. `kubeadm upgrade plan` : regarder avant de toucher

```bash
docker exec lab-n2-control-plane kubeadm upgrade plan
```

![kubeadm upgrade plan — composants CURRENT → TARGET, version skew appliqué](../screenshots/Part6-Kubernetes-Lifecycle/upgrade-plan.png)

![upgrade plan détail — falling back to stable-1.35, kubelet targets](../screenshots/Part6-Kubernetes-Lifecycle/upgrade-plan-detail.png)

Traduction : *« dis-moi ce que tu ferais, mais ne fais rien »*.

**Cette commande ne modifie RIEN.** Elle inspecte et rapporte. Il faut lire ce qu'il va faire.

### Enseignement 1 — il a refusé de me proposer la 1.36

```
I0817 15:08:34 version.go:260] remote version is much newer: v1.36.3;
falling back to: stable-1.35
```

**kubeadm est allé voir quelle est la dernière version de Kubernetes. Il a trouvé 1.36.3. Et il a dit : *non, trop loin pour toi, je te ramène à 1.35*.**

> **C'est la règle « pas de saut de version », appliquée par l'outil lui-même. Je ne pourrais pas sauter même si je le voulais.**

### Enseignement 2 — six programmes à changer, pas un

```
kube-apiserver            v1.34.8 → v1.35.7
kube-controller-manager   v1.34.8 → v1.35.7
kube-scheduler            v1.34.8 → v1.35.7
kube-proxy                1.34.8  → v1.35.7
CoreDNS                   v1.12.1 → v1.13.1
etcd                      3.6.5-0 → 3.6.6-0
```

**« Mettre à jour le control-plane » veut dire mettre à jour ces six-là.** Ce n'est pas un binaire.

Note que **CoreDNS et etcd suivent leur propre numérotation** — ce ne sont pas des composants Kubernetes à proprement parler, mais des briques que Kubernetes embarque.

### Enseignement 3 — ce qu'il ne fera PAS

```
Components that must be upgraded manually after you have upgraded
the control plane with 'kubeadm upgrade apply':
kubelet   lab-n2-control-plane   v1.34.8 → ...
kubelet   lab-n2-worker          v1.34.8 → ...
kubelet   lab-n2-worker2         v1.34.8 → ...
```

> **kubeadm ne touche PAS aux kubelet.** Ni sur les workers, ni même sur le chef.

**C'est mon travail après.** Et c'est ce qui explique la surprise du chapitre 15.

### Un détail sur la version cible

kubeadm disait `Target version: v1.35.7`, mais mon binaire était en **1.35.5**. J'ai donc visé explicitement `v1.35.5` :
- mes images kind existent en 1.35.5
- ça garde la cohérence avec les binaires téléchargés

kubeadm accepte qu'on lui donne explicitement la version qui correspond à la sienne.

---

<a name="c12"></a>
## 12. L'erreur SystemVerification

### L'échec

```bash
docker exec lab-n2-control-plane kubeadm upgrade apply v1.35.5 -y
```

![ERROR SystemVerification — module configs non chargeable, mais cgroups tous enabled](../screenshots/Part6-Kubernetes-Lifecycle/systemverification-error.png)

```
[preflight] Some fatal errors occurred:
  [ERROR SystemVerification]: failed to parse kernel config: unable to load
  kernel module: "configs", output: "modprobe: FATAL: Module configs not found
  in directory /lib/modules/7.0.0-29-generic"
error: error execution phase preflight: preflight checks failed
```

### Ce que kubeadm essayait de faire

Avant tout upgrade, kubeadm fait des contrôles de sécurité (*preflight checks*). L'un d'eux : *« est-ce que le noyau Linux de cette machine a les bonnes options compilées ? »*

Pour le savoir, il charge un module noyau appelé `configs`, qui expose la configuration du noyau courant.

### Pourquoi ça échoue chez moi

**Deux raisons cumulées :**

1. Mon nœud est un **conteneur** — il n'a pas les modules du noyau de la VM montés dedans.
2. De toute façon, **un conteneur n'a pas le droit de charger un module noyau**.

### Le détail crucial : ce qu'il a QUAND MÊME réussi à lire

```
KERNEL_VERSION: 7.0.0-29-generic
OS: Linux
CGROUPS_CPU: enabled
CGROUPS_CPUSET: enabled
CGROUPS_DEVICES: enabled
CGROUPS_FREEZER: enabled
CGROUPS_MEMORY: enabled
CGROUPS_PIDS: enabled
CGROUPS_HUGETLB: enabled
CGROUPS_IO: enabled
```

**TOUT est `enabled`. Le noyau est parfaitement apte.**

> **kubeadm n'échoue pas parce qu'il manque quelque chose. Il échoue parce qu'il N'A PAS PU LIRE LE FICHIER pour le confirmer.** Il refuse de valider ce qu'il n'a pas vérifié lui-même.

C'est une **posture prudente et saine** par défaut. Mais ici, j'ai l'information sous les yeux et elle est bonne.

### Le contournement

```bash
docker exec lab-n2-control-plane kubeadm upgrade apply v1.35.5 -y \
  --ignore-preflight-errors=SystemVerification
```

**Le résultat se voit immédiatement :**
```
[WARNING SystemVerification]: failed to parse kernel config...
```

`[ERROR]` est devenu `[WARNING]`. **La vérification est toujours faite et rapportée, elle n'est simplement plus bloquante.**

### Pourquoi PAS `--ignore-preflight-errors=all`

> **Je NOMME l'erreur que j'accepte. Ça laisse TOUTES les autres vérifications actives.**

C'est la différence entre **« je sais ce que j'ignore »** et **« je ferme les yeux »**.

### Note pour le runbook

Ce contournement est nécessaire **sur chaque nœud**, pas seulement au control-plane. Dans une vraie procédure écrite, ça apparaît **une fois dans les préconditions** plutôt que d'être redécouvert à chaque machine.

---

<a name="c13"></a>
## 13. Ce qui se passe vraiment : les static pods

**C'est le morceau le plus intéressant de toute la partie. Si je ne dois retenir qu'une chose technique, c'est ça.**

### La question de départ

**Comment met-on à jour l'API server... alors que c'est lui qui répond à `kubectl` ?** Si je l'éteins pour le remplacer, je perds le contrôle du cluster.

### Le fonctionnement normal de Kubernetes

```
J'écris un YAML → kubectl → API server → base du cluster (etcd)
                                              ↓
                                    le kubelet lit et exécute
```

Le kubelet demande à l'API server quoi faire tourner.

### Le problème de l'œuf et de la poule

**Comment démarre-t-on l'API server lui-même ?** Il ne peut pas se demander à lui-même de démarrer.

### La solution : les static pods

**Le kubelet surveille aussi un dossier local :**

```
/etc/kubernetes/manifests/
```

**Tout fichier YAML posé là est démarré comme un pod, SANS passer par l'API server.**

C'est un « static pod » — *statique* parce qu'il vient d'un fichier sur le disque, pas de la base du cluster.

Sur mon control-plane, ce dossier contient :
```
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
```

> **Donc etcd, l'API server, le controller-manager et le scheduler sont des PODS**, démarrés par le kubelet à partir de fichiers locaux.

### La conséquence pour l'upgrade

> **Pour mettre à jour l'API server, kubeadm ne remplace pas un binaire. Il RÉÉCRIT UN FICHIER YAML.**

Le kubelet voit que le fichier a changé, arrête l'ancien pod, et démarre le nouveau avec la nouvelle image. **Automatiquement.**

### Le log, ligne par ligne

```
[upgrade/control-plane] Upgrading your static Pod-hosted control plane to version "v1.35.5"
[upgrade/staticpods] Writing new Static Pod manifests to "/etc/kubernetes/tmp/kubeadm-upgraded-manifests..."
[upgrade/staticpods] Preparing for "etcd" upgrade
[upgrade/staticpods] Renewing etcd-server certificate
[upgrade/staticpods] Renewing etcd-peer certificate
[upgrade/staticpods] Renewing etcd-healthcheck-client certificate
[upgrade/staticpods] Moving new manifest to "/etc/kubernetes/manifests/etcd.yaml" and
    backing up old manifest to "/etc/kubernetes/tmp/kubeadm-backup-manifests-2026-08-17-15-14-20/etcd.yaml"
[upgrade/staticpods] Waiting for the kubelet to restart the component
[upgrade/staticpods] This can take up to 5m0s
[apiclient] Found 1 Pods for label selector component=etcd
[upgrade/staticpods] Component "etcd" upgraded successfully!
[upgrade/etcd] Waiting for etcd to become available
```

| Ligne | Ce qu'elle veut dire |
|---|---|
| `Preparing for "etcd" upgrade` | on s'occupe d'etcd maintenant |
| `Renewing ... certificate` | les certificats sont renouvelés au passage (→ chapitre 14) |
| `Moving new manifest to .../etcd.yaml` | **on écrase le fichier YAML** |
| `backing up old manifest to .../kubeadm-backup-manifests-.../` | **l'ancien est sauvegardé** |
| `Waiting for the kubelet to restart the component` | kubeadm attend que le kubelet réagisse |
| `Found 1 Pods for label selector component=etcd` | le nouveau pod est là |
| `Component "etcd" upgraded successfully!` | on passe au suivant |

### Point crucial 1 — le backup, c'est mon retour arrière

```
/etc/kubernetes/tmp/kubeadm-backup-manifests-2026-08-17-15-14-20/
```

**À chaque composant, kubeadm range l'ancien fichier dans ce dossier daté.**

> **Si l'upgrade tourne mal, la récupération consiste à remettre les anciens fichiers YAML dans `/etc/kubernetes/manifests/`.** Le kubelet redémarrera les composants en ancienne version.

**C'est la ligne « procédure de retour arrière » de mon runbook.** Je note le chemin.

### Point crucial 2 — l'ordre : etcd d'abord

Le log montre l'ordre : **etcd** → **kube-apiserver** → **kube-controller-manager** → **kube-scheduler**.

**Ce n'est pas au hasard.**

**etcd est la base de données** — elle contient l'état de tout le cluster. **L'API server est le seul programme qui lui parle.**

On met à jour la base **AVANT** celui qui l'utilise. Jamais l'inverse : sinon j'aurais un API server récent qui parle à une base ancienne pendant plusieurs minutes.

**C'est la même logique que le chef avant les ouvriers, un cran plus bas.**

### Et pendant ce temps, kubectl ?

L'API server redémarre effectivement. Pendant quelques secondes, `kubectl` ne répond pas. **C'est normal et attendu** — c'est aussi pour ça que kubeadm attend et vérifie après chaque composant avant de passer au suivant.

**Sur un cluster de production sérieux, il y a TROIS control-planes**, et on les met à jour un par un : les deux autres continuent de répondre. Mon lab n'en a qu'un, donc j'ai un vrai micro-trou de contrôle.

> ⚠️ **Important : un trou d'API server n'arrête PAS mes applications.** Les pods continuent de tourner. Je perds seulement la capacité à **donner des ordres** au cluster.

### Le succès

```
[upgrade] SUCCESS! A control plane node of your cluster was upgraded to "v1.35.5".
[upgrade] Now please proceed with upgrading the rest of the nodes by following the right order.
```

![SUCCESS — control plane upgraded to v1.35.5 en 3 min 05 s](../screenshots/Part6-Kubernetes-Lifecycle/upgrade-success.png)

**Durée : 15:13:52 → 15:16:57 = 3 min 05 s.**

---

<a name="c14"></a>
## 14. La rotation des certificats

### Ce que j'ai vu passer sans l'avoir demandé

Au milieu du log d'upgrade :

```
[upgrade/staticpods] Renewing etcd-server certificate
[upgrade/staticpods] Renewing etcd-peer certificate
[upgrade/staticpods] Renewing etcd-healthcheck-client certificate
[upgrade/staticpods] Renewing apiserver certificate
[upgrade/staticpods] Renewing apiserver-kubelet-client certificate
[upgrade/staticpods] Renewing front-proxy-client certificate
[upgrade/staticpods] Renewing apiserver-etcd-client certificate
[upgrade/staticpods] Renewing scheduler.conf certificate
```

> **Un upgrade renouvelle les certificats internes du cluster.** Je n'avais rien demandé de tel.

### Pourquoi il y a des certificats partout

**Chaque composant de Kubernetes prouve son identité aux autres par un certificat.** Ce n'est pas décoratif :

| Certificat | Qui prouve quoi à qui |
|---|---|
| `apiserver` | l'API server prouve son identité à tout le monde |
| `apiserver-etcd-client` | l'API server prouve à etcd qu'il a le droit d'écrire |
| `apiserver-kubelet-client` | l'API server prouve aux kubelets qu'il est légitime |
| `etcd-server` | etcd prouve son identité à l'API server |
| `etcd-peer` | les membres etcd se prouvent leur identité entre eux |
| `etcd-healthcheck-client` | pour les sondes de santé |
| `front-proxy-client` | pour les API agrégées (ex: metrics-server) |
| `scheduler.conf` | le scheduler prouve son identité à l'API server |

**Sans ça, n'importe quel programme sur le réseau pourrait se faire passer pour l'API server et prendre le contrôle du cluster.**

C'est **le même mécanisme que ma PKI du Module 10**, appliqué à l'intérieur du cluster. Il y a une CA interne au cluster (créée par `kubeadm init`) qui signe tous ces certificats.

J'ai d'ailleurs vu cette PKI de mes yeux plus tard :

![PKI etcd — ls /etc/kubernetes/pki/etcd/ + pluto detect clean](../screenshots/Part6-Kubernetes-Lifecycle/etcd-pki-pluto.png)

```bash
docker exec lab-n2-control-plane ls -la /etc/kubernetes/pki/etcd/
```
```
ca.crt / ca.key                              ← la CA d'etcd
healthcheck-client.crt / .key
peer.crt / .key
server.crt / .key
```

### Pourquoi c'est le sujet le plus dangereux du chapitre

**Ces certificats durent environ UN AN.**

Et voilà ce qui se passe quand ils expirent :

> **Le cluster devient totalement inaccessible — Y COMPRIS POUR LE RÉPARER.**

- Je ne peux plus lancer `kubectl`, parce que mon kubeconfig contient un certificat expiré.
- Je ne peux plus joindre l'API server, parce que le sien est expiré.
- Les composants ne peuvent plus se parler entre eux.

**C'est un des rares incidents qui transforme une négligence en panne complète, sans aucun avertissement préalable.**

### L'effet pervers à connaître (et à raconter en entretien)

**Une équipe qui upgrade tous les 6 mois ne voit JAMAIS ses certificats expirer** — chaque upgrade les renouvelle silencieusement, comme je viens de le voir.

Puis un jour : l'équipe change, le projet ralentit, et **14 mois passent sans upgrade**.

**Tout tombe d'un coup. Et personne dans l'équipe n'a jamais vécu l'incident, donc personne ne sait quoi faire.**

### Les trois horloges

J'ai **trois cycles de rotation indépendants**, qui n'expirent pas ensemble et ne se surveillent pas au même endroit :

| Quoi | Durée | Ce qui casse à l'expiration |
|---|---|---|
| Certificats applicatifs (cert-manager) | **90 jours** | le service concerné, progressivement |
| **Certificats internes du cluster** | **1 an** | **tout le cluster, d'un coup, sans accès de secours** |
| Mon intermédiaire (Module 10) | **10 ans** | toute la plateforme, et je ne peux plus rien réémettre |

### Les commandes à connaître

Vérifier les dates d'expiration :
```bash
kubeadm certs check-expiration
```
*(Sur kind : `docker exec lab-n2-control-plane kubeadm certs check-expiration`)*

Renouveler manuellement, sans faire d'upgrade :
```bash
kubeadm certs renew all
systemctl restart kubelet
```

Régénérer le kubeconfig d'administration :
```bash
kubeadm init phase kubeconfig admin
```

### Le conseil

> **Mets-le en ALERTE, pas en rappel mental.** Un rappel dans un calendrier ne survit pas à un changement d'équipe.

Alerte Prometheus à 30 jours, sur la métrique :
```
apiserver_client_certificate_expiration_seconds_bucket
```

---

<a name="c15"></a>
## 15. Le piège du `kubectl get nodes`

### Ce qui m'a surpris

Après le `SUCCESS! ... upgraded to "v1.35.5"`, j'ai lancé :

```bash
kubectl get nodes
```

```
lab-n2-control-plane   Ready   control-plane   4h27m   v1.34.8   ← TOUJOURS 1.34 ?!
lab-n2-worker          Ready   <none>          4h27m   v1.34.8
lab-n2-worker2         Ready   <none>          4h27m   v1.34.8
```

**Rien n'avait bougé.** Alors que kubeadm venait de dire SUCCESS.

### L'explication

> **La colonne `VERSION` de `kubectl get nodes` affiche la version du KUBELET de ce nœud. PAS celle du cluster.**

Et je l'ai vu au chapitre 11 : **kubeadm ne touche pas aux kubelet**. Il a mis à jour les six composants du control-plane, **pas l'agent**.

Donc à ce moment-là :
- Les composants du chef : **1.35.5** ✅
- Le kubelet du chef : **encore 1.34.8**
- Les kubelets des ouvriers : **encore 1.34.8**

### Comment voir la vraie version du cluster

```bash
kubectl version
```
```
Client Version: v1.36.3
Kustomize Version: v5.8.1
Server Version: v1.35.5
```

![Le piège — get nodes dit v1.34.8 mais kubectl version confirme Server v1.35.5 + 403 transitoire](../screenshots/Part6-Kubernetes-Lifecycle/version-trap-403.png)

**`Server Version` = l'API server. C'est ÇA, la version du cluster.**

### Les trois versions en jeu, toutes légitimes

| Composant | Version | Statut |
|---|---|---|
| kubectl (mon client) | 1.36.3 | 1 mineure **en avance** — toléré |
| API server | 1.35.5 | la nouvelle référence |
| kubelets | 1.34.8 | 1 mineure **en retard** — toléré |

> **Un cluster en cours d'upgrade ressemble TOUJOURS à ça.** Ce n'est pas un état sale, c'est un état de transition prévu par la politique de skew.

### Les deux commandes à ne pas confondre

| Commande | Ce qu'elle montre |
|---|---|
| `kubectl get nodes` | la version des **kubelets** |
| `kubectl version` | la version de l'**API server** |

---

<a name="c16"></a>
## 16. Copier un binaire ne suffit pas

### Le piège

```bash
docker cp kubelet lab-n2-control-plane:/usr/bin/kubelet
```

J'ai remplacé le fichier sur le disque. Si je vérifie :

```bash
docker exec lab-n2-control-plane kubelet --version
# Kubernetes v1.35.5
```

**Ça dit 1.35.5.** Et pourtant `kubectl get nodes` continuerait d'afficher 1.34.8.

### Pourquoi

> **Le kubelet TOURNE DÉJÀ.** Le processus chargé en mémoire est l'ancien programme, celui de 1.34.8. Il a été lancé au démarrage du nœud, à partir de l'ancien fichier.

**Remplacer le fichier sur le disque ne change rien au programme déjà en cours d'exécution.** Le nouveau fichier ne sera lu qu'au prochain démarrage.

**Analogie :** je remplace le fichier d'un logiciel pendant qu'il est ouvert. La fenêtre ouverte reste l'ancienne version tant que je ne l'ai pas fermée et rouverte.

### La solution

```bash
docker exec lab-n2-control-plane systemctl restart kubelet
```

`systemctl restart` = arrêter le service et le relancer. **Au redémarrage, il charge le nouveau fichier.**

### La séquence complète — les 3 étapes sont obligatoires

```bash
docker cp kubelet <noeud>:/usr/bin/kubelet      # 1. remplacer le fichier
docker exec <noeud> systemctl restart kubelet   # 2. relancer le service
kubectl get nodes                               # 3. vérifier
```

**Aucune n'est optionnelle.** C'est un piège classique : on copie, on vérifie la version du fichier, on croit avoir fini, et rien n'a changé.

---

<a name="c17"></a>
## 17. Le 403 après le redémarrage

### Ce que j'ai vu

Juste après `systemctl restart kubelet` sur le control-plane :

```
Error from server (Forbidden): nodes is forbidden: User "kubernetes-admin"
cannot list resource "nodes" in API group "" at the cluster scope
```

### Comment lire cette erreur — c'est capital

> **Ce n'est PAS une erreur de connexion.**

- Une erreur de connexion dirait : `connection refused`, `timeout`, `no such host`. Ça voudrait dire que **l'API server ne répond pas**.
- Ici, l'API server **RÉPOND**. Il me reconnaît, il m'identifie comme `kubernetes-admin`, et il me dit **NON**.

C'est une erreur d'**autorisation** (403), pas d'authentification (401), pas de réseau.

Et c'est déroutant, parce que `kubernetes-admin` est censé être **administrateur complet** du cluster.

### La cause

Redémarrer le kubelet du control-plane a **relancé tous les static pods** — donc l'API server aussi (chapitre 13).

Au redémarrage, l'API server met quelques secondes à charger toutes ses règles RBAC (qui a le droit de faire quoi). **Pendant ce court intervalle, il répond aux requêtes mais ne connaît pas encore mes droits. Donc il refuse.**

### La résolution

**Attendre 30 secondes. Rien à corriger.**

```
lab-n2-control-plane   Ready   control-plane   4h31m   v1.35.5   ✅
```

### Pourquoi ça mérite une ligne de runbook

C'est exactement le genre de **faux incident** qui pousse quelqu'un à « réparer » un cluster qui allait bien — à recréer des RoleBindings, à retoucher le kubeconfig, **à casser des choses qui marchaient**.

> **Ligne de runbook :** *Après redémarrage du kubelet du control-plane, l'API server peut répondre en 403 pendant ~30 s le temps que le RBAC se recharge. Ne pas paniquer, ne rien corriger, attendre.*

### Le réflexe général que j'en tire

Devant une erreur pendant un upgrade, la première question est : **est-ce que le composant répond, ou est-ce qu'il est mort ?**

| Symptôme | Nature | Réaction |
|---|---|---|
| `connection refused`, `timeout` | le composant ne répond pas | il démarre peut-être, ou il est en panne |
| `403 Forbidden`, `401` | le composant répond mais refuse | question de droits ou d'état interne |

> **Une erreur qui RÉPOND est presque toujours moins grave qu'un silence.**

---

<a name="c18"></a>
## 18. Les workers, un par un

### La séquence complète, par worker

```bash
docker cp kubeadm lab-n2-worker:/usr/bin/kubeadm
docker cp kubelet lab-n2-worker:/usr/bin/kubelet

docker exec lab-n2-worker kubeadm upgrade node --ignore-preflight-errors=SystemVerification

docker exec lab-n2-worker systemctl restart kubelet

kubectl uncordon lab-n2-worker
```

### Pourquoi `kubeadm upgrade node` et pas juste redémarrer le kubelet

**Le kubelet a un fichier de configuration, et ce fichier est STOCKÉ DANS LE CLUSTER** (dans une ConfigMap nommée `kubelet-config`).

Quand j'ai mis à jour le control-plane, kubeadm a publié une **nouvelle version** de cette configuration :
```
[kubelet] Creating a ConfigMap "kubelet-config" in namespace kube-system
    with the configuration for the kubelets in the cluster
```

`kubeadm upgrade node` **va chercher cette nouvelle config et l'écrit localement** sur le nœud, dans `/var/lib/kubelet/config.yaml`.

> **Sans cette commande, je ferais tourner un kubelet 1.35 avec une configuration écrite pour 1.34.** Ça peut marcher — ou casser de manière sournoise.

### Ce que le log m'apprend

```
[upgrade/preflight] Skipping prepull. Not a control plane node.
[upgrade/control-plane] Skipping phase. Not a control plane node.
[upgrade/kubeconfig] Skipping phase. Not a control plane node.
[upgrade/kubelet-config] The kubelet configuration for this node was successfully upgraded!
[upgrade/addon] Skipping the addon/coredns phase. Not a control plane node.
[upgrade/addon] Skipping the addon/kube-proxy phase. Not a control plane node.
```

**Six lignes « Skipping », UNE SEULE ligne utile.**

kubeadm détecte qu'il est sur un worker et saute tout ce qui ne le concerne pas : pas de static pods à remplacer, pas de certificats de control-plane, pas d'add-ons à réappliquer.

**Il ne fait qu'UNE chose : récupérer la config kubelet.**

![kubeadm upgrade node — worker upgradé, kubectl get nodes montre v1.35.5](../screenshots/Part6-Kubernetes-Lifecycle/worker-upgrade-node.png)

**D'où l'écart de durée :**

| Opération | Durée |
|---|---|
| `kubeadm upgrade apply` (control-plane) | **3 min 05 s** |
| `kubeadm upgrade node` (worker) | **~1 seconde** |

### Le balancier — ce que j'ai observé

Quand j'ai drainé `worker2` (le second), les pods sont revenus sur `worker` (le premier, déjà upgradé) :

```
web-6d689fbfdf-c8ss4   Running   9s   10.244.2.6   lab-n2-worker
web-6d689fbfdf-gn6p9   Running   9s   10.244.2.7   lab-n2-worker
web-6d689fbfdf-jvd48   Running   9s   10.244.2.8   lab-n2-worker
web-6d689fbfdf-vr8dx   Running   9s   10.244.2.5   lab-n2-worker
```

![Drain worker2 — pods basculés sur worker, IPs en 10.244.2.x](../screenshots/Part6-Kubernetes-Lifecycle/worker-drain-balancier.png)

**Nouvelles IP en `10.244.2.x`** (le sous-réseau de `worker`) au lieu de `10.244.1.x` (celui de `worker2`). Chaque nœud a sa plage d'IP pour les pods.

> **C'est le mouvement de balancier qui rend la maintenance sans coupure possible :** la charge fait l'aller-retour pendant que les nœuds passent en version l'un après l'autre.

### Le problème que ça m'a révélé

**Les 4 pods ont `AGE 9s` — tous recréés EN MÊME TEMPS.** Pendant quelques secondes : **zéro pod prêt à servir**.

Et dans le log du drain :
```
evicting pod kube-system/coredns-7d764666f9-xqgqw
evicting pod kube-system/coredns-7d764666f9-2f7qk
```

**Les DEUX CoreDNS étaient sur le même nœud et sont partis ensemble.** CoreDNS = le DNS du cluster. Pendant quelques secondes, **plus aucune résolution de noms**.

→ C'est exactement ce qu'un PDB empêche. **Chapitre 19.**

### Le cycle complet d'un worker

```
1. kubectl cordon <noeud>            → plus de nouveaux pods
2. kubectl drain <noeud>             → sortir les pods existants
3. docker cp kubeadm + kubelet       → remplacer les binaires
4. kubeadm upgrade node              → récupérer la config
5. systemctl restart kubelet         → charger le nouveau binaire
6. kubectl uncordon <noeud>          → remettre en service
7. kubectl get nodes                 → ATTENDRE Ready avant le suivant
```

> ⚠️ **UN NŒUD À LA FOIS.** L'étape 7 n'est pas décorative : si je draine deux nœuds en même temps, je n'ai plus nulle part où mettre les pods, et je retrouve les `Pending` de ma toute première tentative.

*(Note : `kubectl drain` fait déjà le `cordon` au passage. Les deux sont séparés ici pour la clarté.)*

### Résultat final de l'upgrade en place

```
lab-n2-control-plane   Ready   control-plane   4h35m   v1.35.5
lab-n2-worker          Ready   <none>          4h35m   v1.35.5
lab-n2-worker2         Ready   <none>          4h35m   v1.35.5
```

![Upgrade complet — 3 nœuds en v1.35.5, pods redistribués](../screenshots/Part6-Kubernetes-Lifecycle/upgrade-complete-35.png)

**Durée totale : 15:13:52 → 15:32:07 = 18 min 15 s** pour 3 nœuds.

---
---

# PARTIE D — LE PODDISRUPTIONBUDGET

<a name="d19"></a>
## 19. Le problème que j'ai vu de mes yeux

**Sans PDB, quand je draine un nœud, Kubernetes évince TOUS les pods EN MÊME TEMPS.**

Il s'en fiche que ce soient mes 4 réplicas ou mes 2 CoreDNS. Le ReplicaSet en recrée d'autres ailleurs, mais **pendant quelques secondes, j'ai zéro pod prêt**.

**C'est une coupure.**

Le **PodDisruptionBudget** est la réponse : je déclare « je veux toujours au moins N pods debout », et **le drain ATTEND au lieu de tout arracher**.

---

<a name="d20"></a>
## 20. Créer un PDB et le voir travailler

### Le contrat

```bash
cat > ~/lab-p6/pdb-web.yaml <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web
spec:
  minAvailable: 3
  selector:
    matchLabels:
      app: web
EOF
```

**Décomposition :**

| Champ | Ce qu'il fait |
|---|---|
| `minAvailable: 3` | il doit toujours y avoir **au moins 3 pods disponibles** |
| `selector.matchLabels.app: web` | quels pods sont concernés — ceux portant le label `app: web` |

*(Le label `app: web` a été posé automatiquement par `kubectl create deployment web`.)*

```bash
kubectl apply -f ~/lab-p6/pdb-web.yaml
kubectl get pdb
```

```
NAME   MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
web    3               N/A               1                     0s
```

### La colonne qui compte

**`ALLOWED DISRUPTIONS: 1`** = le nombre de pods que Kubernetes s'autorise à retirer **à cet instant**.

4 réplicas, minimum 3 → **il peut en sacrifier 1**.

![PDB watch — lifecycle complet d'un pod (Pending → ContainerCreating → Running)](../screenshots/Part6-Kubernetes-Lifecycle/pdb-watch-lifecycle.png)

### Le test

Dans un second terminal, une surveillance en direct :
```bash
kubectl get pods -o wide -w
```

Dans le premier :
```bash
kubectl drain lab-n2-worker --ignore-daemonsets --delete-emptydir-data
```

**Sortie :**
```
evicting pod default/web-6d689fbfdf-gn6p9
evicting pod default/web-6d689fbfdf-c8ss4
evicting pod default/web-6d689fbfdf-jvd48
evicting pod default/web-6d689fbfdf-vr8dx
error when evicting pods/"web-...-jvd48" (will retry after 5s):
    Cannot evict pod as it would violate the pod's disruption budget.
error when evicting pods/"web-...-gn6p9" (will retry after 5s): Cannot evict pod...
error when evicting pods/"web-...-c8ss4" (will retry after 5s): Cannot evict pod...
pod/web-6d689fbfdf-vr8dx evicted          ← 1 SEUL sort
evicting pod default/web-6d689fbfdf-gn6p9
...
pod/web-6d689fbfdf-gn6p9 evicted          ← puis le suivant
...
pod/web-6d689fbfdf-jvd48 evicted
pod/web-6d689fbfdf-c8ss4 evicted
node/lab-n2-worker drained
```

![PDB en action — évictions refusées une par une, « Cannot evict pod »](../screenshots/Part6-Kubernetes-Lifecycle/pdb-drain-evictions.png)

### Ce qui se passe

> **Kubernetes REFUSE SES PROPRES ÉVICTIONS.**

Il demande à sortir les 4 pods, en obtient 1, et pour les trois autres il se répond « non, ça casserait le contrat ». **Puis il réessaie toutes les 5 secondes.**

### La comparaison

| Sans PDB | Avec PDB |
|---|---|
| 4 `evicted` d'affilée | 1 `evicted`, 3 refus, attente, 1 de plus… |
| instantané | par vagues |
| **0 pod dispo** pendant quelques secondes | **jamais moins de 3 debout** |
| tous les pods au même `AGE` | âges **en escalier** : 29s, 34s, 39s, 45s |

> **Le drain est plus lent — ET C'EST LE BUT. La lenteur, ici, c'est la disponibilité.**

Avec un PDB correct, je dois avoir **zéro** requête en erreur pendant un drain.

### Détail observé dans le watch

```
web-...-4mjgq   Pending   <none>            ← pas encore de nœud choisi
web-...-4mjgq   Pending   lab-n2-worker2    ← le scheduler a choisi
web-...-4mjgq   ContainerCreating           ← le kubelet démarre le conteneur
web-...-4mjgq   Running
```

**Je vois le scheduler prendre sa décision en direct.** Les trois étapes de la vie d'un pod.

---

<a name="d21"></a>
## 21. Provoquer un upgrade qui ne finit jamais

### Casser

```bash
kubectl patch pdb web -p '{"spec":{"minAvailable":4}}'
kubectl get pdb
```

```
NAME   MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
web    4               N/A               0                     102s
```

**`ALLOWED DISRUPTIONS: 0`.**

**Zéro.** Kubernetes n'a plus le droit de retirer un seul pod.

> **Je viens de créer un cluster IMPOSSIBLE À MAINTENIR.**

Le piège : *un PDB avec `minAvailable` égal au nombre de réplicas bloque définitivement tout drainage. `kubectl drain` attendra pour toujours.*

**C'est la cause classique d'un upgrade qui s'enlise à 3 h du matin.**

### Constater

```bash
kubectl drain lab-n2-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=60s
```

> ⚠️ **Le `--timeout` est INDISPENSABLE.** Sans lui, la commande tourne **littéralement à l'infini**.

![PDB bloquant (minAvailable=4) — drain boucle à l'infini, puis déblocage après patch à 3](../screenshots/Part6-Kubernetes-Lifecycle/pdb-blocking-fix.png)

**Résultat : une boucle sans fin.** Toutes les 5 secondes, Kubernetes redemande, se refuse, recommence. **Aucun pod `web` ne sortira jamais.**

### Trois observations importantes

**1. AUCUNE ERREUR.**
Rien n'est cassé, rien n'est en panne. Le cluster est en parfaite santé et **fait précisément ce que je lui ai demandé**.

> **Ce n'est pas une panne. C'est une contradiction que j'ai écrite moi-même.**

**2. CoreDNS est quand même sorti.**
```
pod/coredns-7d764666f9-7f8ls evicted
```
Il n'est **pas couvert par mon PDB**, donc il part sans problème.

> **Le nœud se vide PARTIELLEMENT — c'est le pire des cas : je perds des composants sans jamais finir.**

**3. Le nœud reste `cordoned`** même après l'abandon sur timeout.

> **Un drain raté laisse mon cluster dans un état dégradé.**

### Débloquer

Trois options, par ordre de préférence :

| Option | Commentaire |
|---|---|
| **Corriger le PDB** | **la bonne réponse** |
| Augmenter les réplicas (4→5) | bon réflexe si le minimum est une vraie exigence métier |
| Supprimer le PDB | ça marche, mais je retire le garde-fou pendant la maintenance — ce que font les gens pressés |

```bash
kubectl patch pdb web -p '{"spec":{"minAvailable":3}}'
kubectl drain lab-n2-worker2 --ignore-daemonsets --delete-emptydir-data --timeout=120s
```

```
pod/web-6d689fbfdf-jtxz6 evicted
pod/web-6d689fbfdf-4mjgq evicted
pod/web-6d689fbfdf-x8kmk evicted
pod/web-6d689fbfdf-npddq evicted
node/lab-n2-worker2 drained
```

**Débloqué en une commande, en quelques secondes.**

### LA RÈGLE À RETENIR

> **`minAvailable` doit être STRICTEMENT INFÉRIEUR à `replicas`.**

**Un seul chiffre de différence :**
- `3` sur 4 → **ralentit** le drain (c'est voulu, c'est la disponibilité)
- `4` sur 4 → le rend **IMPOSSIBLE**, pour toujours

Sinon j'ai écrit une contradiction : *« ne jamais rien retirer »* et *« vide ce nœud »*.

---
---

# PARTIE E — LES PANNES D'ENVIRONNEMENT

<a name="e22"></a>
## 22. Le disque plein, et LVM qui me sauve

### Le symptôme

```
cat: -: No space left on device
```

En plein milieu d'une commande banale.

### Le diagnostic

```bash
df -h /
docker system df
sudo du -sh /var/lib/docker
```

```
/dev/mapper/ubuntu--vg-ubuntu--lv   19G   18G   0   100%  /

TYPE            TOTAL   ACTIVE   SIZE      RECLAIMABLE
Images          5       2        2.402GB   253.6MB (10%)
Containers      4       3        530.2MB   3.858MB (0%)
Local Volumes   4       4        5.671GB   0B (0%)
Build Cache     25      0        436.2MB   423.2MB

8.2G  /var/lib/docker
```

### La cause

**`Local Volumes 5.671GB`** = les systèmes de fichiers de mes nœuds kind.

**Chaque nœud embarque son PROPRE cache d'images containerd.** Et pendant l'upgrade, j'ai téléchargé les composants 1.35.5 **trois fois** (une par nœud) — **sans que les 1.34.8 soient supprimées**.

> **Un upgrade télécharge les images de la nouvelle version sur chaque nœud SANS supprimer les anciennes.** C'est une précondition d'upgrade que personne n'écrit.

**Et ce n'est pas anodin :** un nœud dont le disque est plein déclenche de l'**éviction de pods** par le kubelet. C'est un incident classique en production — provoqué ici par un upgrade, ce qui est exactement le scénario réel.

### Premier réflexe : nettoyer

```bash
docker builder prune -af      # cache de build : 423 Mo, purement jetable
docker image prune -f         # images sans conteneur
```

Insuffisant : `Total reclaimed space: 0B` pour le second (les 253 Mo « reclaimable » étaient l'image de mon cluster `lab`, considérée comme utilisée).

### La découverte

```bash
lsblk
```

```
sda                         40G
├─sda1                       1M
├─sda2                       2G   /boot
└─sda3                      38G
  └─ubuntu--vg-ubuntu--lv   19G   /       ← 19 Go INUTILISÉS dans le VG !
sdb                         30G                (disque ajouté, vierge)
```

> **Ma partition fait 38 Go, mais le volume logique n'en utilise que 19.**

**L'installateur Ubuntu fait ça par défaut** — il alloue la moitié et laisse le reste libre dans le groupe de volumes (VG). **Je pouvais étendre sans toucher au matériel.**

### Le correctif

```bash
sudo lvextend -l +100%FREE -r /dev/mapper/ubuntu--vg-ubuntu--lv
```

| Option | Ce qu'elle fait |
|---|---|
| `-l +100%FREE` | prend **tout** l'espace libre du groupe de volumes |
| `-r` | **redimensionne le système de fichiers** dans la foulée (`resize2fs`) |

**Sans `-r`**, le volume serait plus grand mais le système de fichiers ne le saurait pas — je n'aurais rien gagné.

```
Size of logical volume ubuntu-vg/ubuntu-lv changed from <19,00 GiB to <38,00 GiB
Extending file system ext4 to <38,00 GiB...
resize2fs done
Extended file system ext4 on ubuntu-vg/ubuntu-lv.

/dev/mapper/ubuntu--vg-ubuntu--lv   38G   18G   19G   50%   /
```

> **19 Go libérés, À CHAUD, sans démonter quoi que ce soit, sans arrêter les clusters.**

**C'est la force de LVM.** Et c'est du Module 2 de mon lab réseau qui ressert ici.

### La ligne de runbook

> **Vérifier l'espace disque AVANT de commencer un upgrade.**

---
---

# PARTIE F — L'AUTRE MÉTHODE

<a name="f23"></a>
## 23. Patching en place vs remplacement immuable

### Les deux philosophies (§6.4)

| | **En place** | **Immuable** |
|---|---|---|
| **Principe** | on patche le nœud existant | on ne patche jamais : on crée un nœud neuf, on bascule, on détruit l'ancien |
| **Le nœud a** | une **histoire** (1.34 → 1.35 par modifications successives) | **aucune histoire** — il naît dans sa version |
| **Dérive de config** | **s'accumule** | **impossible** |
| **Retour arrière** | complexe | **trivial** (recréer depuis l'ancienne image) |
| **Modèle** | Ansible, `unattended-upgrades`, `kured` | cloud : node groups, Karpenter |

**Ce qu'est la « dérive de configuration » :** un serveur qu'on patche pendant deux ans finit par avoir un état que personne ne sait reproduire. Des paquets installés à la main, des fichiers modifiés en urgence, des contournements oubliés. **Le jour où il faut le remonter à l'identique, c'est impossible.**

### Ce que j'ai fait

```bash
sed -i 's/v1.35.5/v1.36.1/; s/v1.34.8/v1.36.1/' ~/lab-p6/kind-n2.yaml
```

```bash
date +%T
kind delete cluster --name lab-n2
kind create cluster --config ~/lab-p6/kind-n2.yaml
date +%T
```

```
23:34:15
Deleted nodes: ["lab-n2-worker" "lab-n2-control-plane" "lab-n2-worker2"]
✓ Ensuring node image (kindest/node:v1.36.1) 🖼
✓ Joining worker nodes 🚜
23:35:00
```

```
lab-n2-control-plane   Ready   control-plane   60s   v1.36.1
lab-n2-worker          Ready   <none>          45s   v1.36.1
lab-n2-worker2         Ready   <none>          44s   v1.36.1
```

![Immuable — delete + create v1.36.1 en 45 secondes](../screenshots/Part6-Kubernetes-Lifecycle/immutable-45s.png)

### LA COMPARAISON MESURÉE (exercice 6.8 n°3)

| Méthode | Durée | Ce qu'il a fallu faire |
|---|---|---|
| **En place** (1.34→1.35) | **18 min 15 s** | télécharger 2 binaires, les copier ×3, `kubeadm upgrade apply`, `kubeadm upgrade node` ×2, restart kubelet ×3, cordon/drain/uncordon ×2, contourner SystemVerification ×3, gérer un 403 transitoire |
| **Immuable** (1.35→1.36) | **45 s** | éditer une ligne, détruire, recréer |

> **24× plus rapide.** Zéro commande manuelle dans les nœuds, zéro contournement, zéro dérive.

### ⚠️ LA NUANCE HONNÊTE — à dire absolument en entretien

**Ici, j'ai détruit TOUT l'état du cluster.** Mes pods, mon PDB, mon Ingress — tout est parti.

**En production, l'immuable remplace les nœuds UN PAR UN dans un cluster qui reste vivant** — le control-plane et etcd survivent. Ce que j'ai fait ressemble davantage à une **reconstruction complète**.

**L'écart réel en production est donc moins violent.**

**Mais la propriété centrale tient :** aucun nœud n'est jamais modifié, donc **aucune dérive possible**, et le retour arrière consiste à recréer depuis l'image précédente.

### Ce que le marché attend

> La bonne réponse n'est pas « immuable, toujours ». Elle dépend de la **maturité de l'automatisation**, du **délai d'approvisionnement des nœuds**, et du **coût**.
>
> Ce qui compte, c'est d'avoir **un avis argumenté** — et de pouvoir dire *« j'ai fait les deux, voici l'écart mesuré »*.

---
---

# PARTIE G — CE QU'IL FAUT FAIRE AVANT UN UPGRADE

<a name="g24"></a>
## 24. Les APIs dépréciées : la cause n°1 des upgrades ratés

### Le problème

**Kubernetes retire des APIs à chaque version.** Un manifest qui marchait en 1.34 peut être refusé en 1.36.

**Exemple réel :** `Ingress` a vécu successivement en :
1. `extensions/v1beta1`
2. `networking.k8s.io/v1beta1`
3. `networking.k8s.io/v1`

**Les deux premières ont été SUPPRIMÉES en 1.22.**

### Le piège — c'est ça qui est vicieux

**Ce n'est pas le cluster qui casse.**

C'est mon manifest, celui qui dort dans mon dépôt Git depuis deux ans, qui devient soudain **irrecevable**. Je ne le découvre qu'au prochain déploiement — **souvent des semaines après l'upgrade, en pleine mise en production**.

> **C'est pour ça qu'on détecte et corrige AVANT de toucher au cluster.** C'est l'étape 3 de la procédure.

### Les deux outils, et leur différence

| Outil | Ce qu'il lit | Quand l'utiliser |
|---|---|---|
| **`pluto`** | mes **FICHIERS** (dépôt Git, charts Helm) | en CI, sur chaque commit |
| **`kubent`** | le **CLUSTER** (ce qui est déjà déployé) | avant chaque upgrade |

Et une **troisième source** : la métrique `apiserver_requested_deprecated_apis` de l'API server. Elle dit **ce qui appelle réellement** une API mourante — utile quand le coupable est un opérateur tiers dont je n'ai pas les manifests.

### Installer pluto — et l'erreur que j'ai faite

**Premier essai (échec) :**
```bash
curl -sSL https://github.com/FairwindsOps/pluto/releases/latest/download/pluto_linux_amd64.tar.gz -o pluto.tar.gz
tar -xzf pluto.tar.gz pluto
```
```
gzip: stdin: not in gzip format
```

**Diagnostic :**
```bash
file pluto.tar.gz
head -c 300 pluto.tar.gz
```
```
pluto.tar.gz: ASCII text, with no line terminators
Not Found
```

> **J'avais téléchargé les 9 octets du texte « Not Found ».** GitHub met le **numéro de version dans le nom du fichier**, donc mon URL ne pointait sur rien.

**C'est exactement le risque dont je parlais au chapitre 10 :** un `curl` silencieux peut rapporter n'importe quoi. **D'où le réflexe : vérifier ce qu'on a téléchargé avant de s'en servir.**

**Trouver la vraie URL :**
```bash
curl -s https://api.github.com/repos/FairwindsOps/pluto/releases/latest \
  | grep browser_download_url | grep linux_amd64
```
```
"https://github.com/FairwindsOps/pluto/releases/download/v5.24.3/pluto_5.24.3_linux_amd64.tar.gz"
```

**Deuxième essai (succès) :**
```bash
curl -sSL https://github.com/FairwindsOps/pluto/releases/download/v5.24.3/pluto_5.24.3_linux_amd64.tar.gz -o pluto.tar.gz
file pluto.tar.gz
tar -xzf pluto.tar.gz pluto
chmod +x pluto
./pluto version
```
```
pluto.tar.gz: gzip compressed data, max compression   ← une VRAIE archive
Version:5.24.3 Commit:366e3d0...
```

### Fabriquer un manifest fautif (exprès)

```bash
mkdir -p ~/lab-p6/manifests
cat > ~/lab-p6/manifests/ingress-old.yaml <<'EOF'
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: legacy-app
spec:
  rules:
    - host: legacy.lab.local
      http:
        paths:
          - path: /
            backend:
              serviceName: legacy
              servicePort: 80
EOF
```

Et un deuxième, **valide**, pour vérifier que pluto ne crie pas au loup :
```bash
cat > ~/lab-p6/manifests/deploy-ok.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
EOF
```

### Le scan

```bash
./pluto detect-files -d manifests/
```

```
NAME         KIND      VERSION                     REPLACEMENT            REMOVED   DEPRECATED   REPL AVAIL
legacy-app   Ingress   networking.k8s.io/v1beta1   networking.k8s.io/v1   true      true         true
```

![Pluto — détection API dépréciée, correction, kubectl apply réussi](../screenshots/Part6-Kubernetes-Lifecycle/pluto-api-fix.png)

### Lecture du tableau, colonne par colonne

| Colonne | Valeur | Sens |
|---|---|---|
| `NAME` / `KIND` | `legacy-app` / `Ingress` | l'objet fautif |
| `VERSION` | `networking.k8s.io/v1beta1` | l'API utilisée |
| `REPLACEMENT` | `networking.k8s.io/v1` | **par quoi la remplacer** |
| `REMOVED` | `true` | elle n'existe plus du tout |
| `DEPRECATED` | `true` | elle avait été annoncée obsolète avant |
| `REPL AVAIL` | `true` | le remplacement est disponible sur ce cluster |

**Et `deploy-ok.yaml` n'apparaît pas** — pluto ne signale que les problèmes. **Pas de faux positif.**

### La distinction qui compte

| État | Sens |
|---|---|
| **DEPRECATED** | ça marche encore, mais c'est un avertissement. **J'ai le temps de corriger.** |
| **REMOVED** | c'est fini. **L'API server refusera mon manifest.** |

Ici les deux sont `true` — **le cycle complet a été parcouru. Je suis en retard.**

### Vérifier que c'est bien réel

```bash
kubectl apply -f ~/lab-p6/manifests/ingress-old.yaml
```

```
error: resource mapping not found for name: "legacy-app" namespace: "" from
"...ingress-old.yaml": no matches for kind "Ingress" in version "networking.k8s.io/v1beta1"
ensure CRDs are installed first
```

**L'API server ne connaît plus cette version. Mon manifest est devenu irrecevable.**

> ⚠️ **Note le conseil TROMPEUR à la fin : `ensure CRDs are installed first`.**
>
> kubectl suppose que je cherche une ressource personnalisée manquante. **C'est faux ici**, et c'est ce qui envoie les gens sur une fausse piste pendant une demi-heure : ils cherchent un opérateur à installer, alors que le problème est une **API supprimée**.

### La correction — et pourquoi ce n'est pas qu'une ligne

```bash
cat > ~/lab-p6/manifests/ingress-old.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: legacy-app
spec:
  rules:
    - host: legacy.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: legacy
                port:
                  number: 80
EOF
```

**TROIS différences, pas une :**

| Avant (`v1beta1`) | Après (`v1`) |
|---|---|
| `apiVersion: networking.k8s.io/v1beta1` | `apiVersion: networking.k8s.io/v1` |
| (pas de `pathType`) | **`pathType: Prefix` obligatoire** |
| `serviceName: legacy` + `servicePort: 80` | bloc `service: { name:, port: { number: } }` imbriqué |

> **La STRUCTURE a changé, pas seulement le nom de l'API.**
>
> **C'est ce qui fait qu'on ne peut PAS automatiser ça avec un `sed`**, et pourquoi on le fait **avant**, au calme, pas pendant la fenêtre de maintenance.

### Vérification finale

```bash
./pluto detect-files -d manifests/
kubectl apply -f ~/lab-p6/manifests/ingress-old.yaml
```
```
There were no resources found with known deprecated apiVersions.
ingress.networking.k8s.io/legacy-app created
```

**Le cycle complet : détecter → corriger le fichier → revérifier → déployer.** Et tout ça **sans jamais toucher au cluster**.

---

<a name="g25"></a>
## 25. Sauvegarder etcd (et vérifier la sauvegarde)

### Pourquoi c'est l'étape 1 de tout upgrade

**etcd contient TOUT l'état de mon cluster.** Tous les objets, tous les Secrets, toute la configuration.

> **Perdre etcd = perdre le cluster.** Les nœuds continuent de tourner, mais plus personne ne sait ce qui doit exister.

### Trouver l'outil

```bash
docker exec lab-n2-control-plane etcdctl version
```
```
OCI runtime exec failed: "etcdctl": executable file not found in $PATH
```

**`etcdctl` n'est pas sur le nœud.** Normal : les images kind sont minimalistes.

**Mais etcd tourne comme un static pod** (chapitre 13) — et le binaire `etcdctl` est **dans l'image du conteneur etcd**, pas sur le nœud.

```bash
kubectl -n kube-system exec etcd-lab-n2-control-plane -- etcdctl version
```
```
etcdctl version: 3.6.8
API version: 3.6
```

### Vérifier l'état avant de sauvegarder

**etcd est protégé par TLS mutuel** — il ne parle à personne sans certificat client. D'où les **trois options obligatoires** sur chaque commande :

| Option | Ce qu'elle donne |
|---|---|
| `--cacert` | l'autorité qui a signé le certificat d'etcd (pour le vérifier) |
| `--cert` | mon certificat client (pour prouver mon identité) |
| `--key` | ma clé privée |

```bash
kubectl -n kube-system exec etcd-lab-n2-control-plane -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --write-out=table
```

**Résultat (colonnes intéressantes) :**
```
DB SIZE: 2.5 MB   IN USE: 1.1 MB   PERCENTAGE NOT IN USE: 55%
QUOTA: 2.1 GB     IS LEADER: true  RAFT INDEX: 74583
```

### Trois colonnes à comprendre

**`DB SIZE 2.5 MB` / `IN USE 1.1 MB` / `55% NOT IN USE`**
etcd conserve l'**historique des révisions**. 55 % de ma base, c'est du passé. **Il ne rend pas cet espace tout seul** : il faut `compact` (supprimer les vieilles révisions) puis `defrag` (récupérer l'espace).

> **En production, une base qui gonfle sans raison, c'est presque toujours ça.**

**`QUOTA 2.1 GB`**
La limite dure. **Quand etcd l'atteint, il passe en LECTURE SEULE** — plus aucun objet créé ou modifié dans le cluster.

> **C'est un des incidents les plus brutaux qui existent, et il arrive silencieusement.**

**`IS LEADER true`**
Un seul membre ici. **En production : trois ou cinq**, avec un leader élu. C'est ce qui permet à etcd de survivre à la perte d'une machine.

### La sauvegarde

```bash
kubectl -n kube-system exec etcd-lab-n2-control-plane -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd/snap-$(date +%F-%H%M).db
```

**Résultat :**
```
created temporary db file "/var/lib/etcd/snap-2026-08-18-0953.db.part"
fetched snapshot  size:"2.5 MB"  took:"48.735036ms"
Snapshot saved at /var/lib/etcd/snap-2026-08-18-0953.db
```

**2,5 Mo en 48 millisecondes.**

> Sur un cluster de production avec des milliers d'objets, compte quelques secondes à quelques dizaines de secondes. **Mais l'ordre de grandeur reste petit — ce qui rend l'excuse « on n'a pas le temps de sauvegarder » indéfendable.**

**Le détail du `.part` :** etcd écrit d'abord un fichier temporaire, **puis le renomme une fois complet**. Je ne peux donc jamais tomber sur un snapshot à moitié écrit.

### Sortir la sauvegarde du nœud

```bash
mkdir -p ~/lab-p6/backups
docker cp lab-n2-control-plane:/var/lib/etcd/snap-2026-08-18-0953.db ~/lab-p6/backups/
ls -lh ~/lab-p6/backups/
```
```
-rw------- 1 badr badr 2.5M Aug 18 09:53 snap-2026-08-18-0953.db
```

> **Une sauvegarde qui reste sur la machine qu'elle protège ne protège RIEN.** Si le nœud brûle, la sauvegarde brûle avec.

**Les droits `600`** (lecture pour moi seul) sont le bon réflexe :

> ⚠️ **Un snapshot etcd contient TOUS mes Secrets EN CLAIR** si le chiffrement au repos n'est pas activé. **C'est un fichier à traiter comme une clé privée.**

En production, l'étape suivante serait de l'envoyer sur un **stockage distant** (S3, serveur de sauvegarde), **chiffré**.

### VÉRIFIER la sauvegarde — l'étape que tout le monde saute

> **Une sauvegarde jamais restaurée n'est pas une sauvegarde.**

Un fichier de 2,5 Mo qui existe **ne prouve rien**. Des équipes découvrent que leurs snapshots sont corrompus **le jour où elles en ont besoin**.

**Ma première tentative a échoué, et ça m'a appris quelque chose :**

```bash
docker cp ~/lab-p6/backups/snap-...db lab-n2-control-plane:/tmp/verif.db
kubectl -n kube-system exec etcd-lab-n2-control-plane -- etcdutl snapshot status /tmp/verif.db
```
```
Error: stat /tmp/verif.db: no such file or directory
```

**Deux systèmes de fichiers différents :**

| Commande | Où elle agit |
|---|---|
| `docker cp ... lab-n2-control-plane:/tmp/` | dans le **NŒUD** (le conteneur Docker) |
| `kubectl exec etcd-lab-n2-control-plane` | dans le **POD etcd**, qui tourne *à l'intérieur* du nœud mais a son propre `/tmp` |

> **Le pod ne voit pas le `/tmp` du nœud. Il ne voit QUE ce qui lui est explicitement MONTÉ** — et `/var/lib/etcd` en fait partie (d'où le succès du snapshot).

**C'est le principe d'isolation des conteneurs, rencontré en vrai plutôt qu'en théorie.**

**La solution — passer par le dossier partagé :**
```bash
docker cp ~/lab-p6/backups/snap-...db lab-n2-control-plane:/var/lib/etcd/verif.db
kubectl -n kube-system exec etcd-lab-n2-control-plane -- \
  etcdutl snapshot status /var/lib/etcd/verif.db --write-out=table
```

```
+----------+----------+------------+------------+---------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE | VERSION |
+----------+----------+------------+------------+---------+
| d7101698 |    59647 |        312 |     2.5 MB |   3.6.0 |
+----------+----------+------------+------------+---------+
```

![etcd snapshot save + vérification — 2.5 MB, 312 clés, hash d7101698](../screenshots/Part6-Kubernetes-Lifecycle/etcd-backup-verify.png)

### Note sur l'outil : `etcdutl`, pas `etcdctl`

**Depuis etcd 3.5**, les opérations sur les **fichiers** snapshot (status, restore) sont dans un **binaire séparé**, parce qu'elles travaillent **hors ligne**, sans parler à un serveur.

| Outil | Pour quoi |
|---|---|
| `etcdctl` | parler à un serveur etcd **en marche** |
| `etcdutl` | travailler sur des **fichiers**, hors ligne |

### Lecture du tableau

| Colonne | Valeur | Ce que ça prouve |
|---|---|---|
| `HASH` | `d7101698` | somme de contrôle — **le fichier n'est pas corrompu** |
| `REVISION` | `59647` | l'instant précis du cluster capturé |
| `TOTAL KEYS` | **`312`** | **312 objets dedans — la sauvegarde n'est pas vide** |
| `TOTAL SIZE` | `2.5 MB` | cohérent avec le fichier |

> **`TOTAL KEYS: 312` est LA ligne qui compte.** C'est la différence entre « un fichier de 2,5 Mo existe » et « ma sauvegarde contient réellement mon cluster ». **Un snapshot corrompu ou tronqué échouerait ici.**

Ces 312 clés = tous mes objets : les nœuds, les pods système, les ServiceAccounts, les Secrets, mon Ingress `legacy-app`. **Tout ce que `kubectl get` peut montrer vit là-dedans.**

### Ce qui reste (Partie 9)

**La RESTAURATION.** *Une sauvegarde jamais restaurée n'est pas une sauvegarde*.

Mais c'est le sujet de la **Partie 9** (PRA : *« détruis le nœud pour de bon et reconstruis, chronomètre »*). Pour la Partie 6, l'étape 1 du runbook est faite : **je sais sauvegarder ET vérifier**.

---
---

# PARTIE H — EXPLOITER AU QUOTIDIEN

<a name="h26"></a>
## 26. Capacity planning : requests vs réel

### La question à laquelle ça répond

**Mon cluster a une capacité finie. Où en suis-je, et quand faut-il ajouter un nœud ?**

### Le piège central du chapitre

> **Kubernetes réserve ce que je DEMANDE, pas ce que je CONSOMME.**

Si mes pods demandent 2 Go et en utilisent 200 Mo, **le scheduler considère 2 Go comme pris**. Je paie des nœuds pour du vide.

### Ce que le scheduler voit

```bash
kubectl describe node lab-n2-worker | grep -A 8 "Allocated resources"
```

```
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests   Limits
  --------           --------   ------
  cpu                100m (5%)  100m (5%)
  memory             50Mi (0%)  50Mi (0%)
  ephemeral-storage  0 (0%)     0 (0%)
```

C'est juste `kindnet` et `kube-proxy` (les DaemonSets). Mon Ingress ne consomme rien — **c'est un objet de configuration sans pod**.

**Et note la phrase entre parenthèses :**

> *« Total limits may be over 100 percent, i.e., overcommitted. »*

**C'est le cœur du chapitre : Kubernetes m'autorise à PROMETTRE PLUS QUE CE QUE J'AI**, tant que les `requests` tiennent. **C'est ce qui rend un cluster économique — et fragile si j'exagère.**

### Ce que les nœuds consomment vraiment

```bash
kubectl top nodes
```
```
error: Metrics API not available
```

**`metrics-server` n'était pas installé** (le cluster avait été recréé par la méthode immuable).

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Puis une correction obligatoire sur kind :**

```bash
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

**Pourquoi :** `metrics-server` interroge chaque kubelet en HTTPS, et **le kubelet présente un certificat auto-signé** que `metrics-server` refuse. Sur un vrai cluster, on met en place la rotation de certificats kubelet signés par la CA du cluster. Ici, on lui dit d'accepter.

*(J'ai vu deux pods pendant quelques secondes : le patch avait déclenché un rollout — l'ancien sans le flag, le nouveau avec.)*

![Allocated resources + metrics-server install + --kubelet-insecure-tls patch](../screenshots/Part6-Kubernetes-Lifecycle/capacity-metrics-server.png)

### LE RÉSULTAT — et la comparaison qui compte

```bash
kubectl top nodes
```
```
NAME                   CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
lab-n2-control-plane   167m         8%       659Mi           8%
lab-n2-worker          125m         6%       148Mi           1%
lab-n2-worker2         114m         5%       145Mi           1%
```

![Snapshot vérifié + describe allocated resources — requests vs réel](../screenshots/Part6-Kubernetes-Lifecycle/capacity-allocated-resources.png)

**Face à face avec les requests :**

| | Réservé (requests) | Consommé réellement |
|---|---|---|
| `worker` CPU | **100m (5%)** | **125m (6%)** |
| `worker` RAM | **50Mi (0%)** | **148Mi (1%)** |

> **La consommation DÉPASSE la réservation.** Les DaemonSets demandent 50 Mi et en utilisent 148. **C'est l'overcommit en action.**

### Les deux dérives possibles

| Situation | Conséquence |
|---|---|
| **Requests trop HAUTES** | le scheduler croit le nœud plein, refuse d'y placer des pods → **j'achète des serveurs pour du vide**. Le cas le plus fréquent, et le plus cher. |
| **Requests trop BASSES** | le nœud accepte plus qu'il ne peut tenir. Tant que tout le monde est calme, ça passe. **Le jour d'un pic simultané, le kubelet évince des pods pour survivre.** ← mon cas ici |

### Le control-plane n'est jamais gratuit

`659Mi` sur le control-plane. **etcd, l'API server et le scheduler consomment du vrai.**

### La méthode du chapitre

> **Mesurer la consommation réelle sur plusieurs semaines, puis régler les `requests` sur le percentile haut observé — PAS sur une estimation faite au doigt mouillé le jour du déploiement.**

---

<a name="h27"></a>
## 27. kured : automatiser les redémarrages

*(Lecture — rien à installer)*

### Le problème

**Mettre à jour le noyau d'un nœud demande un REDÉMARRAGE.**

Sur 50 nœuds, je ne vais pas les redémarrer à la main. **Et surtout pas tous en même temps** — ce serait une panne totale.

### Ce que fait kured

**kured** (KUbernetes REboot Daemon) tourne **sur chaque nœud** (c'est un DaemonSet) et :

1. **Surveille** le fichier que Debian/Ubuntu créent quand un redémarrage est requis : `/var/run/reboot-required`
2. Quand il le trouve : il prend un **VERROU GLOBAL** — **un seul nœud à la fois dans tout le cluster**
3. Puis : `cordon` → `drain` → `reboot` → `uncordon`
4. Il relâche le verrou, le nœud suivant peut y aller

**Et il respecte les PDB.** Donc tout ce que j'ai appris au chapitre 20 s'applique.

### Ce que je retiens

> **kured est le pendant AUTOMATISÉ du cycle que j'ai fait à la main sur `worker` et `worker2`.**

Le verrou global est la pièce essentielle : **c'est lui qui garantit « un nœud à la fois »**, la règle que j'ai apprise au chapitre 18.

---
---

# PARTIE I — LE LIVRABLE

<a name="i28"></a>
## 28. MON RUNBOOK D'UPGRADE

> **Ce qu'est un runbook :** la procédure écrite qu'on suit pour faire une opération. Comme une check-list de pilote — pas un cours, la liste exacte des gestes dans l'ordre, avec les vérifications et quoi faire si ça part en vrille.
>
> **Pourquoi :** dans six mois j'aurai oublié. Et si c'est un collègue qui doit le faire à 3 h du matin pendant que je suis en vacances, il n'a pas ma mémoire.

---

## RUNBOOK — Upgrade de cluster Kubernetes

**Version :** 1.0
**Auteur :** Badr
**Testé sur :** kind 3 nœuds, 1.34.8 → 1.35.5 → 1.36.1
**Durée constatée :** 18 min 15 s (en place) / 45 s (immuable)

---

### PRÉCONDITIONS (à vérifier AVANT toute action)

| # | Vérification | Commande | Pourquoi |
|---|---|---|---|
| 1 | **Espace disque** ≥ 20 Go libres par nœud | `df -h /` | un upgrade télécharge les images de la nouvelle version **sans supprimer les anciennes** → j'ai saturé un disque de 19 Go |
| 2 | **Limites inotify** ≥ 1024 instances | `sysctl fs.inotify.max_user_instances` | partagées entre tous les conteneurs → kubelet mort en silence |
| 3 | **Tous les PDB ont `minAvailable < replicas`** | `kubectl get pdb -A` | sinon le drain boucle à l'infini |
| 4 | **Aucun pod orphelin** (sans `ownerReferences`) | voir §5 | sinon le drain refuse de démarrer |
| 5 | **Sauvegarde etcd prise ET VÉRIFIÉE** | voir §25 | `TOTAL KEYS > 0` obligatoire |
| 6 | **APIs dépréciées détectées et corrigées** | `pluto detect-files -d manifests/` | cause n°1 des upgrades ratés |
| 7 | **Notes de version lues** | — | ce qui est supprimé, ce qui change de comportement |
| 8 | **Version cible = N+1 maximum** | `kubeadm upgrade plan` | jamais de saut de mineure |

---

### PROCÉDURE

#### Étape 1 — Sauvegarder
```
snapshot etcd + copie hors du nœud + vérification (TOTAL KEYS)
sauvegarde de /etc/kubernetes/manifests/
```

#### Étape 2 — Control-plane
```
1. installer kubeadm cible          (apt / docker cp sur kind)
2. kubeadm upgrade plan             ← LIRE la sortie
3. kubeadm upgrade apply vX.Y.Z
4. installer kubelet cible
5. systemctl restart kubelet
6. ⏳ attendre ~30 s (403 transitoire normal)
7. kubectl get nodes → doit afficher la nouvelle version
```

**Point de vérification :** `kubectl version` → `Server Version` = cible

#### Étape 3 — Chaque worker, UN PAR UN
```
1. kubectl drain <noeud> --ignore-daemonsets --delete-emptydir-data --timeout=300s
2. installer kubeadm cible
3. kubeadm upgrade node
4. installer kubelet cible
5. systemctl restart kubelet
6. kubectl uncordon <noeud>
7. ⏳ ATTENDRE Ready avant de passer au suivant
```

**Point de vérification :** `kubectl get nodes` → nœud `Ready` + nouvelle version

#### Étape 4 — Add-ons
```
CNI, ingress controller, cert-manager, CSI drivers
(ils ont leur propre cycle de version)
```

#### Étape 5 — Vérifier les intégrations
```
□ Authentification OIDC        kubectl auth can-i --list
□ Envoi des logs vers le SIEM
□ Sortie réseau (proxy/egress)
□ Certificats applicatifs      kubectl get certificate -A
□ WAF / ingress externe
```

> **C'est l'étape que tout le monde oublie : ce n'est presque jamais Kubernetes qui casse, ce sont ses intégrations.**

---

### PIÈGES CONNUS (rencontrés en vrai)

| Symptôme | Cause | Correctif |
|---|---|---|
| `kubelet is not healthy after 4m` au join | `fs.inotify.max_user_instances=128`, partagé entre conteneurs | `sysctl -w ...=1024` + `/etc/sysctl.d/99-kind.conf` |
| `cannot delete Pods that declare no controller` | pod sans `ownerReferences` | supprimer sciemment — **PAS `--force` à l'aveugle** |
| `[ERROR SystemVerification]` | module noyau `configs` non chargeable dans un conteneur | `--ignore-preflight-errors=SystemVerification` (**nommé**, pas `all`) — **sur CHAQUE nœud** |
| `403 Forbidden` sur `kubernetes-admin` | RBAC pas rechargé après restart kubelet | **attendre 30 s** — ne rien corriger |
| `No space left on device` | images des 2 versions × N nœuds | `lvextend -l +100%FREE -r` |
| `drain` boucle sans fin | PDB avec `minAvailable = replicas` | `kubectl patch pdb <nom> -p '{"spec":{"minAvailable":N-1}}'` |
| `no matches for kind X in version Y` | API supprimée | corriger le manifest (**structure**, pas juste `apiVersion`) |

---

### RETOUR ARRIÈRE

| Niveau | Procédure |
|---|---|
| **Control-plane** | remettre les manifests de `/etc/kubernetes/tmp/kubeadm-backup-manifests-<date>/` dans `/etc/kubernetes/manifests/` → le kubelet redémarre les composants en ancienne version |
| **Nœud (immuable)** | recréer depuis l'image de l'ancienne version |
| **Dernier recours** | restauration du snapshot etcd |

---

### DURÉES CONSTATÉES

| Opération | Durée |
|---|---|
| `kubeadm upgrade apply` (control-plane) | 3 min 05 s |
| `kubeadm upgrade node` (worker) | ~1 s |
| Cycle complet d'un worker (drain inclus) | ~5 min |
| **Upgrade complet en place, 3 nœuds** | **18 min 15 s** |
| **Remplacement immuable, 3 nœuds** | **45 s** |

**Pour dimensionner une fenêtre de maintenance :** compter ~5 min par worker + 5 min de control-plane + marge ×2.

---

<a name="i29"></a>
## 29. Ce que je dois savoir dire en entretien

### La question : *« Raconte-moi ton dernier upgrade de cluster »*

**Le squelette — les 7 étapes :**

1. **Sauvegarder** — snapshot etcd + manifests
2. **Lire les notes de version** — ce qui est déprécié, supprimé, changé
3. **Détecter les APIs dépréciées et corriger les manifests** — AVANT de toucher au cluster
4. **Mettre à jour le control-plane**
5. **Mettre à jour les nœuds, UN PAR UN** — vider → mettre à jour → remettre → attendre Ready
6. **Mettre à jour les add-ons** — CNI, ingress, cert-manager, CSI
7. **Vérifier les intégrations** — celle que tout le monde oublie

### Les phrases qui me distinguent

Tout le monde peut lire la doc. **Ces trois-là, non :**

> *« Control-plane d'abord, parce que le kubelet peut être en retard sur l'API server, jamais en avance. »*

> *« Le control-plane est fait de static pods : kubeadm réécrit des YAML dans `/etc/kubernetes/manifests/` et sauvegarde les anciens — c'est là qu'est le rollback. »*

> *« Un upgrade renouvelle les certificats internes au passage. C'est pour ça qu'une équipe qui upgrade régulièrement ne voit jamais l'expiration venir — et se fait avoir le jour où elle laisse passer 14 mois. »*

### Mes chiffres

**18 min 15 s** pour 3 nœuds en place, **45 s** en immuable. Avec la nuance : *« l'immuable en production remplace les nœuds un par un, pas tout d'un coup — l'écart réel est moins violent, mais la propriété d'absence de dérive tient. »*

### Autres questions probables

**« Que se passe-t-il si les certificats du cluster expirent ? »**
→ Perte totale d'accès, **y compris pour réparer**. Prévention : `kubeadm certs check-expiration` en **alerte** à 30 jours, pas en rappel mental.

**« Comment garantis-tu zéro coupure pendant un drain ? »**
→ PDB avec `minAvailable` **strictement inférieur** à `replicas`. Et j'ai vérifié : sans PDB, les 4 pods sont recréés en même temps (même `AGE`) ; avec, ils naissent en escalier.

**« Pourquoi Kubernetes ne rééquilibre pas après un uncordon ? »**
→ Le scheduler ne décide qu'à la **naissance** d'un pod. Un pod vivant ne bouge jamais seul. Il faut le tuer, ou utiliser `descheduler`.

**« En place ou immuable ? »**
→ Ça dépend de la maturité de l'automatisation, du délai d'approvisionnement des nœuds et du coût. **J'ai fait les deux, voici l'écart mesuré.**

---

<a name="i30"></a>
## 30. Ce qui reste à faire

### Exercices 6.8

| # | Exercice | Statut |
|---|---|---|
| 1 | Provoquer un échec d'upgrade (PDB bloquant) + documenter le déblocage | ✅ **fait** |
| 2 | Faire expirer un certificat de cluster, constater la perte d'accès, récupérer | ⬜ à faire |
| 3 | Comparer patching en place vs remplacement immuable | ✅ **fait** (18 min 15 s vs 45 s) |
| 4 | Écrire une alerte pour les APIs dépréciées et la déclencher | ⬜ à faire |
| 5 | Mesurer les erreurs sur le WAF pendant un drain | ⬜ reporté (nécessite les VMs) |

### Reporté à la Partie 6-bis (infra réelle)

**L'étape 5 du runbook** (vérifier les intégrations) nécessite mes VMs allumées :
- **OIDC** : `kubectl auth can-i --list` avec un compte FreeIPA
- **cert-manager** : les `Certificate` toujours `READY`, adossés à mon intermédiaire du Module 10
- **Agent SIEM** : les événements d'audit arrivent encore dans Wazuh
- **Egress** : un pod sort toujours via Squid
- **WAF** : `https://app.lab.local` répond de bout en bout

### Lien avec la Partie 9

La sauvegarde etcd anticipe la Partie 9.

**Ce qui manque : la RESTAURATION.** *Une sauvegarde jamais restaurée n'est pas une sauvegarde*. → Partie 9 (PRA) : détruire le nœud pour de bon, reconstruire, chronométrer.

---
---

# SYNTHÈSE — CE QUE JE DOIS ABSOLUMENT RETENIR

## Les 6 idées

1. **Le chef avant les ouvriers** — le kubelet peut être en retard sur l'API server, jamais en avance.
2. **Un nœud à la fois** — `cordon → drain → travaux → uncordon`, puis attendre `Ready`.
3. **Un pod ne se déplace pas** — il est tué et recréé ailleurs. D'où : ce qui n'a pas de contrôleur bloque le drain.
4. **`minAvailable` < `replicas`** — sinon le drain est impossible, pour toujours.
5. **Un upgrade renouvelle les certificats internes** (~1 an). À l'expiration : cluster inaccessible, même pour le réparer.
6. **`kubectl get nodes` montre la version du KUBELET**, `kubectl version` celle de l'API server.

## Les 2 chiffres

**18 min 15 s** en place, **45 s** en immuable. Mesurés sur mon lab.

## Le réflexe qui vaut le plus

**5 pannes rencontrées. 4 n'avaient RIEN à voir avec Kubernetes :** une limite du noyau, un module absent dans un conteneur, un disque plein, un RBAC qui se recharge.

> **CE N'EST PRESQUE JAMAIS KUBERNETES QUI CASSE.**

## Mes fichiers

```
~/lab-p6/
├── kind-n2.yaml                    # topologie du cluster
├── pdb-web.yaml                    # PodDisruptionBudget
├── kubeadm, kubelet                # binaires v1.35.5
├── pluto                           # détecteur d'APIs dépréciées
├── manifests/
│   ├── ingress-old.yaml            # corrigé en networking.k8s.io/v1
│   └── deploy-ok.yaml
└── backups/
    └── snap-2026-08-18-0953.db     # snapshot etcd vérifié (312 clés)
```

# 🏛️ Module 2 : Active Directory, Samba, DNS & Kerberos

## Architecture de l'Active Directory

La VM `dc-ipa` (Domain Controller) = **cerveau central** du lab, située sur `10.10.10.5`.  
On n'a pas utilisé Windows Server, mais **Samba** configuré en **Active Directory Domain Controller (AD-DC)** — un logiciel open-source qui émule parfaitement le comportement d'un Windows Server.

**Domaine :** `LAB.LOCAL`

### Les 3 piliers de l'AD

| Composant | Rôle | Analogie |
|-----------|------|----------|
| **LDAP** | Base de données des utilisateurs, groupes, ordinateurs, mots de passe hachés | 📖 L'Annuaire |
| **Kerberos** | Authentification par tickets — ne transmet **jamais** le mdp sur le réseau | 🔐 Le Vigile |
| **DNS** | Résolution de noms — guide les machines vers `lab.local` | 🗺️ Le GPS |

---

## Le Protocole Kerberos v5

### Fonctionnement
1. Tu tapes ton mot de passe **une seule fois**
2. Kerberos vérifie dans le LDAP
3. Si c'est bon → il te donne un **TGT** (Ticket Granting Ticket)
4. Ce ticket te sert de "passe-partout" pendant sa durée de validité
5. Plus besoin de renvoyer le mot de passe sur le réseau !

### ⚠️ Contrainte absolue : l'horloge
> Si le décalage entre client et serveur dépasse **5 minutes**, Kerberos **rejette tout** !  
> C'est une **protection contre les attaques par rejeu** (replay attacks) — empêche un attaquant d'intercepter un vieux ticket et de le rejouer.

### Pourquoi le DNS est critique pour Kerberos
Quand le client tape `kinit Administrator@LAB.LOCAL`, il demande au DNS :  
*"Donne-moi l'enregistrement SRV pour Kerberos dans le domaine lab.local"*  
Si le DNS répond mal → Kerberos échoue. Le DNS **doit pointer** vers le DC (`10.10.10.5`).

---

## Les démons côté client

### `smbd` (Samba Daemon)
- Gère le protocole **SMB** (Server Message Block) — partage de fichiers, RPC
- Nécessaire même pour un simple client, pour dialoguer avec le DC

### `winbindd` (Winbind)
- **Le traducteur universel** AD ↔ Linux
- Convertit les **SIDs** Windows en **UIDs/GIDs** Linux
- Va chercher les utilisateurs dans l'AD et les rend visibles au système

### NSS (Name Service Switch)
- Configuré via `/etc/nsswitch.conf`
- Dit à Linux : *"regarde d'abord en local (`/etc/passwd`), puis demande à Winbind (qui demandera à l'AD)"*

---

## Jonction du client Ubuntu au domaine — Chronologie complète

### Étape 1 : Le grand nettoyage initial

**Objectif :** Préparer la VM Ubuntu comme **client** du domaine, sans conflit.

**Problème :** La VM avait des restes de paquets serveur AD (`samba-ad-dc`). Une machine ne peut pas être DC **et** client du même domaine — les services entraient en conflit.

![Erreur DNS — apt update échoue car resolv.conf pointe vers AD](../screenshots/Module2-AD-Samba-Kerberos/Screenshot%20from%202026-06-08%2022-48-49.png)

> Les erreurs `apt update` : impossible de résoudre `archive.ubuntu.com` car le DNS pointe vers le DC qui ne connaît pas les dépôts Ubuntu.

![Erreur d'installation — paquets Kerberos introuvables](../screenshots/Module2-AD-Samba-Kerberos/Screenshot%20from%202026-06-08%2023-23-34.png)

> Tentative d'installation de paquets Kerberos échouée : les résolutions DNS sont cassées.

**Correction :**
```bash
# Purger le paquet serveur AD (conflit client/serveur)
sudo apt purge samba-ad-dc -y

# Installer les modules clients nécessaires
sudo apt install winbind libnss-winbind libpam-winbind -y
```

| Paquet | Rôle |
|--------|------|
| `winbind` | Le démon de traduction AD ↔ Linux |
| `libnss-winbind` | Permet à Linux de voir les utilisateurs AD via `getent` |
| `libpam-winbind` | Permet l'authentification AD pour SSH / session graphique |

---

### Étape 2 : Configuration de l'intégration

**Objectif :** Expliquer à Samba et Linux comment trouver le domaine et gérer les comptes.

#### Fichier `/etc/samba/smb.conf`
```ini
[global]
workgroup = LAB
security = ADS
realm = LAB.LOCAL
idmap config * : backend = tdb
idmap config * : range = 3000-7999
```

> **idmap :** Un utilisateur Windows a un SID (très long). Linux ne comprend que les UIDs numériques. Cette config dit à Samba : *"Attribue un numéro entre 3000 et 7999 à chaque utilisateur AD qui se connecte sur cette machine"*.

#### Fichier `/etc/nsswitch.conf`
```
passwd:         files winbind
group:          files winbind
```

---

### Étape 3 : Le crash de l'horloge et la perte de réseau (Le piège Kerberos)

**Problème :** Erreur massive lors d'un `apt update` : *"Le fichier Release n'est pas encore valable"*. La VM avait **11 heures de retard** sur l'horloge réelle. De plus, plus de résolution DNS → pas d'Internet.

![Erreur NTP — chronyd échoue car un autre process tourne déjà](../screenshots/Module2-AD-Samba-Kerberos/Screenshot%20from%202026-06-09%2000-00-25.png)

> `chronyd` refuse de démarrer car un autre processus est déjà actif.

![Erreur d'horloge — apt update "Release n'est pas encore valable"](../screenshots/Module2-AD-Samba-Kerberos/Screenshot%20from%202026-06-09%2012-01-54.png)

> `apt update` échoue : le fichier Release *"n'est pas encore valable (invalide pendant encore 3h 15min)"* — preuve du décalage horaire.

**Explication :** Au réveil d'une mise en pause de VM, l'horloge interne se désynchronise. Sans heure parfaite, Kerberos bloque tout.

**Correction :**
```bash
# 1. DNS temporaire pour récupérer Internet
sudo bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

# 2. Forcer l'heure manuellement
sudo timedatectl set-ntp no
sudo timedatectl set-time "12:45:00"

# 3. Remettre le DNS du DC (obligatoire pour joindre le domaine)
sudo bash -c 'echo "nameserver 10.10.10.5" > /etc/resolv.conf'
```

---

### Étape 4 : Le service manquant (`smbd` introuvable)

**Problème :** Winbind refuse de s'activer : `WBC_ERR_WINBIND_NOT_AVAILABLE`. En essayant de relancer smbd : `Failed to restart smbd.service: Unit smbd.service not found.`

![Erreur smbd — service introuvable après purge](../screenshots/Module2-AD-Samba-Kerberos/Screenshot%20from%202026-06-09%2012-01-01.png)

> `systemctl restart smbd` → **Unit smbd.service not found**. Le paquet `samba` a été supprimé lors du nettoyage.

**Explication :** Le `apt purge` de l'étape 1 a supprimé le paquet global `samba`. Winbind s'est retrouvé isolé, sans le démon `smbd`.

**Correction :**
```bash
sudo apt update
sudo apt install samba -y
sudo systemctl enable smbd winbind
sudo systemctl restart smbd winbind
```

---

### Étape 5 : Saturation des connexions & conflit d'identifiants

**Problème :** `net ads join` échoue : *"No more connections can be made to this remote computer at this time because the computer has already accepted the maximum number of connections."*
Puis : `Preauthentication failed / Invalid credentials`.

![Erreurs multiples — net ads join échoue, max connections atteintes](../screenshots/Module2-AD-Samba-Kerberos/Screenshot%20from%202026-06-09%2000-45-39.png)

> Série d'erreurs : le DC a saturé sa table de connexions TCP/SMB (protection DoS) et le mot de passe admin est corrompu.

![Tentatives de jonction — failed to lookup DC info, preauthentication failed](../screenshots/Module2-AD-Samba-Kerberos/Screenshot%20from%202026-06-09%2000-34-50.png)

> Multiples tentatives de `net ads join` avec erreurs : *"failed to lookup DC info for domain 'LAB.LOCAL' over rpc"* et *"Preauthentication failed"*. Finalement la jonction passe mais DNS update échoue.

**Explication :**
1. Le DC a activé une protection DoS et fermé la porte
2. Le mot de passe admin était mal interprété (piège AZERTY/QWERTY lors de l'installation)

**Correction :**
```bash
# (Sur le serveur AD) : Reset du mot de passe avec une chaîne simple
sudo samba-tool user setpassword Administrator --newpassword=badrnadi0.

# (Sur le client Ubuntu) : Purge des secrets corrompus
sudo rm -f /var/lib/samba/private/secrets.tdb

# Test de ticket Kerberos (preuve que le mdp fonctionne)
kinit Administrator@LAB.LOCAL

# Jonction officielle
sudo net ads join -U Administrator -S 10.10.10.5
```

### Succès de la jonction

![Jonction réussie — kinit + net ads join acceptés](../screenshots/Module2-AD-Samba-Kerberos/Screenshot%20from%202026-06-09%2012-56-48.png)

> `kinit Administrator@LAB.LOCAL` accepté → ticket Kerberos obtenu. Puis `net ads join` réussit : *"Joined 'BADR-VIRTUALBOX' to dns domain 'lab.local'"*.

---

### Étape 6 : Premier succès — `wbinfo -u`

**Objectif :** Tester si Winbind arrive à lire le contenu de l'Active Directory.

![wbinfo -u — liste des utilisateurs AD visible](../screenshots/Module2-AD-Samba-Kerberos/Screenshot%20from%202026-06-09%2012-59-59.png)

> `wbinfo -u` affiche enfin les utilisateurs du domaine :
> ```
> LAB\administrator
> LAB\guest
> LAB\krbtgt
> ```
> **Victoire !** Le canal RPC chiffré entre Winbind et le DC est opérationnel.

---

### Étape 7 : Intégration finale — getent, id, shell

**Problème :** `getent passwd administrator` renvoyait `/bin/false` (pas de shell). Sans le préfixe `LAB\`, Linux était perdu.

![getent passwd — administrator avec /bin/false](../screenshots/RBAC-PAM/Screenshot%20from%202026-06-09%2013-07-34.png)

> Première tentative : `administrator:*:3000:3006::/home/LAB/administrator:/bin/false` — le shell est bloqué.

**Correction :** Ajout de 4 options cruciales dans `/etc/samba/smb.conf` :
```ini
winbind enum users = yes       # Force Winbind à donner toute la liste à Linux
winbind enum groups = yes      # Idem pour les groupes
winbind use default domain = yes  # Taper "administrator" au lieu de "LAB\administrator"
template shell = /bin/bash     # Donne un vrai terminal aux utilisateurs AD
```

```bash
sudo systemctl restart smbd winbind
```

### Résultat final 🏆

![getent passwd — administrator avec /bin/bash](../screenshots/RBAC-PAM/Screenshot%20from%202026-06-09%2013-09-00.png)

> **Avant :** `administrator:*:3000:3006::/home/LAB/administrator:/bin/false`  
> **Après :** `administrator:*:3000:3006::/home/LAB/administrator:/bin/bash` ✅

**Analyse technique de la ligne (à retenir par cœur) :**

| Champ | Valeur | Signification |
|-------|--------|---------------|
| Nom | `administrator` | Utilisateur AD, reconnu nativement par Linux |
| UID | `3000` | Généré par `idmap_tdb` (dans la plage 3000-7999) ✅ |
| GID | `3006` | Groupe principal (Domain Users) |
| Home | `/home/LAB/administrator` | Chemin du répertoire personnel |
| Shell | `/bin/bash` | Terminal fonctionnel (SSH, session graphique) ✅ |

---

## Création d'utilisateurs et vérification RBAC

### Sur le DC (10.10.10.5)
```bash
# Créer un utilisateur
sudo samba-tool user create testadmin

# L'ajouter au groupe Domain Admins
sudo samba-tool group addmembers 'Domain Admins' testadmin
```

### Vérification côté client (10.10.10.10)

![id testadmin — UID, GID, groupes AD visibles + su - testadmin](../screenshots/RBAC-PAM/Screenshot%20from%202026-06-09%2015-56-56.png)

> `id testadmin` confirme :
> - **UID** : 3001 (dans la plage idmap)
> - **Groupes** : domain users (3006), **domain admins** (3007), BUILTIN\administrators (3000)
> 
> `su - testadmin` réussit l'authentification AD mais alerte que `/home/LAB/testadmin` n'existe pas encore (résolu avec PAM plus tard).

---

## Protocoles et processus en jeu

### Communication
| Protocole | Rôle |
|-----------|------|
| **Kerberos** | Génère des tickets pour prouver l'identité sans envoyer le mdp |
| **RPC/Samba (SMB)** | Langage pour que Linux "parle" avec Windows — crée le compte machine |

### Processus de jonction
| Commande / Service | Rôle |
|-------------------|------|
| `net ads join` | Crée une relation de confiance — la machine reçoit un "machine secret" |
| `winbind` | Le traducteur — comprend les utilisateurs AD (ex: `LAB\Administrator`) |
| `nsswitch.conf` | Le panneau de contrôle — dit à Linux où chercher les utilisateurs |

### Le mapping d'identifiants (idmap)
> *"Dans un Active Directory Windows, un utilisateur est identifié par un **SID**. Mais Linux ne comprend que les **UID/GID** numériques. J'ai configuré le sous-système **idmap_tdb** dans Samba avec une plage stricte (3000-7999) pour que chaque utilisateur AD reçoive dynamiquement un UID unique et persistant."*

### Le triptyque critique de Kerberos : Heure, DNS, Secret
> *"Kerberos v5 exige un décalage horaire < 5 minutes (protection contre les replay attacks). J'ai synchronisé le client manuellement et fait pointer le DNS exclusivement vers le DC pour que le Realm Kerberos soit découvert automatiquement."*

# 🌐 Étape 4 : Garder un oeil sur le trafic avec Squid (Forward & Transparent)

## 1. Forward Proxy Explicite (Module 4.1)

### L'idée de base

Le **Forward Proxy** (Squid) = le **surveillant** à la porte de sortie du réseau.
- **Surveille** qui sort vers Internet
- **Interdit** certains sites (YouTube, Facebook, etc.)
- **Garde un registre** complet (les logs d'audit)

**Machine :** `proxy-squid` (`10.10.10.20`)

### Installation

```bash
sudo apt update && sudo apt install squid -y
```

### Squid démarré et opérationnel

![Squid — service actif et en écoute sur le port 3128](../screenshots/Module4-Proxy-Squid/Screenshot%20from%202026-07-12%2004-26-23.png)

> `systemctl status squid` confirme le service **active (running)**. Squid traite la configuration : ACL `lan_net` pour `10.10.10.0/24`, `http_access allow lan_net`, `http_access deny all`, port `3128`. Le service écoute sur `[::]:3128`.

### Comment j'ai configuré ça (`/etc/squid/squid.conf`)

```conf
# --- Qui a le droit d'utiliser ce proxy ---
acl lan_net src 10.10.10.0/24      # DÉFINIT le réseau LAN autorisé
http_access allow lan_net          # AUTORISE ce groupe
http_access deny all               # REFUSE tout le reste (default-deny)

# --- Sur quelle adresse/port Squid écoute ---
http_port 10.10.10.20:3128

# --- Journal d'audit ---
access_log /var/log/squid/access.log squid
```

> ⚠️ **Important :** Squid lit les règles **de haut en bas**. La première qui matche s'applique !  
> Si `allow all` est avant `deny youtube`, YouTube marchera quand même.

### Problème rencontré
- Le ping entre pfSense et proxy-squid ne marchait pas
- **Cause :** il manquait la règle **"from LAN to Any"** dans pfSense
- **Solution :** Ajouter la règle → tout a marché immédiatement

### Test du proxy explicite depuis le client

![curl via proxy — réponse HTTP 301 via proxy-squid](../screenshots/Module4-Proxy-Squid/Screenshot%20from%202026-07-12%2004-47-02.png)

> `curl -x http://10.10.10.20:3128 -I http://1.1.1.1` → réponse `HTTP/1.1 301 Moved Permanently`. Le header **`Via: 1.1 proxy-squid (squid/6.14)`** prouve que le trafic passe bien par Squid.

---

## 2. Filtrage de sites (Module 4.2)

### Créer la liste noire

```bash
sudo tee /etc/squid/blocked_sites.txt >/dev/null <<'EOF'
.youtube.com
.googlevideo.com
.facebook.com
.tiktok.com
EOF
```

### Comment j'ai configuré ça Squid avec filtrage

![squid.conf — ACL blocked_domains + deny](../screenshots/Module4-Proxy-Squid/Screenshot%20from%202026-07-16%2013-38-37.png)

> Configuration visible dans le fichier `squid.conf` : l'ACL `blocked_domains` pointe vers `/etc/squid/blocked_sites.txt`, et la règle `http_access deny blocked_domains` est placée **avant** `http_access deny all`.

```conf
acl lan_net src 10.10.10.0/24
acl blocked_domains dstdomain "/etc/squid/blocked_sites.txt"
http_access deny blocked_domains    # ← DOIT être AVANT le allow !
http_access allow lan_net
http_access deny all
```

### Erreur de configuration rencontrée

![Squid — erreur ACL type 'domains' invalide](../screenshots/Module4-Proxy-Auth-AD/Screenshot%20from%202026-07-16%2015-23-14.png)

> `squid -k parse` révèle une erreur : *"invalid ACL type 'domains'"* — le mot-clé correct est `dstdomain` et non `domains`. Après correction, Squid redémarre avec succès.

---

## 3. Proxy Transparent (Module 4.4)

### Pourquoi ?

Avec un proxy **explicite**, l'utilisateur peut simplement le **désactiver** dans son navigateur et contourner tout le filtrage.  
Le proxy **transparent** intercepte le trafic **automatiquement** via pfSense — l'utilisateur ne peut rien faire.

### Fonctionnement

```
Client HTTP (port 80) → pfSense → DNAT (PREROUTING) → Squid (port 3129 intercept)
```

> C'est le même mécanisme que le port forwarding du Module 3, mais dans l'autre sens (trafic **sortant** au lieu de trafic entrant).

### Comment j'ai configuré ça Squid — port intercept

```bash
sudo nano /etc/squid/squid.conf
```
Ajouter :
```conf
http_port 10.10.10.20:3129 intercept
```
> Le mot-clé `intercept` dit à Squid d'attendre du trafic détourné et de reconstruire la destination à partir de l'entête `Host:`.

### Comment j'ai configuré ça pfSense (NAT > Port Forward)

| Paramètre | Valeur |
|-----------|--------|
| Interface | LAN |
| Protocol | TCP |
| Source | `! 10.10.10.20` (**Invert match** pour éviter la boucle !) |
| Dest Port | 80 (HTTP) |
| Redirect target IP | `10.10.10.20` |
| Redirect target Port | `3129` |

> ⚠️ **Piège critique :** Sans l'invert match (`! 10.10.10.20`), le trafic de Squid lui-même serait re-redirigé → **boucle infinie** !

> ⚠️ **Limitation :** Ne fonctionne que pour HTTP (port 80). HTTPS nécessite le **SSL Bump** (Module 4.6).

### Le fil rouge à retenir
> **Un point de passage obligé** (pfSense est la seule sortie) **+ une réécriture de destination au bon moment** (DNAT en PREROUTING) **= interception invisible et incontournable.**

### Test de validation

```bash
# Sur lan-client : supprimer toute config proxy
unset http_proxy
unset https_proxy

# Requête sans proxy configuré
curl -I http://neverssl.com

# Sur proxy-squid : vérifier que la requête apparaît dans les logs
sudo tail -n 5 /var/log/squid/access.log
sudo grep neverssl /var/log/squid/access.log
```

> Si l'IP `10.10.10.10` apparaît dans le `access.log` malgré l'absence de configuration proxy sur le client, l'interception fonctionne ! 🎯

---

## 4. Analyse des logs Squid

### Top 10 des URLs les plus visitées

```bash
sudo awk '{print $7}' /var/log/squid/access.log | sort | uniq -c | sort -rn | head
```

**Décryptage de la commande (la magie des pipes `|`) :**
- `awk '{print $7}'` → extrait la 7ème colonne (l'URL)
- `sort` → trie alphabétiquement (nécessaire pour `uniq`)
- `uniq -c` → compte les occurrences identiques
- `sort -rn` → tri numérique décroissant (`r`=reverse, `n`=numeric)
- `head` → affiche le top 10

### Isoler le trafic d'une machine suspecte

```bash
# Filtrer par IP (ex: machine d'un employé suspect)
sudo grep '10.10.10.10' /var/log/squid/access.log
# Ajouter | less si le fichier est trop long
```

### Squid parse — validation de la config complète

![Squid -k parse — toute la configuration traitée avec succès](../screenshots/Module4-Proxy-Squid/Screenshot%20from%202026-07-16%2014-14-24.png)

> `squid -k parse` valide toute la configuration : Kerberos negotiate auth, ACLs (lan_net, blocked_domains, authenticated), ports (3128), et les règles d'accès dans l'ordre correct.

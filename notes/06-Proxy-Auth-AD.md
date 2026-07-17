# 🔑 Module 4.7 : Authentification Proxy via Active Directory

## L'idée de base

Passer de la sécurité **par IP** à la sécurité **par identité** (Identity-Based Security).

### Avantages
1. **Traçabilité absolue** : les logs Squid montrent *"l'utilisateur **jdoe** est allé sur facebook.com"* au lieu d'une simple IP
2. **Filtrage par groupe** : *"Le groupe Marketing peut accéder aux réseaux sociaux, le groupe Comptabilité non"*

---

## Protocole : Kerberos SSO (Single Sign-On)

L'utilisateur n'a même **pas besoin de taper son mot de passe** au proxy !  
Squid regarde son **ticket Kerberos** (généré automatiquement à l'ouverture de session) et le laisse passer.

---

## Comment j'ai configuré ça

### Sur `proxy-squid` : Modifier `squid.conf`

![squid.conf — Configuration complète avec Kerberos auth](../screenshots/Module4-Proxy-Auth-AD/Screenshot%20from%202026-07-16%2015-21-51.png)

> Le fichier `squid.conf` final avec toutes les ACLs en place : `lan_net`, `blocked_domains`, `authenticated` (proxy_auth REQUIRED), les paramètres `auth_param negotiate` pour Kerberos, et l'ordre des règles d'accès.

```conf
# 1. Dire à Squid comment parler à l'AD via Kerberos
auth_param negotiate program /usr/lib/squid/negotiate_kerberos_auth -s GSS_C_NO_NAME
auth_param negotiate children 10

# 2. Créer une règle "Il FAUT être authentifié"
acl authenticated proxy_auth REQUIRED

# 3. Autoriser ceux qui sont authentifiés
http_access allow authenticated

# 4. Bloquer tout le reste
http_access deny all
```

> ⚠️ **Important :** Supprimer/commenter l'ancienne règle `http_access allow lan_net` pour **forcer l'authentification** !

### Appliquer et valider

![Squid -k parse — config Kerberos validée avec succès](../screenshots/Module4-Proxy-Squid/Screenshot%20from%202026-07-16%2015-30-23.png)

> `squid -k parse` valide la configuration complète : `auth_param negotiate`, les ACLs (`lan_net`, `blocked_domains`, `authenticated`), et l'ordre des règles (`allow lan_net`, `deny blocked_domains`, `allow authenticated`, `deny all`).

```bash
sudo systemctl restart squid
```

---

## Vérification

### Côté client (`lan-client`)
- **Sans ticket de domaine** (non connecté à l'AD) → Squid renvoie erreur **407 Proxy Authentication Required**
- **Avec ticket Kerberos valide** → la requête passe sans rien demander (SSO)

### Côté proxy — les logs révèlent l'identité
```bash
sudo tail -f /var/log/squid/access.log
```

Le **nom de l'utilisateur** apparaît dans la ligne de log à la place du tiret `-` :
```
1689451200.123    200 TCP_MISS/200 1234 GET http://example.com - jdoe HIER_DIRECT/...
```

---

## Résultat 🎯

On a **bloqué l'accès à Internet sauf pour les utilisateurs authentifiés** via l'Active Directory !

- ✅ Traçabilité : chaque requête est liée à un **nom d'utilisateur**
- ✅ SSO : pas besoin de retaper le mot de passe (ticket Kerberos)
- ✅ Sécurité : les machines non-authentifiées sont bloquées (erreur 407)

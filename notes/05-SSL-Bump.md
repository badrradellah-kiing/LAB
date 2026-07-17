# 🔓 Module 4.6 : SSL Bump (Interception HTTPS)

## L'idée de base

En temps normal, Squid est **aveugle** face au trafic HTTPS — le contenu est chiffré dans un "tuyau blindé".

Le **SSL Bump** = donner à Squid l'autorisation de faire une attaque **Man-in-the-Middle** contrôlée :

1. **Intercepte** la connexion HTTPS du client
2. **Ouvre et lit** le contenu (détection virus, filtrage d'URL, DLP)
3. **Re-chiffre** le paquet avec **sa propre clé** (certificat forgé)
4. **Envoie** au serveur de destination

> C'est comme un douanier qui ouvre tes valises, les inspecte, puis les referme avec son propre cadenas.

---

## Setup : 4 étapes de préparation

Toutes les commandes sont exécutées sur la machine **`proxy-squid`** (`10.10.10.20`).

### Étape A : Créer la Clé Maître (Autorité de Certification)

```bash
sudo openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -keyout /etc/squid/bump.key -out /etc/squid/bump.crt \
  -subj "/CN=Lab Squid Proxy CA"
```

| Paramètre | Signification |
|-----------|---------------|
| `rsa:2048` | Clé de 2048 bits de robustesse |
| `days 3650` | Certificat valide **10 ans** |
| `-nodes` | Pas de phrase de passe sur la clé |
| `-x509` | Générer un certificat auto-signé (CA) |
| `bump.key` | La clé **privée** (à protéger !) |
| `bump.crt` | Le certificat **public** (à distribuer aux clients) |

> Cette CA "maîtresse" permet à Squid de forger des faux certificats à la volée (un faux certificat Google, un faux Facebook, etc.)

### Étape B : Initialiser la base de données de certificats

```bash
sudo /usr/lib/squid/security_file_certgen -c -s /var/lib/squid/ssl_db -M 4MB
sudo chown -R proxy:proxy /var/lib/squid/ssl_db
```

- Cache de **4 Mo** pour stocker les certificats déjà forgés
- Économise le CPU (pas besoin de re-créer à chaque requête)
- `chown proxy:proxy` → donne les droits de lecture/écriture au service Squid

### Étape C : Configuration Squid (`squid.conf`)

```conf
# 1. Port de déchiffrement avec nos clés CA
http_port 10.10.10.20:3130 ssl-bump \
  cert=/etc/squid/bump.crt key=/etc/squid/bump.key \
  generate-host-certificates=on

# 2. Base de données des certificats (cache)
sslcrtd_program /usr/lib/squid/security_file_certgen -s /var/lib/squid/ssl_db -M 4MB

# 3. Exceptions : NE PAS déchiffrer (splice) certains sites sensibles
acl no_bump ssl::server_name_regex "/etc/squid/no_bump.txt"
ssl_bump splice no_bump

# 4. Pour le reste : inspecter (peek) puis déchiffrer (bump)
ssl_bump peek all
ssl_bump bump all
```

| Terme | Signification |
|-------|---------------|
| **peek** | Regarder le SNI (nom du site) sans casser le chiffrement |
| **bump** | Intercepter et re-chiffrer le trafic (MITM complet) |
| **splice** | Laisser passer tel quel sans toucher (exception) |

### Étape D : Créer la liste d'exceptions et redémarrer

```bash
sudo touch /etc/squid/no_bump.txt
# Ajouter plus tard : banque.fr, whatsapp.com, etc.
sudo systemctl restart squid
```

---

## Points importants

- Certains sites (banques, WhatsApp) **détectent** les faux certificats et bloquent tout → les mettre en exception via **splice**
- Les navigateurs des clients devront **faire confiance à la CA** du proxy pour ne pas avoir d'erreur SSL
- En entreprise, la CA est déployée automatiquement via les GPO (Group Policy Objects) de l'Active Directory

# 🛡️ Étape 3 : La zone isolée (DMZ) et Nginx

## L'idée de base de la DMZ

La **DMZ** (DeMilitarized Zone) est un réseau **isolé** entre le LAN et Internet.

### Pourquoi ?
Si un hacker pirate le serveur web (Nginx), il est **coincé dans la DMZ**.  
Le firewall pfSense lui interdit d'accéder au LAN grâce à la règle de blocage **"DMZ → LAN"**.

### Comment j'ai configuré ça réseau
| Élément | Adresse |
|---------|---------|
| Réseau DMZ | `10.10.30.0/24` |
| serveur web (`web-dmz`) | `10.10.30.10` |
| Passerelle (pfSense) | `10.10.30.1` |

---

## Le trajet de la donnée

```
 ⚡ Résumé "en 2 2" : Le trajet de la donnée

 1. Le Visiteur (Internet / WAN)
    Quelqu'un tape l'adresse publique → sa requête arrive sur la porte WAN de pfSense.

 2. Le Routage (pfSense & DNAT)
    pfSense bloque tout par défaut (de base). Mais grâce au Port Forwarding (DNAT) :
    "Ah ! Requête port 80 ? → Transférer à 10.10.30.10 dans la DMZ."

 3. La Cible (Nginx en DMZ)
    La requête atterrit sur web-dmz. Nginx intercepte et renvoie sa page web.

 🛡️ Sécurité : Si le hacker pirate Nginx, il est coincé dans la DMZ.
    Le firewall pfSense lui interdit d'atteindre le LAN (règle DMZ → LAN bloquée).
```

### Test de diagnostic DMZ

![pfSense — Ping depuis la DMZ vers Internet](../screenshots/Module3-DMZ-Nginx/Screenshot%20from%202026-06-28%2008-28-02.png)

> L'outil de diagnostic pfSense (`diag_ping.php`) permet de valider que l'interface DMZ (`10.10.30.1`) a bien accès à Internet (ici `8.8.8.8`). Ça confirme que le NAT sortant et les règles de base fonctionnent pour cette zone isolée.

---

## Installation de Nginx

```bash
# Sur web-dmz (10.10.30.10)
sudo apt update && sudo apt install nginx -y
sudo systemctl start nginx
```

![web-dmz — Installation Nginx](../screenshots/Module3-DMZ-Nginx/Screenshot%20from%202026-06-28%2009-30-57.png)

> L'installation de Nginx sur la VM `web-dmz` crée automatiquement le service et active les fichiers de base.

---

## Forward Proxy vs Reverse Proxy — La règle d'or

> - Le **Forward Proxy** protège tes **utilisateurs** (qui vont vers Internet)
> - Le **Reverse Proxy** protège tes **serveurs** (depuis Internet)

| | Forward Proxy (Squid) | Reverse Proxy (Nginx) |
|---|---|---|
| **Analogie** | Le surveillant à la porte de **sortie** | Le vigile (bouncer) à l'**entrée** |
| **Protège** | Les employés / le LAN | Le serveur web / la DMZ |
| **Machine** | `proxy-squid` (10.10.10.20) | `web-dmz` (10.10.30.10) |
| **Direction** | Trafic **sortant** → Internet | Trafic **entrant** ← Internet |

---

## Comment j'ai configuré ça en Reverse Proxy (Module 4.5)

### Fichier de configuration

![Nginx — Configuration reverse proxy dans nano](../screenshots/Module3-DMZ-Nginx/Screenshot%20from%202026-07-16%2000-32-37.png)

> Configuration du reverse proxy Nginx : écoute sur le port 80, proxy_pass vers `127.0.0.1:8080`, avec les headers `X-Real-IP` et `X-Forwarded-For` pour transmettre la vraie IP du visiteur.

```bash
sudo nano /etc/nginx/sites-available/app
```

```nginx
server {
    listen 80;
    server_name web.lab.local;
    access_log /var/log/nginx/app_access.log;
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

### Activation et erreurs rencontrées

![Nginx — ln -s et erreur de configuration](../screenshots/Module3-DMZ-Nginx/Screenshot%20from%202026-07-16%2000-36-33.png)

> Tentative d'activation : le premier `ln -s` échoue (*"No such file or directory"*) — on corrige le chemin. Puis `nginx -t` échoue car le fichier sites-available/app n'avait pas été créé correctement au premier essai.

```bash
# Lien symbolique pour activer le site
sudo ln -s /etc/nginx/sites-available/app /etc/nginx/sites-enabled/

# Validation de la syntaxe + rechargement
sudo nginx -t && sudo systemctl reload nginx
```

### Test depuis l'extérieur (attacker-kali)
```bash
curl -I http://<firewall-WAN-IP>
# Objectif réussi si "Server: nginx" apparaît dans la réponse HTTP
```

---

## Schéma global du trafic

```
Trafic Sortant (Employés naviguent) :
  lan-client → Squid (Forward Proxy) → pfSense → Internet

Trafic Entrant (Clients visitent le site) :
  Internet → pfSense (DNAT port 80) → Nginx (Reverse Proxy) → Application backend
```

> **Et le Reverse Proxy dans tout ça ?**  
> Pour l'instant Nginx affiche juste "Welcome to nginx!". Prochaine étape : le transformer en **vrai** reverse proxy — au lieu d'afficher sa propre page, Nginx fera barrage et ira chercher les pages sur un serveur caché derrière lui, tout en filtrant les attaques !

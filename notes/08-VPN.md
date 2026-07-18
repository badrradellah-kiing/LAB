# 🔒 Module 5 : VPN WireGuard

## L'idée de base

Le but du VPN ici, c'est de créer un **tunnel chiffré** entre ma machine distante (le laptop) et le réseau sécurisé du lab.

### Le Principe
Au lieu de s'amuser à exposer chaque service un par un (SSH, le GUI du firewall, les sites web), on **ferme absolument tout**. On n'ouvre qu'**un seul port** : celui du VPN. 

### Résultat
Une fois connecté au VPN :
- La machine distante chope une **IP interne**.
- Elle fait comme si elle était **physiquement branchée sur le LAN**.
- La surface d'attaque est ultra réduite : on a un seul point d'entrée, et il est blindé par cryptographie.

---

## Comment ça marche ? (La théorie)

WireGuard donne une **IP unique** à chaque appareil connecté au tunnel, et pfSense gère tout ça. **J'ai fait ça exprès pour que la VM de l'IDS (Suricata) puisse voir tout le trafic en clair.**

- **Le Transport :** Kali utilise son IP physique (WAN) pour balancer le paquet vers l'adresse `Endpoint` de pfSense.
- **L'Encapsulation :** Juste avant l'envoi, Kali emballe le paquet dans une "enveloppe" chiffrée WireGuard. À l'intérieur, le paquet est marqué comme venant de l'IP du tunnel (`10.200.0.x`).
- **La Réception :** Quand pfSense reçoit le paquet, il capte direct que c'est du VPN parce que ça arrive sur l'interface du tunnel (`tun_wg0`).
- **Le Déballage :** Il retire l'enveloppe chiffrée, voit l'IP source (`10.200.0.x`), et vérifie avec les clés cryptographiques que c'est bien moi (le client légitime).
- **Le Routage :** Une fois déballé, pfSense peut appliquer ses règles de pare-feu classiques pour laisser (ou pas) ce réseau VPN accéder au LAN ou à la DMZ.

---

# 📑 DOCUMENTATION TECHNIQUE : Déploiement VPN WireGuard (pfSense / Kali)

## 1. Setup côté pfSense (La passerelle)

**But :** Transformer pfSense en serveur VPN.

- **Étape 1 : Installer le paquet**
    - Interface Web pfSense > `System` > `Package Manager` > `Available Packages`. J'ai installé `WireGuard`.
    - *Note :* WireGuard n'est pas là par défaut, faut rajouter le module.

- **Étape 2 : Créer le Tunnel (Le Serveur)**
    - `VPN` > `WireGuard` > `Tunnels` > `Add`.
    - Nom : `tun_wg0` (Description : `VPN_REMOTE`), Port d'écoute : `51820` (le port standard UDP). J'ai généré les clés du serveur ici.

![pfSense — VPN / WireGuard / Tunnels](../screenshots/Module5-VPN/Screenshot%20from%202026-07-16%2015-32-53.png)

- **Étape 3 : Assigner l'interface**
    - `Interfaces` > `Assignments`. J'ai ajouté `tun_wg0` (OPT2) et je l'ai renommée en `WIRE_GUARD` avec l'IP statique `10.200.0.1/24`.
    - *(Petite erreur au passage : "Sorry, an interface group with the name WIREGUARD already exists" — j'ai juste mis un underscore pour régler ça).*

![pfSense — Interface OPT2 (tun_wg0) — Configuration WireGuard](../screenshots/Module5-VPN/Screenshot%20from%202026-07-16%2015-39-03.png)

- **Étape 4 : Règles de Pare-feu**
    - *Sur le WAN :* J'ai autorisé le trafic `UDP` entrant sur le port `51820`. Indispensable pour que le tunnel soit joignable depuis Kali.
    - *Sur WireGuard :* J'ai autorisé tout le trafic (Any) depuis la source `10.200.0.0/24`. Comme ça, une fois connecté, le client a le droit de traverser vers le LAN/DMZ.

![pfSense — Règles Firewall WAN VPN](../screenshots/Module5-VPN/Screenshot%20from%202026-07-17%2019-27-04.png)

## 2. Setup côté Attaquant (Kali Linux)

**But :** Préparer Kali et générer ses clés.

- **Étape 1 : Installer les outils**
    - `sudo apt update` puis `sudo apt install wireguard -y`

- **Étape 2 : Générer les clés cryptographiques**
    - J'ai balancé la commande : `wg genkey | tee client_private.key | wg pubkey | tee client_public.key`


## 3. Le Handshake (Authentification mutuelle)

- **Étape 1 : Dire à pfSense d'accepter Kali**
    - Dans pfSense > `VPN` > `WireGuard` > `Peers` > `Add`.
    - J'ai collé la clé publique de Kali (`eVzvZLV...`) et je l'ai associée à l'IP `10.200.0.2/32`.

![pfSense — Configuration du Peer Kali](../screenshots/Module5-VPN/Screenshot%20from%202026-07-17%2020-32-09.png)

- **Étape 2 : Fichier de conf sur Kali**
    - `sudo nano /etc/wireguard/wg0.conf`


## 4. Le Grand Blocage : Les "bulles" réseaux de VirtualBox

- Je lance le VPN : `sudo wg-quick up wg0`.
- ⚠️ **Galère n°1 : Le dialogue de sourds (0 B received)**
    - L'interface monte bien, Kali envoie des paquets (296 B sent), mais pfSense ne répond jamais. Pas de "latest handshake".
    - *Diagnostic :* En faisant un `ip a` sur Kali, je vois qu'elle a l'IP `10.0.2.15`... C'est littéralement la même IP WAN que pfSense. Le mode NAT par défaut de VirtualBox isolait chaque VM dans sa propre petite bulle.

![Kali — Dialogue de sourds (0 B received)](../screenshots/Module5-VPN/Screenshot%20from%202026-07-17%2020-43-55.png)
![Kali — Conflit d'IP VirtualBox](../screenshots/Module5-VPN/Screenshot%20from%202026-07-17%2020-45-14.png)

- ⚠️ **Galère n°2 : Le réseau du CROUS bloque tout**
    - J'ai essayé de passer les cartes en "Accès par pont" (Bridged) pour régler le souci, mais pfSense ne recevait aucune IP.
    - *Raison :* Le réseau physique de la fac bloque la distribution d'IP directes aux VM pour des raisons de sécurité. Impossible de faire du bridge.

- **LA RÉSOLUTION : Le NatNetwork**
    1. Dans VirtualBox : `Fichier > Outils > Réseaux NAT`. J'ai créé un `NatNetwork` global en `10.0.2.0/24`.
    2. J'ai branché la carte WAN de pfSense et la carte de Kali sur ce nouveau réseau NAT.
    3. Sur la console pfSense, j'ai forcé le renouvellement DHCP. pfSense a pris `10.0.2.15` et Kali a reçu une autre IP. Enfin, elles pouvaient se pinger !

## 5. Validation de bout en bout

- **Test 1 : Le Handshake cryptographique**
    - `sudo wg`
    - *Boum !* `latest handshake: 2 seconds ago` et `transfer: 124 B received`. Le tunnel est officiellement monté.

![Kali — Handshake réussi](../screenshots/Module5-VPN/Screenshot%20from%202026-07-17%2021-07-49.png)

- **Test 2 : Le Routage (Pings)**
    - `ping -c 4 10.200.0.1` (passerelle VPN) -> OK !
    - `ping -c 4 10.10.10.1` (passerelle LAN interne) -> OK ! Ça prouve que pfSense route bien le trafic VPN vers l'intérieur.

![Kali — Ping vers LAN interne](../screenshots/Module5-VPN/Screenshot%20from%202026-07-17%2021-10-44.png)

- **Test 3 : L'accès Applicatif**
    - J'ouvre Firefox sur Kali, je tape `http://10.10.10.1`... et la page de login pfSense s'affiche.
    - Accès distant simulé avec succès à 100%.

![Kali — Accès Interface pfSense](../screenshots/Module5-VPN/Screenshot%20from%202026-07-17%2021-11-42.png)

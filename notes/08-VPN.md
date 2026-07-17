# 🔒 Module 5 : VPN WireGuard

## L'idée de base

Le VPN crée un **tunnel chiffré** entre une machine distante et le réseau sécurisé.

### Principe

Au lieu d'exposer chaque service individuellement (SSH, GUI firewall, apps web), on **ferme tout** et on n'ouvre qu'**un seul port** : celui du VPN.

### Résultat

Une fois connecté au VPN :
- la VM distante reçoit une **IP interne** du réseau
- Elle se comporte comme si elle était **physiquement branchée sur le LAN**
- Surface d'attaque réduite à **un seul point d'entrée**, fortement authentifié

---

## Comment j'ai configuré ça WireGuard dans pfSense

### Création du tunnel WireGuard

![pfSense — VPN / WireGuard / Tunnels](../screenshots/Module5-VPN/Screenshot%20from%202026-07-16%2015-32-53.png)

> Tunnel WireGuard créé dans pfSense : **tun_wg0**, description **"VPN_REMOTE"**, port d'écoute **51820**, clé publique générée. Le service WireGuard n'est pas encore démarré à ce stade.

### Comment j'ai configuré ça de l'interface WireGuard

![pfSense — Interface OPT2 (tun_wg0) — Configuration WireGuard](../screenshots/Module5-VPN/Screenshot%20from%202026-07-16%2015-39-03.png)

> L'interface `tun_wg0` est assignée en tant qu'**OPT2** avec la description **"WIREGUARD"**. Configuration IPv4 en **Static IPv4**. Erreur rencontrée : *"Sorry, an interface group with the name WIREGUARD already exists"* — à résoudre en renommant.

---

## Prochaines étapes (EN COURS)

- [ ] Configurer le Peer (client distant) avec sa clé publique
- [ ] Attribuer une IP au tunnel (ex: `10.10.50.1/24`)
- [ ] Créer les règles firewall pour l'interface WireGuard
- [ ] Tester la connexion depuis la VM `attacker-kali` (simulation accès distant)
- [ ] Valider l'accès au LAN depuis le tunnel VPN

---

> 🚧 **Module en cours de réalisation** — Notes à compléter au fur et à mesure.

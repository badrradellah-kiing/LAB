# Module 7 — Host Hardening

### Ma doc perso du lab

Voilà tout ce que j'ai fait dans ce module, expliqué comme si je me le racontais à moi-même dans 6 mois quand j'aurai tout oublié. Le but c'est de durcir mes machines pour qu'elles soient chiantes à attaquer.

**Le contexte vite fait :**
- Machine que je durcis à fond : `proxy-squid` (10.10.10.20)
- VM que j'ai montée pour Ansible : `mgmt-ansible` (10.10.99.10)
- Les 3 machines que je gère : proxy (10.10.10.20), web-dmz (10.10.30.10), lan-client (10.10.10.10)

**La règle que j'ai apprise à la dure :** avant de toucher à SSH ou d'activer un pare-feu, TOUJOURS garder une deuxième session ouverte. Sinon tu te verrouilles dehors comme un con.

---

## Sommaire
- [7.1 — Durcir SSH](#71--durcir-ssh)
- [7.2 — Pare-feu sur la machine (ufw)](#72--pare-feu-sur-la-machine-ufw)
- [7.3 — Fail2Ban (le videur automatique)](#73--fail2ban-le-videur-automatique)
- [7.4 — Gestion centralisée avec Ansible](#74--gestion-centralisée-avec-ansible)
- [7.5 — MFA / Authentification à deux facteurs](#75--mfa--authentification-à-deux-facteurs)

---

## 7.1 — Durcir SSH

### Le principe
SSH c'est la porte d'entrée de toutes mes machines. Si quelqu'un le pète, il a accès à tout. Donc première chose : on verrouille ça proprement.

### Ce que j'ai changé dans `/etc/ssh/sshd_config` sur proxy-squid

```
PermitRootLogin no              # personne se connecte en root
PasswordAuthentication no       # plus de mot de passe, que des clés
PubkeyAuthentication yes        # seule méthode autorisée
AllowUsers badr                 # que moi, personne d'autre
MaxAuthTries 3                  # 3 essais et tu dégages
LoginGraceTime 20               # 20 secondes pour t'authentifier
Protocol 2                      # que le protocole 2 (le 1 est mort)
```

> **Le piège Protocol 2 :** j'ai mis `Protocol 2` dans ma config et `sshd -t` m'a gueulé dessus. Normal : sur les versions récentes d'OpenSSH (9.x), cette directive n'existe plus car le protocole 1 a été complètement retiré. C'est déjà du Protocol 2 par défaut. J'ai dû retirer la ligne.

### Mise en place des clés SSH

1. Génération d'une paire Ed25519 sur mon poste :
```bash
ssh-keygen -t ed25519 -C "lab-admin"
```

2. Copie de la clé publique vers proxy-squid :
```bash
ssh-copy-id badr@10.10.10.20
```

3. Vérification — connexion sans mot de passe :
```bash
ssh badr@10.10.10.20
```

4. Test de sécurité — on vérifie que `sshd -t` passe proprement :
```bash
sudo sshd -t
cat ~/.ssh/authorized_keys
```

### Preuves visuelles
| Capture | Description |
|---------|-------------|
| ![sshd_config durci](../screenshots/Module7-Host-Hardening/7.1-sshd-config-hardened-nano.png) | Configuration SSH complète dans nano : PermitRootLogin no, PasswordAuth no, PubkeyAuth yes, AllowUsers badr, MaxAuthTries 3, Protocol 2 |
| ![sshd -t + authorized_keys](../screenshots/Module7-Host-Hardening/7.1-sshd-test-authorized-keys.png) | `sshd -t` qui passe + vérification de la clé autorisée |

---

## 7.2 — Pare-feu sur la machine (ufw)

### Pourquoi ufw en plus de pfSense ?
pfSense c'est le garde à l'entrée du réseau. Mais si quelqu'un arrive à passer (pivot, accès physique, whatever), il faut que la machine elle-même se défende. C'est le principe de la **défense en profondeur**.

### La politique que j'ai appliquée

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow from 10.10.10.0/2 to any port 22 proto tcp    
sudo ufw allow from 10.10.10.0/24 to any port 3128 proto tcp 
sudo ufw allow from 10.10.10.0/24 to any port 3129 proto tcp 
sudo ufw allow from 10.10.10.0/24 to any port 3130 proto tcp 

sudo ufw enable
```

### Vérification

```bash
sudo ufw status verbose
```

Test depuis le proxy et depuis lan-client :
```bash
ping -c2 1.1.1.1        
ping -c2 example.com    
curl -x http://10.10.10.20:3128 -I http://example.com 

curl -x http://10.10.10.20:3128 -I http://example.com
```

### Preuves visuelles
| Capture | Description |
|---------|-------------|
| ![ufw setup](../screenshots/Module7-Host-Hardening/7.2-ufw-setup-default-deny-rules.png) | Mise en place d'ufw : default deny, règles SSH + Squid, activation |
| ![ufw status verbose](../screenshots/Module7-Host-Hardening/7.2-ufw-status-verbose-squid-ports.png) | `ufw status verbose` + ajout des ports 3129/3130 + test ping/curl |
| ![curl through proxy](../screenshots/Module7-Host-Hardening/7.2-ufw-curl-through-proxy-working.png) | Curl depuis lan-client à travers le proxy — cache hit confirmé |

---

## 7.3 — Fail2Ban (le videur automatique)

### Le principe
Fail2Ban surveille les logs SSH (et autres) et ban automatiquement les IP qui échouent trop de fois. C'est comme un videur de boîte de nuit : tu te plantes 5 fois, tu dégages.

### Installation et config

```bash
sudo apt install fail2ban -y
```

Puis j'ai créé `/etc/fail2ban/jail.local` :

```ini
[DEFAULT]
bantime = 15m
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
backend = systemd
```

### Le bordel que j'ai eu

Oh putain, ça a été un festival d'erreurs :

1. **Socket error au démarrage** — le service refusait de démarrer, erreur de socket.
2. **Duplicate `bantime`** — j'avais copié-collé un truc et j'avais `bantime` en double dans ma config. Le parser a pété.
3. **Duplicate `[sshd]` section** — pareil, j'avais deux sections `[sshd]` dans le fichier. Fail2Ban supporte pas ça.
4. **Service qui restart mais fail encore** — parce que j'avais pas nettoyé TOUTES les duplications.

### Comment j'ai résolu

J'ai tout repris de zéro :
```bash
sudo nano /etc/fail2ban/jail.local

sudo fail2ban-client -t

sudo systemctl restart fail2ban
sudo systemctl status fail2ban
```

### Vérification que ça tourne

```bash
sudo fail2ban-client status sshd
```

La jail SSH est active, zéro ban pour l'instant (normal, c'est un lab isolé).

### Preuves visuelles
| Capture | Description |
|---------|-------------|
| ![jail.local config](../screenshots/Module7-Host-Hardening/7.3-fail2ban-jail-local-config.png) | Configuration jail.local dans nano |
| ![socket error](../screenshots/Module7-Host-Hardening/7.3-fail2ban-install-socket-error.png) | Première erreur : socket au démarrage |
| ![service failed](../screenshots/Module7-Host-Hardening/7.3-fail2ban-service-failed-status.png) | Service en état failed |
| ![duplicate bantime](../screenshots/Module7-Host-Hardening/7.3-fail2ban-duplicate-bantime-error.png) | Erreur de duplicate `bantime` |
| ![still failing](../screenshots/Module7-Host-Hardening/7.3-fail2ban-still-failing-restart.png) | Ça fail encore après un premier fix |
| ![duplicate sshd](../screenshots/Module7-Host-Hardening/7.3-fail2ban-duplicate-sshd-section.png) | Le vrai problème : section [sshd] en double |
| ![config test OK](../screenshots/Module7-Host-Hardening/7.3-fail2ban-config-test-success.png) | `fail2ban-client -t` qui passe enfin |
| ![jail active](../screenshots/Module7-Host-Hardening/7.3-fail2ban-sshd-jail-active.png) | Jail sshd active et fonctionnelle |

---

## 7.4 — Gestion centralisée avec Ansible

### Le plan
Au lieu de me connecter sur chaque machine pour appliquer le hardening, j'ai monté une VM dédiée `mgmt-ansible` (10.10.99.10) qui gère tout depuis un point central. L'idée c'est : j'écris un playbook une fois, je l'applique sur les 3 machines en une commande.

### Étape 1 : Monter la VM mgmt-ansible

**Réseau :** nouveau subnet MGMT (10.10.99.0/24) sur pfSense, dédié à l'administration.

J'ai dû :
1. Ajouter l'interface dans pfSense (pas sans galère — erreur ARP au début)
2. Installer Ubuntu Server sur la VM
3. Configurer le réseau en statique via netplan :

```yaml
# /etc/netplan/00-installer-config.yaml
network:
  version: 2
  ethernets:
    enp0s3:
      addresses: [10.10.99.10/24]
      routes:
        - to: default
          via: 10.10.99.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
```

4. Ajouter les règles firewall sur pfSense pour que MGMT puisse parler aux autres VLANs (LAN, DMZ)

**Test de connectivité :**
```bash
ping 10.10.10.20  
ping 10.10.10.1   
ping 1.1.1.1      
```

### Étape 2 : Distribution des clés SSH

Depuis mgmt-ansible, j'ai généré une clé Ed25519 et distribué sur toutes les machines :

```bash
ssh-keygen -t ed25519
ssh-copy-id badr@10.10.10.10  
ssh-copy-id badr@10.10.30.10  
```

> **Le piège ssh-copy-id :** la première fois j'ai eu "No identities found" parce que j'avais pas encore généré la clé sur mgmt-ansible. Faut faire `ssh-keygen` AVANT `ssh-copy-id`, logique mais quand t'es fatigué tu oublies.

Vérification avec `ssh hostname` :
```bash
ssh badr@10.10.10.10 hostname 
ssh badr@10.10.10.20 hostname 
ssh badr@10.10.30.10 hostname 
```

### Étape 3 : Premier test Ansible

```bash
sudo apt install ansible -y
```

Fichier d'inventaire `inventory.ini` :
```ini
[web]
10.10.30.10 ansible_become_pass=badr

[proxy]
10.10.10.20 ansible_become_pass=badr

[clients]
10.10.10.10 ansible_become_pass=badrnadi

[all:vars]
ansible_user=badr
ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

Test de connectivité Ansible :
```bash
ansible all -i inventory.ini -m ping
```

Les 3 machines répondent. On est bon.

### Étape 4 : Playbook de hardening

Fichier `harden.yml` :
```yaml
- hosts: all
  become: true
  tasks:
    - name: Report how many security updates are pending
      command: apt list --upgradable
      register: upd
      changed_when: false

    - name: Apply all security updates
      apt: { upgrade: dist, update_cache: yes }

    - name: Enforce hardened sshd settings
      lineinfile:
        path: /etc/ssh/sshd_config
        regexp: "{{ item.re }}"
        line: "{{ item.line }}"
      loop:
        - { re: '^#?PermitRootLogin', line: 'PermitRootLogin no' }
        - { re: '^#?PasswordAuthentication', line: 'PasswordAuthentication no' }
      notify: restart ssh

  handlers:
    - name: restart ssh
      service: { name: ssh, state: restarted }
```

> **Le YAML de merde :** j'ai dû m'y reprendre à 3-4 fois avant que la syntaxe passe. Des espaces en trop, des tirets mal placés, le parser YAML est impitoyable. `ansible-playbook --syntax-check` est ton meilleur ami.

### Exécution et résultat

**Premier run (avec changements) :**
```bash
ansible-playbook -i inventory.ini harden.yml
```

**Deuxième run (idempotence vérifiée) :**
```bash
ansible-playbook -i inventory.ini harden.yml
```

`changed=0` partout au 2e run → le playbook est idempotent. C'est exactement ce qu'on veut.

### Preuves visuelles

**Infrastructure :**
| Capture | Description |
|---------|-------------|
| ![pfSense interfaces](../screenshots/Module7-Host-Hardening/7.6-pfsense-interfaces-before-mgmt.png) | Interfaces pfSense avant ajout du réseau MGMT |
| ![pfSense ARP error](../screenshots/Module7-Host-Hardening/7.6-pfsense-interface-assignment-arp-error.png) | Erreur ARP lors de l'assignation de l'interface |
| ![VM install DHCP](../screenshots/Module7-Host-Hardening/7.6-mgmt-ansible-install-network-dhcp.png) | Installation de mgmt-ansible — config réseau DHCP |
| ![VM autoconfig failed](../screenshots/Module7-Host-Hardening/7.6-mgmt-ansible-install-autoconfig-failed.png) | Auto-configuration réseau échouée (normal en lab) |
| ![VM LVM partitioning](../screenshots/Module7-Host-Hardening/7.6-mgmt-ansible-install-lvm-partitioning.png) | Partitionnement LVM pendant l'installation |
| ![pfSense WAN fix](../screenshots/Module7-Host-Hardening/7.6-pfsense-dhclient-wan-fix.png) | Fix dhclient WAN sur pfSense |
| ![pfSense MGMT rule](../screenshots/Module7-Host-Hardening/7.6-pfsense-mgmt-firewall-rule.png) | Règle firewall pfSense pour le réseau MGMT |
| ![netplan + ping](../screenshots/Module7-Host-Hardening/7.6-mgmt-ansible-netplan-ping-all.png) | Netplan appliqué + ping réussi vers toutes les machines |

**Distribution des clés :**
| Capture | Description |
|---------|-------------|
| ![SSH to targets](../screenshots/Module7-Host-Hardening/7.6-ssh-mgmt-to-webdmz-lanclient.png) | SSH depuis mgmt vers web-dmz et lan-client |
| ![No identities](../screenshots/Module7-Host-Hardening/7.6-ssh-copy-id-no-identities.png) | Erreur "No identities found" — clé pas encore générée |
| ![keygen + copy-id](../screenshots/Module7-Host-Hardening/7.6-ssh-keygen-copy-id-success.png) | ssh-keygen puis ssh-copy-id — succès |
| ![key display](../screenshots/Module7-Host-Hardening/7.6-ansible-key-display.png) | Clé Ansible affichée |
| ![VBox all VMs](../screenshots/Module7-Host-Hardening/7.6-vbox-manager-all-vms-key-distribution.png) | VirtualBox Manager — toutes les VMs running + distribution |
| ![hostname check](../screenshots/Module7-Host-Hardening/7.6-ssh-hostname-verification.png) | `ssh hostname` — vérification proxy-squid |
| ![all hostnames](../screenshots/Module7-Host-Hardening/7.6-ssh-all-hostnames-confirmed.png) | Tous les hostnames confirmés : badr-VirtualBox, proxy-squid, web-dmz |
| ![ansible ping](../screenshots/Module7-Host-Hardening/7.6-ansible-ping-pong-all-success.png) | `ansible all -m ping` — pong sur les 3 machines |

**Playbook :**
| Capture | Description |
|---------|-------------|

| ![clean view](../screenshots/Module7-Host-Hardening/7.6-harden-yml-clean-nano-view.png) | Version clean du playbook dans nano |
| ![syntax pass](../screenshots/Module7-Host-Hardening/7.6-harden-yml-syntax-check-pass.png) | `ansible-playbook --syntax-check` → OK |

| ![playbook run](../screenshots/Module7-Host-Hardening/7.6-ansible-playbook-run-tasks.png) | Exécution du playbook — tasks en cours |
| ![recap success](../screenshots/Module7-Host-Hardening/7.6-ansible-playbook-recap-success.png) | PLAY RECAP — ok=5, failed=0 sur les 3 machines |
| ![idempotent](../screenshots/Module7-Host-Hardening/7.6-ansible-idempotent-rerun.png) | Re-run idempotent — changed=0 partout |

---

## 7.5 — MFA / Authentification à deux facteurs

### Le principe
Même avec des clés SSH, on rajoute une couche : un code TOTP (Time-based One-Time Password) via Google Authenticator. Pour se connecter, il faut maintenant **la clé SSH + un code qui change toutes les 30 secondes**. Un attaquant qui vole ta clé privée est quand même bloqué.

### Installation sur proxy-squid

```bash
sudo apt install libpam-google-authenticator -y
google-authenticator
```

### Configuration de PAM

Dans `/etc/pam.d/sshd`, ajout de :
```
auth required pam_google_authenticator.so
```

### Configuration de sshd_config

```
AuthenticationMethods publickey,keyboard-interactive
KbdInteractiveAuthentication yes
```

> **Le piège de la typo :** j'ai écrit `KbdInterractiveAuthentication` (deux 'r') et `sshd -t` m'a renvoyé "Bad configuration option". Ce genre de typo te rend dingue parce que tu cherches un problème de logique alors que c'est juste une faute de frappe.

### Résultat final

```bash
ssh badr@10.10.10.20
```

Le MFA marche ! Clé SSH + code TOTP = connexion. Sans le code → refusé.

### Preuves visuelles
| Capture | Description |
|---------|-------------|
| ![QR code](../screenshots/Module7-Host-Hardening/7.8-google-authenticator-qr-code.png) | QR code Google Authenticator sur proxy-squid |
| ![sshd_config MFA](../screenshots/Module7-Host-Hardening/7.8-sshd-config-mfa-full.png) | sshd_config complet avec MFA activé |
| ![typo error](../screenshots/Module7-Host-Hardening/7.8-sshd-bad-config-typo.png) | Erreur de typo : KbdInterractiveAuthentication |
| ![sshd -t pass](../screenshots/Module7-Host-Hardening/7.8-sshd-test-pass-ssh-version.png) | `sshd -t` OK + version OpenSSH_9.6p1 |
| ![MFA success](../screenshots/Module7-Host-Hardening/7.8-mfa-ssh-verification-code-success.png) | SSH avec "Verification code:" → connexion réussie ! |



---

## Résumé de ce qui est en place

| Composant | Machine | Status |
|-----------|---------|--------|
| SSH hardened (clés Ed25519 only) | proxy-squid | ✅ |
| SSH hardened (via Ansible) | toutes | ✅ |
| UFW (deny incoming + rules SSH/Squid) | proxy-squid | ✅ |
| Fail2Ban (jail SSH active) | proxy-squid | ✅ |
| Ansible management VM | mgmt-ansible | ✅ |
| Ansible ping all hosts | 3 machines | ✅ |
| Ansible hardening playbook | 3 machines | ✅ |
| MFA Google Authenticator | proxy-squid | ✅ |

---

## Leçons retenues

1. **YAML c'est de la merde** — un espace de trop et tout pète. Toujours utiliser `--syntax-check`.
2. **Les typos dans sshd_config** — `sshd -t` est ton meilleur ami. Lance-le AVANT de restart.
3. **Les duplications dans fail2ban** — une seule section `[sshd]`, pas deux. Le parser te dit pas clairement que c'est un doublon.
4. **ssh-copy-id sans clé** — faut d'abord `ssh-keygen`, évidemment.
5. **Toujours garder une session de secours** — avant de toucher SSH ou ufw, ouvre un deuxième terminal sur la machine.


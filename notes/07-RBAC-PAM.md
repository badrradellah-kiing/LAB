# 🔐 RBAC & PAM (Contrôle d'accès basé sur les rôles)

## RBAC (Role-Based Access Control)

### L'idée de base
On donne le pouvoir au **rôle** (groupe), pas à l'individu.  
Si quelqu'un change de poste, on le retire du groupe → il perd ses droits automatiquement.

### Comment j'ai configuré ça sudoers

```bash
sudo visudo
```

Ajouter :
```
%domain\ admins ALL=(ALL:ALL) ALL
```

| Élément | Signification |
|---------|---------------|
| `%` | Indique qu'on parle d'un **groupe** (pas un utilisateur) |
| `domain\ admins` | Le groupe AD "Domain Admins" |
| `ALL=(ALL:ALL) ALL` | Droit sudo complet sur toutes les commandes |

### Test complet

![id testadmin + su - testadmin — UID, groupes AD, authentification réussie](../screenshots/RBAC-PAM/Screenshot%20from%202026-06-09%2015-56-56.png)

> **Séquence complète visible :**
> 1. `getent passwd administrator` → `administrator:*:3000:3006::/home/LAB/administrator:/bin/bash` ✅
> 2. `id testadmin` → **uid=3001(testadmin)**, groupes: domain users (3006), **domain admins (3007)**, BUILTIN\administrators (3000) ✅
> 3. `sudo visudo` → ajout de la règle RBAC pour Domain Admins
> 4. `su - testadmin` → première tentative échoue (mauvais mot de passe), seconde réussit !
> 5. Le prompt change en **`testadmin@badr-VirtualBox`** — l'utilisateur AD est connecté sur Linux !
> 6. Alerte `/home/LAB/testadmin` n'existe pas (résolu avec PAM `pam_mkhomedir`)

---

## PAM (Pluggable Authentication Modules)

### L'idée de base

PAM **centralise l'authentification**. Au lieu que chaque service (SSH, `su`, login) vérifie `/etc/passwd` individuellement, ils appellent tous PAM :  
*"Vérifie si ces identifiants sont corrects"*

### Les mots-clés de contrôle PAM

| Mot-clé | Comportement | Analogie |
|---------|-------------|----------|
| `requisite` | Échec → arrêt **immédiat** | 🚫 Vigile impitoyable |
| `required` | Échec → refusé **à la fin**, mais continue les vérifs (anti-énumération) | 🤫 Vigile silencieux |
| `sufficient` | Succès → accepté **immédiatement** (si aucun `required` n'a échoué avant) | ✅ Passe-droit |
| `optional` | Succès ou échec → **ne change rien** au résultat final | 🎁 Bonus |

### Créer le répertoire /home automatiquement

On a utilisé `optional` pour `pam_mkhomedir.so` :
- Si le dossier `/home/LAB/testadmin` ne se crée pas (erreur disque), ça **n'empêche pas** la connexion

### Bloquer `su` avec `pam_wheel.so`

```
# Dans /etc/pam.d/su
auth       required   pam_wheel.so group=sudo
```

> Par défaut, **n'importe qui** peut taper `su - root` et tenter le mot de passe.  
> Avec `pam_wheel.so` : seuls les membres du groupe `sudo` (ou `wheel`) peuvent **même essayer**.  
> C'est une excellente **réduction de surface d'attaque**.

---

## Autres utilisations de PAM

### 1. Restreindre les heures de connexion (`pam_time.so`)
- Les admins ne peuvent se connecter en SSH que du **lundi au vendredi, 08h-18h**
- Module dans la phase `account`
- Si un admin essaie à 3h du matin un dimanche → PAM rejette même si le mot de passe est bon

### 2. MFA avec Google Authenticator (`pam_google_authenticator.so`)
```
auth required pam_google_authenticator.so
```
- PAM demande le mot de passe AD, **puis** le code à 6 chiffres du téléphone
- C'est PAM qui fait le pont entre SSH et l'app Authenticator

### 3. Interdire `su` (`pam_wheel.so`)
```
auth required pam_wheel.so group=sudo
```
- Si l'utilisateur n'appartient pas au groupe `sudo` → PAM rejette immédiatement la demande de `su` sans même afficher l'invite de mot de passe

---

## ⚠️ La "Danger Zone" de PAM

### 1. Lockout total (S'enfermer dehors)
- Une faute de frappe dans `/etc/pam.d/common-auth` (ex: `reqired` au lieu de `required`) → PAM plante → **personne** ne peut plus se connecter, même pas root !

### 2. L'ordre de lecture est vital
- Les lignes sont lues **de haut en bas**
- Un `sufficient` avant un `required` = un utilisateur peut **contourner** la sécurité en validant le test facile

### 3. La Règle d'Or de l'Administrateur

> 🛡️ **Ne ferme JAMAIS ta session root active quand tu modifies un fichier PAM !**  
> 1. Garde un **2ème terminal** ouvert en root  
> 2. Fais ta modification  
> 3. Ouvre un **3ème terminal** pour tester la connexion  
> 4. Si ça casse → le 2ème terminal te sauve la vie !

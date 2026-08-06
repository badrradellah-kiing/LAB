# Module 18 — Detection Engineering (mes notes)

L'idée : mon SIEM passe de "il ramasse des logs" à "il attrape volontairement les attaquants".

Mon setup pour ce module : mon DC01 (adlab.local, le Windows Server que j'ai monté et promu en DC au module 12, IP 10.10.10.15) avec Sysmon + l'agent Wazuh dessus. Et mon SIEM Wazuh sur l'ids-sensor (10.10.30.50).

---

## Sommaire
- [18.1 — Le cycle de détection](#181--le-cycle-de-détection)
- [18.2 — Mapper ma couverture sur MITRE ATT&CK](#182--mapper-ma-couverture-sur-mitre-attck)
- [18.3 — Valider mes détections (Atomic Red Team)](#183--valider-mes-détections-atomic-red-team)
- [18.4 — Threat hunting : chercher ce que les règles ratent](#184--threat-hunting--chercher-ce-que-les-règles-ratent)

---

## 18.1 — Le cycle de détection

C'est de la théorie, pas de manip. Mais le concept est important.

La phrase à retenir : **"une détection se construit, elle ne se trouve pas"**. La différence entre juste regarder des dashboards (monitoring passif) et faire du vrai detection engineering, c'est l'intention : je décide ce que je veux attraper, PUIS je prouve que je l'attrape.

Y'a une boucle en 6 étapes que je répète pour chaque menace :
1. Je choisis une menace (une vraie technique ATT&CK qui me concerne)
2. Je comprends sa télémétrie (elle produit quel event ?)
3. J'écris la détection
4. Je la valide en rejouant l'attaque
5. J'enlève les faux positifs
6. Je documente et je mesure ma couverture

Le truc que j'ai capté : cette boucle je l'ai DÉJÀ faite au module 12 sans le savoir. Le Kerberoasting = menace, l'event 4769/RC4 = télémétrie, ma requête = détection, l'attaque depuis Kali = validation. Donc le reste du module c'est juste mettre un nom propre sur ce que je faisais déjà.

---

## 18.2 — Mapper ma couverture sur MITRE ATT&CK

ATT&CK c'est le catalogue de toutes les techniques d'attaquants. Le principe : je tag chaque détection que j'ai avec son numéro de technique, et d'un coup ma pile de règles en vrac devient une carte où je vois ce que je couvre.

En gros je me pose 3 questions sur mon système :
- qu'est-ce que je détecte ? (mes cases vertes)
- où je suis aveugle ? (mes angles morts)
- où faut faire gaffe ? (les cases où j'ai une règle mais je l'ai jamais testée)

### Ma carte à moi (ce que j'ai vraiment en place)

| Attaque | Tactique | ATT&CK | Ma détection | État |
|---------|----------|--------|--------------|------|
| Port scan | Discovery | T1046 | Suricata | ✅ ok |
| Web/dir scan | Discovery | T1595 | ModSecurity | ✅ ok |
| Directory enum | Discovery | T1087 | LDAP/AD | ✅ ok |
| Exploit web | Initial Access | T1190 | WAF | ✅ ok |
| Valid accounts | Initial Access | T1078 | à moitié | ⚠️ partiel |
| Brute force | Credential Access | T1110 | Wazuh + Fail2Ban | ✅ ok |
| Kerberoasting | Credential Access | T1558.003 | 4769/RC4 | ✅ ok |
| DCSync | Credential Access | T1003.006 | rien | 🔴 angle mort |
| Command/script | Execution | T1059 | Sysmon | ✅ ok |
| Container shell | Execution | T1059 | Falco | ⚠️ partiel |
| Pass-the-Hash | Lateral Movement | T1550.002 | rien | 🔴 angle mort |
| New service | Persistence | T1543.003 | rien | 🔴 angle mort |

### Le truc à ne PAS oublier

**Une détection que j'ai jamais testée, c'est pas une détection, c'est juste un espoir.** Le piège c'est de colorier une case en vert juste parce que j'ai écrit la règle. Tant que j'ai pas vu l'alerte tomber pour de vrai, je sais pas si ça marche.

Une case grise que j'assume honnêtement, ça vaut mieux qu'une case verte remplie par optimisme. En entretien, si je connais mes trous ça inspire plus confiance que si je fais semblant de tout couvrir. Mes 3 cases rouges (DCSync, Pass-the-Hash, New service) = ma todo list de détections à écrire.

---

## 18.3 — Valider mes détections (Atomic Red Team)

C'est LA grosse partie du module et le truc le plus satisfaisant.

Le principe : **une détection non testée = un espoir, pas un contrôle**. Donc je rejoue l'attaque pour de vrai et je regarde si ma détection s'allume. Si je rejoue et que rien n'alerte → bingo j'ai trouvé un angle mort avant que l'attaquant le trouve.

L'outil c'est **Atomic Red Team**. C'est une bibliothèque de "tests atomiques", chaque test rejoue UNE technique ATT&CK, proprement et sans danger. C'est de la "detection-as-code" : je teste mes détections comme si c'était du code.

Le piège que le manuel répète : écrire 30 règles et n'en avoir testé aucune. En entretien la question tombe toujours : "comment tu sais qu'elle marche ?". **3 règles testées valent mieux que 30 copiées.**

### L'install

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
IEX (IWR 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1' -UseBasicParsing)
Install-AtomicRedTeam -getAtomics -Force
```

Premier essai → erreur : `github.com could not be resolved`.

![DNS resolution failed](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2012-55-30.png)

### Le problème DNS qui m'a bloqué

J'ai capté le truc : depuis que ma machine est devenue un DC, elle utilise son propre DNS interne (celui d'adlab.local) qui sait pas résoudre Internet. Le fix c'était d'ajouter un forwarder :

```powershell
Add-DnsServerForwarder -IPAddress 8.8.8.8, 1.1.1.1
Resolve-DnsName github.com   # → 140.82.121.4, ça résout
```

![DNS forwarder fix](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2012-57-03.png)

Après reboot → le module avait disparu de la RAM. J'ai relancé dans une nouvelle session :

![Install-AtomicRedTeam not found after reboot](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-06-19.png)

Deuxième install → ça passe. **Defender alerte immédiatement** "Threats found" (il voit les payloads comme des malwares, ce qu'ils SONT techniquement). En lab isolé → on exclut le dossier :

```powershell
Add-MpPreference -ExclusionPath "C:\AtomicRedTeam"
Import-Module "C:\AtomicRedTeam\invoke-atomicredteam\Invoke-AtomicRedTeam.psd1" -Force
```

![ART install + Defender alert](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-13-02.png)

### Piège : `-Help` n'existe pas

`Invoke-AtomicTest -Help` → "A parameter cannot be found that matches parameter name 'Help'". C'est `Get-Help Invoke-AtomicTest` qu'il faut utiliser.

![Invoke-AtomicTest -Help error](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-14-41.png)

### Toujours regarder ce que fait un test AVANT de le lancer

Je tire jamais une attaque à l'aveugle. Les options pour inspecter :

```powershell
Invoke-AtomicTest T1059.001 -ShowDetailsBrief   # liste les tests dispo
Invoke-AtomicTest T1059.001-1 -ShowDetails       # montre la commande exacte
Invoke-AtomicTest T1110.001-1 -CheckPrereqs      # vérifie les prérequis
Invoke-AtomicTest T1110.001-1 -GetPrereqs        # installe les prérequis manquants
```

![ShowDetailsBrief T1059.001](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-16-53.png)

### CheckPrereqs sur T1059.001

J'ai vérifié les prérequis de T1059.001 (PowerShell). Résultat : T1059.001-1 = **Mimikatz** (prereqs met), T1059.001-2 = BloodHound (prereqs NOT met, SharpHound.ps1 manquant). Ça m'a permis de voir quels tests sont prêts et lesquels pas.

![CheckPrereqs T1059.001](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-23-19.png)
![CheckPrereqs suite](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-43-26.png)

### Inspecter avant de tirer : le cas Mimikatz

J'ai regardé T1059.001-1 avec `-ShowDetails` : c'est Mimikatz qui télécharge `Invoke-Mimikatz` et dump les credentials. Trop bruyant et ça télécharge un vrai malware. Je l'ai zappé. C'est exactement pour ça qu'on regarde avant.

![ShowDetails Mimikatz](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-46-55.png)

### Ma validation : le brute-force AD (T1110.001)

J'ai choisi T1110.001 (brute force AD via SMB) parce que j'ai un vrai DC maintenant. D'abord, lister les tests :

```powershell
Invoke-AtomicTest T1110.001 -ShowDetailsBrief
```

T1110.001-1 = "Brute Force Credentials of single Active Directory domain users via SMB". C'est exactement ce qu'il me faut.

![T1110.001 ShowDetailsBrief + ShowDetails](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-48-54.png)

Le test crée une liste de mots de passe (Password1, 1q2w3e4r, etc.) et essaie chacun contre un compte via le partage `IPC$` du DC. Chaque échec = un event 4625.

```powershell
Invoke-AtomicTest T1110.001-1 -CheckPrereqs   # → "Prerequisites met"
Invoke-AtomicTest T1110.001-1 -GetPrereqs      # → "No Prereqs Defined"
```

![CheckPrereqs + GetPrereqs OK](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-49-22.png)
![GetPrereqs suite](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-49-33.png)

### Le tir

```powershell
Invoke-AtomicTest T1110.001-1 -InputArgs @{ "user" = "Administrator" }
```

### La preuve que ça a marché (le moment que j'attendais)

Sur le sensor, après avoir lancé le test :

```bash
sudo grep -i 4625 /var/ossec/logs/alerts/alerts.log | tail -20
```

Et là mon alerte est remontée :

```
** Alert ...: sysmon, windows
"eventID":"4625", "severityValue":"AUDIT_FAILURE",
"message":"An account failed to log on...",
"targetUserName":"Administrator", "failureReason":"%%2313",
"computer":"DC01.adlab.local"
```

![4625 alerts in Wazuh SIEM](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2013-58-54.png)

Donc : mon test a lancé le brute-force → Wazuh l'a capté → alerte. **Détection validée pour de vrai.** Ma case brute-force passe de "j'espère" à "je sais que ça marche".

Et maintenant si on me demande en entretien "comment tu sais que ta règle marche ?" je réponds : "je l'ai validée avec Atomic Red Team, voilà la preuve dans mon SIEM".

---

## 18.4 — Threat hunting : chercher ce que les règles ratent

C'est l'inverse du 18.3. Les détections attrapent le connu. Le hunting je cherche activement l'inconnu, en partant d'une hypothèse genre : "SI un attaquant était sur mon système, qu'est-ce que je verrais de bizarre ?". Puis je vais fouiller mes logs.

Exemples d'hypothèses :
- des arbres de process bizarres (Word qui lance PowerShell)
- des destinations sortantes rares (une machine qui parle à une IP jamais vue = C2)
- un compte de service qui se log en interactif (un svc- en type 2 = louche)

Les 3 hunts classiques :
- **beaconing** : même source qui parle à même destination à intervalles trop réguliers (un humain c'est irrégulier, un malware qui appelle sa base c'est métronomique)
- **process rare** : un binaire vu sur une seule machine, une seule fois
- **admin hors horaires** : un login admin en dehors des heures de bureau

### Mon hunt (arbres de process)

Hypothèse : "si mon DC était compromis, un process bureautique ou système lancerait un shell". Ma requête sur les logs Sysmon :

```powershell
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Sysmon/Operational'; Id=1} -MaxEvents 100 |
  ForEach-Object {
    $xml=[xml]$_.ToXml()
    [PSCustomObject]@{
      Image =($xml.Event.EventData.Data|?{$_.Name -eq 'Image'})."#text"
      Parent=($xml.Event.EventData.Data|?{$_.Name -eq 'ParentImage'})."#text"
    }
  } | Where-Object { $_.Image -match 'cmd\.exe|powershell\.exe' } |
  Group-Object Parent | Sort-Object Count -Descending | Format-Table Name, Count -AutoSize
```

### Résultat (rien de suspect, et c'est ok)

```
Name                                Count
----                                -----
C:\Windows\System32\svchost.exe         1
C:\Windows\explorer.exe                 1
```

![Threat hunt parent-child results](../screenshots/Module18-Detection-Engineering/Screenshot%20from%202026-08-05%2014-58-26.png)

Les deux parents sont normaux : `explorer.exe` = c'est moi qui ouvre un shell, `svchost.exe` = les services Windows. Donc aucune anomalie, mon DC est clean sur ce vecteur. La plupart des hunts trouvent rien et c'est bon signe.

Ce que je chercherais si c'était compromis (les drapeaux rouges) :
```
winword.exe -> shell     = macro piégée
outlook.exe -> shell     = email piégé
nginx.exe   -> shell     = webshell
un truc inconnu -> shell = à investiguer
```

### Transformer un hunt en règle (le point clé)

Un hunt qui trouve un truc mais qui produit pas de détection est à moitié fini. Donc même si j'ai rien trouvé, j'écris la règle qui m'alerterait automatiquement si ça arrivait. En **Sigma** (portable Wazuh/Splunk/Elastic) :

```yaml
title: Suspicious Shell Spawned by Non-Interactive Parent
status: experimental
logsource:
  category: process_creation
  product: windows
detection:
  selection:
    ParentImage|endswith:
      - '\winword.exe'
      - '\excel.exe'
      - '\outlook.exe'
      - '\nginx.exe'
      - '\w3wp.exe'
    Image|endswith:
      - '\cmd.exe'
      - '\powershell.exe'
  condition: selection
level: high
tags:
  - attack.execution
  - attack.t1059
```

Je la mets dans git avec son tag ATT&CK et un cas de test. J'ai transformé un angle mort potentiel en détection permanente. Hunting et detection engineering c'est la même boucle, juste à des vitesses différentes.

---

## Ce que je retiens

- **Detection engineering = je décide quoi attraper puis je prouve que je l'attrape.** C'est pas "regarder des dashboards".
- La coverage map (tagger chaque règle avec son ID ATT&CK) me donne une vraie carte de ce que je couvre.
- **Une règle jamais testée = un espoir.** La validation c'est ce qui fait la différence.
- Toujours regarder ce que fait un test avant de le lancer (j'ai zappé Mimikatz comme ça).
- **3 règles validées > 30 règles copiées.**
- Le hunting nourrit ma couverture : une trouvaille (ou même juste une hypothèse) → une règle → un trou comblé.
- Piège d'admin : un DC casse la résolution Internet, faut mettre les forwarders DNS.

## Les pièges techniques que je veux plus refaire

- Après un reboot, le module Atomic est perdu de la RAM → je le **REIMPORTE** (`Import-Module`), je réinstalle pas tout. Les trucs sur disque (forwarder DNS, exclusion Defender) eux ils restent.
- `Set-ExecutionPolicy Bypass -Scope Process` = valable juste pour la fenêtre ouverte.
- Defender voit les atomics comme des malwares → exclure `C:\AtomicRedTeam` (lab isolé seulement).
- `tail -f` se termine jamais → Ctrl+C. Pour chercher et que ça se termine : `grep ... | tail`.
- `Invoke-AtomicTest -Help` ça existe pas → `Get-Help Invoke-AtomicTest` à la place.

---

## Où j'en suis

- [x] 18.1 le cycle de détection — compris
- [x] 18.2 la carte de couverture ATT&CK — fait
- [x] 18.3 la validation avec Atomic Red Team — mon brute-force validé, preuve dans le SIEM
- [x] 18.4 le threat hunting — fait, avec une règle Sigma à la clé

Module 18 fini. Mon SIEM est passé de "il ramasse des logs" à "il détecte des attaques, mesuré et validé". Ma todo (backlog) : combler mes 3 angles morts (DCSync, Pass-the-Hash, New service) et exporter ma carte en JSON pour le Navigator officiel.

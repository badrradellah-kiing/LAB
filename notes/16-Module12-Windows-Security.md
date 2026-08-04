# Module 12 — Windows Enterprise Security & Detection

### Mes notes perso

Jusqu'ici mon lab était 100% Linux. Mais en entreprise, la majorité des endpoints sont sous Windows, et c'est là que se passent les vraies attaques AD. Ce module comble ce trou : je monte une VM Windows Server 2025, j'instrumente le logging, j'installe Sysmon, je branche tout vers mon SIEM Wazuh, et je joue une attaque Kerberoasting de bout en bout.

> **Contexte lab :** DC FreeIPA (Linux), SIEM Wazuh sur `ids-sensor` (10.10.30.50), LAN trusted en `10.10.10.0/24`, pfSense en `.1`.

---

## Sommaire
- [12.0 — Setup : monter la VM Windows](#120--setup--monter-la-vm-windows)
- [12.1 — Windows Logging : les events qui comptent](#121--windows-logging--les-events-qui-comptent)
- [12.2 — Sysmon : le microscope du défenseur](#122--sysmon--le-microscope-du-défenseur)
- [12.3 — Envoyer les logs Windows vers le SIEM](#123--envoyer-les-logs-windows-vers-le-siem)
- [12.4 — Détecter les attaques AD (Kerberoasting)](#124--détecter-les-attaques-ad-kerberoasting)
- [12.5 — Le hardening Windows que les entreprises utilisent](#125--le-hardening-windows-que-les-entreprises-utilisent)

---

## 12.0 — Setup : monter la VM Windows

### Le parcours du combattant

Comme mon DC est FreeIPA, il me fallait une VM Windows dédiée. J'ai téléchargé **Windows Server 2025** en édition évaluation (180 jours gratuits) depuis le Microsoft Evaluation Center.

**VM VirtualBox :** `win-endpoint`, 4 Go RAM, 2 CPU, disque VDI dynamique 50 Go, **EFI activé** (obligatoire pour Server 2025).

![VirtualBox System Settings](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-06-22.png)

**Réseau :** adaptateur en **Internal Network**, même nom que ma zone LAN. IP statique `10.10.10.15`.

### Les galères (à retenir)

1. **Boot EFI qui retombe sur le menu** : l'EFI ne lançait pas l'ISO. Fix = aller dans le Boot Manager, choisir `UEFI VBOX CD-ROM`, et **presser une touche immédiatement**.

![Choose an option screen](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-12-21.png)

2. **Install en Server Core par erreur** : VirtualBox avait lancé une **Unattended Installation** automatique (fichier monté sur un contrôleur Floppy) qui choisit l'édition tout seul → SConfig au lieu du bureau.

![SConfig Server Core](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-11-05.png)

3. **Fix = supprimer le contrôleur Floppy** avec son fichier Unattended dans Settings → Storage.

![Storage avec Floppy](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-07-59.png)
![Floppy supprimé](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-09-05.png)

Au final j'ai **supprimé la VM et recréé** proprement. Le point critique : à l'écran de choix d'édition, prendre la ligne **"(Desktop Experience)"** — surtout PAS la ligne nue qui = Server Core.

![Server Manager Desktop](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-37-51.png)

### Config réseau (PowerShell admin)

```powershell
Get-NetAdapter
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.10.10.15 -PrefixLength 24 -DefaultGateway 10.10.10.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.10.10.5
```

Petite galère ici : j'ai d'abord tapé `Set-DnsClientServerAddresse` (avec un 'e' en trop) et `Get-NetIPAdress` (un 'd' en moins). PowerShell est strict sur l'orthographe.

![Erreurs typo DNS/IP](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-45-15.png)
![Fix DNS + Get-NetAdapter](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-45-59.png)

`AddressState` est passé de **Invalid** (le temps que l'IP s'applique) à **Preferred**. Ensuite les pings :

![IP Preferred](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-47-21.png)

```powershell
ping 10.10.10.1    # pfSense -> OK
ping 10.10.10.5    # DC FreeIPA -> OK
```

![Pings OK](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2020-53-19.png)

---

## 12.1 — Windows Logging : les events qui comptent

### Ce que j'ai compris
Windows logge par **channels**. Le journal **Security** n'écrit un event **que si la catégorie d'audit correspondante est activée**. C'est le piège n°1 : *pas d'audit = pas d'event*, donc l'absence d'event ne prouve rien.

### Les Event IDs à connaître par cœur
| ID | Signification |
|----|---------------|
| 4624 / 4625 | Logon réussi / échoué |
| 4672 | Privilèges spéciaux (logon admin/SYSTEM) |
| 4688 | Création de process (avec cmdline si activé) |
| 4768 / 4769 | Kerberos TGT / ticket de service |
| 4720 / 4732 | Compte créé / ajouté à groupe privilégié |
| 7045 | Nouveau service installé (persistence) |

### Logon Types
- **2** = interactif (clavier) · **3** = réseau (Pass-the-Hash) · **5** = service · **10** = RDP · **4** = batch

### Étape A — Activer les audits

```powershell
auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Logoff" /success:enable
auditpol /get /category:"Detailed Tracking","Logon/Logoff"
```

![auditpol set](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2022-28-48.png)
![auditpol get verification](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2022-29-03.png)

**Capturer la cmdline dans le 4688** (éteint par défaut). Ça m'a donné du fil à retordre :
- `reg add ... REG_WORD` → "Invalid key name" (la sous-clé `Audit` n'existait pas + j'avais écrit `REG_WORD` au lieu de `REG_DWORD`)
- `New-ItemProperty` → "IDynamicPropertyCmdletProvider not implemented"
- `HLKM:` drive → "Cannot find drive. A drive with the name 'HLKM' does not exist"

![reg add errors](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2022-43-00.png)
![reg add + REG_DWORD errors](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2022-44-07.png)
![New-ItemProperty + HLKM errors](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2022-48-23.png)
![HLKM drive not found](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2022-49-00.png)

**Ce qui a marché** : passer par .NET directement :
```powershell
[Microsoft.Win32.Registry]::SetValue(
  "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit",
  "ProcessCreationIncludeCmdLine_Enabled", 1,
  [Microsoft.Win32.RegistryValueKind]::DWord)
```

⚠️ En .NET, la ruche s'écrit **`HKEY_LOCAL_MACHINE`** en toutes lettres (pas `HKLM`).

![.NET SetValue qui marche](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2022-54-03.png)

### Étape B — Générer de la télémétrie

```powershell
runas /user:LAB\inexistant cmd    # → 4625 (logon échoué)
whoami                            # → 4688
ipconfig /all                     # → 4688
runas /user:Administrator cmd     # → 4624 (logon réussi)
```

![runas + ipconfig + telemetry](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2022-59-51.png)
![runas inexistant + whoami](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-00-05.png)

### Étape C — Lire les logs

```powershell
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625} -MaxEvents 5 |
  Format-List TimeCreated, Message
```

![4625 event detail](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-01-51.png)

Le 4625 avait **DEUX** blocs "Account" : **Subject** (qui a lancé la tentative = Administrator) et **Account For Which Logon Failed** (la cible = `inexistant`, SID `S-1-0-0`). Logon Type 2 (runas = interactif).

Le 4688 capturait la cmdline (`notepad.exe`, `ipconfig /all`) → ma clé registre fonctionnait.

![4688 avec cmdline](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-10-05.png)

Le tableau SIEM-like que j'ai construit :

```powershell
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624,4625} -MaxEvents 20 |
  ForEach-Object {
    $xml = [xml]$_.ToXml()
    [PSCustomObject]@{
      Time=$_.TimeCreated; EventID=$_.Id
      Result= if($_.Id -eq 4624){'SUCCESS'}else{'FAILED'}
      User=($xml.Event.EventData.Data|?{$_.Name -eq 'TargetUserName'})."#text"
      LogonType=($xml.Event.EventData.Data|?{$_.Name -eq 'LogonType'})."#text"
      SourceIP=($xml.Event.EventData.Data|?{$_.Name -eq 'IpAddress'})."#text"
    }
  } | Format-Table -AutoSize
```

![Tableau 4624/4625](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-11-32.png)

Une masse de `SYSTEM / Type 5` = **bruit de fond normal** (services). Ma seule ligne intéressante : `Administrator / Type 2 / 127.0.0.1`. **Leçon : baseline (le bruit) vs anomalie (ce qui dépasse).**

---

## 12.2 — Sysmon : le microscope du défenseur

### Pourquoi
Les logs natifs sont grossiers (le 4688 dit "notepad a démarré" mais pas QUI l'a lancé). **Sysmon** installe un **driver kernel** qui capture la cmdline, le **process parent**, et le **hash SHA-256**. C'est l'équivalent Windows de auditd + Falco.

### Installation

```powershell
mkdir C:\Tools; cd C:\Tools
Invoke-WebRequest "https://download.sysinternals.com/files/Sysmon.zip" -OutFile Sysmon.zip
Expand-Archive Sysmon.zip C:\Tools\Sysmon -Force
Invoke-WebRequest "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml" -OutFile C:\Tools\Sysmon\sysmonconfig.xml
```

Note : l'accès Internet était intermittent (parfois `TcpTestSucceeded: False`) mais les téléchargements sont passés.

![Test-NetConnection + download](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-19-23.png)
![Sysmon files downloaded](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-20-02.png)
![Sysmon directory listing](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-22-18.png)

```powershell
cd C:\Tools\Sysmon
.\Sysmon64.exe -accepteula -i sysmonconfig.xml
Get-Service Sysmon64  # → Running
```

![Sysmon installed + Running](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-22-58.png)

"Configuration file validated" + "SysmonDrv installed" → le driver kernel est en place.

### Le test parent-enfant

```powershell
cmd.exe /c "notepad.exe"

Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Sysmon/Operational'; Id=1} -MaxEvents 5 |
  ForEach-Object {
    $xml=[xml]$_.ToXml()
    [PSCustomObject]@{
      Image=($xml.Event.EventData.Data|?{$_.Name -eq 'Image'})."#text"
      Parent=($xml.Event.EventData.Data|?{$_.Name -eq 'ParentImage'})."#text"
      Cmdline=($xml.Event.EventData.Data|?{$_.Name -eq 'CommandLine'})."#text"
      Hash=($xml.Event.EventData.Data|?{$_.Name -eq 'Hashes'})."#text"
    }
  } | Format-List
```

![Sysmon parent-child notepad](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-25-08.png)
![Sysmon full chain + hashes](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-03%2023-25-17.png)

### La lignée reconstruite
```
WindowsTerminal.exe → powershell.exe → cmd.exe → notepad.exe
```

Chaque enfant connaît son **Parent**. C'est LA chose que le 4688 ne donnait jamais. Pourquoi ça compte : une attaque réelle = `winword.exe → powershell.exe`, une anomalie flagrante (Word ne lance jamais PowerShell).

Les **hashs** : SHA-256 (à coller dans VirusTotal) et IMPHASH (identifie un malware même recompilé/renommé).

---

## 12.3 — Envoyer les logs Windows vers le SIEM

### Vérif connectivité

```powershell
Test-NetConnection 10.10.30.50 -Port 1514   # True
Test-NetConnection 10.10.30.50 -Port 1515   # True (enrollment)
```

Ma VM est en LAN (10.10.10.x), le manager en DMZ (10.10.30.x) → le trafic traverse pfSense. Les deux ports passaient.

![Test-NetConnection 1514/1515](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2000-33-33.png)

### Install de l'agent

```powershell
Invoke-WebRequest "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.0-1.msi" -OutFile C:\Tools\wazuh-agent.msi
msiexec.exe /i C:\Tools\wazuh-agent.msi /q `
  WAZUH_MANAGER="10.10.30.50" `
  WAZUH_AGENT_NAME="win-endpoint" `
  WAZUH_REGISTRATION_SERVER="10.10.30.50"
```

![Wazuh agent install](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2000-32-27.png)

### Enrollment + démarrage

```powershell
& "C:\Program Files (x86)\ossec-agent\agent-auth.exe" -m 10.10.30.50
# → "Valid key received"
Start-Service WazuhSvc
Get-Service WazuhSvc  # → Running
```

![agent-auth + WazuhSvc Running](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2000-36-39.png)
![runas pirate test + whoami](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2000-37-16.png)

### Vérif côté SIEM (ids-sensor)

```bash
sudo /var/ossec/bin/agent_control -l
```

![agent_control -l (WIN Active)](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2000-39-23.png)

L'agent Windows `WIN-530QD92L1LT` apparaît **Active** en ID 005, à côté de mes agents Linux existants.

Puis j'ai généré un `runas /user:LAB\pirate cmd` (mauvais mdp) côté Windows → l'event est apparu dans les alertes du sensor :

![4625 parsé dans Wazuh SIEM](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2000-40-44.png)

```
win.eventdata.targetUserName: pirate
win.eventdata.logonType: 2
win.eventdata.failureReason: %%2313
win.eventdata.workstationName: WIN-530QD92L1LT
```

**Le même 4625 que je lisais à la main au 12.1, maintenant parsé et centralisé automatiquement.** Voilà l'intérêt de la centralisation.

---

## 12.4 — Détecter les attaques AD (Kerberoasting)

### Promotion en DC

Mon DC étant FreeIPA, j'ai promu ma VM Windows en **DC Active Directory dédié** (domaine `adlab.local`) pour pouvoir jouer les attaques AD natives.

```powershell
Rename-Computer -NewName "DC01" -Restart
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName "adlab.local" -DomainNetbiosName "ADLAB" -InstallDns -Force
```

![Install-WindowsFeature + Install-ADDSForest](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2001-09-08.png)
![ADDSForest installing + DNS warnings](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2001-10-22.png)

Les warnings jaunes "DNS delegation cannot be created" sont **normaux** en lab isolé. Vérif avec `Get-ADDomain` → DC01 tient tous les rôles FSMO, niveau `Windows2025Domain`.

![Get-ADDomain result](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2001-13-54.png)

### Préparer la cible Kerberoastable

```powershell
New-ADUser -Name "svc-sql" -SamAccountName "svc-sql" -UserPrincipalName "svc-sql@adlab.local" `
  -AccountPassword (ConvertTo-SecureString "Summer2024" -AsPlainText -Force) `
  -Enabled $true -PasswordNeverExpires $true
setspn -A MSSQLSvc/DC01.adlab.local:1433 svc-sql
setspn -L svc-sql   # → MSSQLSvc/DC01.adlab.local:1433
```

![New-ADUser + setspn](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2003-52-39.png)

### L'attaque depuis Kali

Piège Kali : `GetUserSPNs.py` → command not found, `impacket-GetUserSPNs.py` → command not found non plus. Sur Kali récent c'est **`impacket-GetUserSPNs`** (sans `.py`).

![GetUserSPNs.py not found](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2003-55-34.png)
![impacket-GetUserSPNs.py not found](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2003-56-13.png)
![Various naming attempts](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2003-56-48.png)
![impacket binaries listing](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2003-57-45.png)

```bash
impacket-GetUserSPNs adlab.local/Administrator -dc-ip 10.10.10.15 -request
```

Impacket a **trouvé la cible** `svc-sql` mais au moment de demander le ticket RC4 :
```
KDC_ERR_ETYPE_NOSUPP (KDC has no support for encryption type)
```

![Kerberoasting KDC_ERR_ETYPE_NOSUPP](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2003-59-24.png)

### La leçon (meilleure que la démo "réussie")

**Windows Server 2025 désactive RC4 par défaut** — c'est un durcissement moderne. Mon domaine était donc **déjà protégé** contre la version RC4 du Kerberoasting. C'est un vrai enseignement : parfois la défense moderne casse déjà l'attaque classique.

### Détection sur DC01

```powershell
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4769} -MaxEvents 20 |
  ForEach-Object {
    $xml=[xml]$_.ToXml()
    [PSCustomObject]@{
      Service=($xml.Event.EventData.Data|?{$_.Name -eq 'ServiceName'})."#text"
      User=($xml.Event.EventData.Data|?{$_.Name -eq 'TargetUserName'})."#text"
      Enc=($xml.Event.EventData.Data|?{$_.Name -eq 'TicketEncryptionType'})."#text"
    }
  } | Where-Object Service -eq 'svc-sql' | Format-Table -AutoSize
```

![4769 + 4672 queries on DC01](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2006-17-14.png)
![4672 privileged logon detection](../screenshots/Module12-Windows-Security/Screenshot%20from%202026-08-04%2006-19-43.png)

---

## 12.5 — Le hardening Windows que les entreprises utilisent

Détecter c'est la moitié. L'autre moitié = **réduire la surface d'attaque**.

| Contrôle | Rôle | Attaque cassée |
|----------|------|----------------|
| **LAPS** | Randomise le mdp admin local de chaque machine | Lateral movement via mdp partagé |
| **Baselines GPO** | Désactiver SMBv1, forcer SMB signing, restreindre NTLM | Relais NTLM, exploits legacy |
| **Credential Guard** | Protège les credentials en mémoire | Mimikatz / dump LSASS |
| **AppLocker / WDAC** | Allow-listing : n'exécute que l'autorisé | Exécution de binaires non approuvés |
| **Tiered admin** | Un Domain Admin ne se logge JAMAIS sur une workstation | Chemins BloodHound (DA sur poste) |

Le **piège classique (BloodHound)** : un Domain Admin se connecte sur une workstation normale → ses credentials restent en mémoire → un attaquant qui compromet ce poste les récupère → tout le domaine. **Fix = le tiering** (décision d'architecture, pas un outil).

---

## Récap ATT&CK

| Attaque | ATT&CK | Télémétrie | Détection |
|---------|--------|------------|-----------|
| Kerberoasting | T1558.003 | 4769 / RC4 | 4769 + enc 0x17 → Sigma |
| DCSync | T1003.006 | 4662 / DS-Replication GUID | Réplication hors DC légitime |
| Pass-the-Hash | T1550.002 | 4624 Type 3 + NTLM | Logon réseau NTLM source anormale |
| Process suspect | T1059 | Sysmon ID 1 (parent+hash) | Chaîne parent→enfant anormale |
| Nouveau service | T1543.003 | 7045 | Service installé hors changement |
| Compte créé | T1136 | 4720 / 4732 | Ajout groupe privilégié |

---

## Ce que je retiens

1. **Piège n°1 du logging Windows** : pas d'audit activé = pas d'event. Toujours vérifier `auditpol` avant de conclure qu'"il ne s'est rien passé".
2. **Logon Types** : un 4624 ne veut rien dire sans son type (2 interactif, 3 réseau/PtH, 10 RDP). C'est le type qui fait le signal.
3. **Sysmon = la lignée de process** : la relation parent→enfant c'est le socle de la détection Windows. Le log natif ne la donne pas.
4. **La règle d'or de la centralisation** : une source n'est "branchée" que quand j'ai vu un event traverser TOUTE la chaîne jusqu'au SIEM.
5. **Agent ≠ navigateur** : l'agent Wazuh parle en direct (1514/1515), il ne passe pas par le proxy. Bien distinguer trafic agent et trafic web.
6. **Windows 2025 est durci par défaut** (RC4 off) — un vrai enseignement.
7. **Détecter = savoir quel Event ID chercher** : Kerberoast→4769, logon admin→4672, brute-force→pic de 4625, service suspect→7045.

## Pièges techniques croisés
- Install Windows : désactiver l'**Unattended Installation** de VirtualBox, sinon = Server Core.
- Registre en .NET : ruche = **`HKEY_LOCAL_MACHINE`** en toutes lettres, type **`REG_DWORD`**.
- Impacket sur Kali récent : **`impacket-GetUserSPNs`** (sans `.py`).
- Fautes de frappe fréquentes : `Set-DnsClientServerAddress` (pas ...Addresse), `Get-NetIPAddress` (2 "d"). → **utiliser Tab** et le presse-papier partagé.

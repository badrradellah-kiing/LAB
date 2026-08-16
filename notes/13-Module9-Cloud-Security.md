# Module 9 — Sécurité Cloud (Infrastructure AWS)

### Ma doc perso du lab

Ici l'idée c'est de prendre tout ce que j'ai appris en on-premises (pare-feu, segmentation, DMZ, proxy, SIEM…) et de le transposer sur le Cloud avec AWS. Je voulais voir comment les mêmes principes s'appliquent, mais avec des services managés. Spoiler : c'est pareil en concept, mais la syntaxe change complètement.

**Le contexte :**
- Compte AWS Academy avec $100 de crédits
- Tout fait en CLI (`aws cli`) depuis mon terminal local, pas depuis la console web
- Région : `eu-west-3` (Paris)
- VPC dédié : `10.20.0.0/16`

---

## Sommaire
- [9.1 — Audit & Budget (pas se ruiner dès le départ)](#91--audit--budget-pas-se-ruiner-dès-le-départ)
- [9.2 — Architecture réseau (VPC, Subnets, IGW)](#92--architecture-réseau-vpc-subnets-igw)
- [9.3 — Filtrage et Security Groups](#93--filtrage-et-security-groups)
- [9.4 — Bastion, ALB et exposition contrôlée](#94--bastion-alb-et-exposition-contrôlée)
- [9.5 — IAM et moindre privilège](#95--iam-et-moindre-privilège)
- [9.6 — Surveillance (CloudTrail & CloudWatch)](#96--surveillance-cloudtrail--cloudwatch)
- [9.7 — Teardown (tout casser proprement)](#97--teardown-tout-casser-proprement)

---

## 9.1 — Audit & Budget (pas se ruiner dès le départ)

### Le principe
Avant de toucher à quoi que ce soit, j'ai mis en place un budget AWS pour pas me retrouver avec une facture surprise. Avec le Cloud, un `t2.xlarge` oublié pendant une semaine et c'est 50$ qui partent.

### Ce que j'ai fait
J'ai créé un budget de sécurité via CloudShell :
```bash
aws budgets create-budget \
  --account-id 434748568913 \
  --budget '{
    "BudgetName": "lab-securities",
    "BudgetLimit": {"Amount": "20", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "TON_EMAIL@example.com"}]
  }]'
```

![Budget CloudShell](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-29%2014-39-12.png)

Ensuite j'ai configuré `aws configure` sur ma machine locale avec mes access keys pour pouvoir tout piloter depuis mon terminal au lieu de la console web.

---

## 9.2 — Architecture réseau (VPC, Subnets, IGW)

### Le principe
C'est exactement comme mon lab on-premises : je crée un réseau isolé avec une DMZ (subnet public) et un LAN de confiance (subnet privé). La différence c'est qu'ici c'est un VPC au lieu de VLANs sur pfSense.

### Création du VPC
```bash
aws ec2 create-vpc --cidr-block 10.20.0.0/16
```

Le VPC me retourne un `vpc-id` que j'utilise pour tout le reste. C'est le périmètre logique de mon infra, comme mon pfSense qui encapsule tout.

![VPC Creation](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-29%2015-51-28.png)

### Création des sous-réseaux

**Subnet public (DMZ)** — `10.20.1.0/24` :
C'est là que je mets les trucs exposés à internet (bastion, load balancer). Exactement comme ma DMZ avec Nginx dans le lab.

**Subnet privé (LAN)** — `10.20.2.0/24` :
Aucune route vers internet. Les serveurs d'application vivent ici, invisibles de l'extérieur. Comme mon réseau interne avec le proxy et l'AD.

```bash
aws ec2 create-subnet --vpc-id vpc-09ee7745f51666da6 --cidr-block 10.20.1.0/24 --availability-zone eu-west-3a
aws ec2 create-subnet --vpc-id vpc-09ee7745f51666da6 --cidr-block 10.20.2.0/24 --availability-zone eu-west-3b
```

![Subnets Creation](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-29%2015-55-57.png)

### Internet Gateway et table de routage

Pour que le subnet public puisse atteindre internet, il faut une Internet Gateway (l'équivalent de l'interface WAN de pfSense) :

```bash
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --vpc-id vpc-09ee7745f51666da6 --internet-gateway-id igw-02d7502148c0b6c49
```

Puis une table de routage avec une route par défaut `0.0.0.0/0` qui pointe vers l'IGW, et on l'associe au subnet public :

![IGW + Route Table](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-29%2015-57-54.png)
![Route + Associate](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-29%2016-03-19.png)

Le subnet privé, lui, n'a PAS cette route. Donc aucun accès direct depuis/vers internet. Si les machines privées ont besoin de télécharger des mises à jour, ça passe par un NAT Gateway (même principe que le NAT sur pfSense).

---

## 9.3 — Filtrage et Security Groups

### Le principe
Les Security Groups sur AWS, c'est comme les règles de pare-feu sur pfSense, mais en **stateful** (pas besoin de gérer le retour). Si j'autorise le trafic entrant sur le port 443, la réponse sort automatiquement.

### Ce que j'ai configuré

J'ai créé un Security Group `lab-web-sg` avec deux règles :
- **Port 443 (HTTPS)** ouvert à tout le monde (`0.0.0.0/0`) — c'est pour le trafic web via l'ALB
- **Port 22 (SSH)** restreint à une seule IP — pas question d'exposer SSH au monde entier

```bash
aws ec2 authorize-security-group-ingress --group-id sg-0aa5e6e994ffd50dc --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-0aa5e6e994ffd50dc --protocol tcp --port 22 --cidr 46.193.69.4/32
```

![Security Groups Rules](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-29%2016-33-47.png)

C'est exactement le même raisonnement que mes règles pfSense : on bloque tout par défaut et on ouvre que ce qui est nécessaire.

---

## 9.4 — Bastion, ALB et exposition contrôlée

### Le Bastion Host

Le bastion c'est un serveur minimaliste dans le subnet public qui sert de point d'entrée unique pour SSH. Même logique que mon VPN WireGuard : on ne se connecte jamais directement aux machines internes.

J'ai d'abord eu une erreur parce que `t2.micro` n'est plus éligible au Free Tier (ils ont changé pour `t3.micro`). Petit piège.

```bash
aws ec2 create-key-pair --key-name lab-bastion-key --query 'KeyMaterial' --output text > lab-bastion-key.pem
chmod 400 lab-bastion-key.pem

aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.micro \
  --subnet-id subnet-02bfa6f6c503a01f9 \
  --security-group-ids sg-0aa5e6e994ffd50dc \
  --key-name lab-bastion-key \
  --associate-public-ip-address \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bastion-lab}]'
```

![Bastion Launch](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-30%2012-02-42.png)
![Bastion Details](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-30%2012-02-48.png)

Le bastion obtient une IP privée `10.20.1.46` dans le subnet public. C'est le seul point avec SSH ouvert.

### Application Load Balancer (ALB) + WAF

Pour le trafic web, j'ai déployé un ALB. C'est l'équivalent cloud d'un reverse proxy Nginx, sauf que c'est managé par AWS.

D'abord le Target Group (le backend qui va recevoir le trafic) :
![Target Group](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-30%2015-54-38.png)

Puis le Load Balancer lui-même, attaché aux deux subnets pour la haute disponibilité :
![ALB Creation](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-30%2015-23-09.png)

Et le Listener qui route le trafic HTTP port 80 vers le Target Group :
![Listener](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-30%2015-26-20.png)

Devant l'ALB, y'a le AWS WAF qui bloque les injections SQL, le XSS, et le rate-limiting contre les scans (Nikto, Gobuster). C'est le même concept que mon module IDS/WAF mais en version managée.

---

## 9.5 — IAM et moindre privilège

### Le principe
IAM c'est LE truc critique en Cloud. Une fuite de clés IAM = quelqu'un a les clés de ton datacenter virtuel. C'est comme si quelqu'un volait le mot de passe root de pfSense, mais en pire parce qu'il peut aussi modifier la facturation.

### Ce que j'ai fait
J'ai créé un utilisateur `lab-admin` avec uniquement la politique `AmazonEC2FullAccess`. Il peut gérer les serveurs et le réseau, mais rien d'autre.

Pour vérifier que le confinement marche, j'ai fait un pen-test maison :

```bash
aws ec2 describe-vpcs --profile lab-admin   
aws iam list-users --profile lab-admin      
```

![IAM describe-vpcs OK](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-30%2016-42-22.png)
![IAM list-users DENIED](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-30%2016-43-17.png)

Le `describe-vpcs` passe parce que c'est du EC2. Mais `iam list-users` est immédiatement rejeté : `AccessDenied`. Si un attaquant vole ces credentials, il ne peut ni lister les autres utilisateurs, ni toucher à la facturation. Le confinement fonctionne.

---

## 9.6 — Surveillance (CloudTrail & CloudWatch)

### CloudTrail — journaliser chaque appel API

CloudTrail c'est le SIEM d'AWS. Il enregistre TOUT ce qui se passe sur le compte : création d'instances, modification de règles, connexions… Les logs sont envoyés dans un bucket S3 dédié.

J'ai d'abord créé le bucket S3 et sa politique d'accès pour autoriser CloudTrail à y écrire :

![S3 Policy](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-29%2015-45-19.png)

Puis j'ai créé le trail et activé le logging :
```bash
aws s3api create-bucket --bucket log-cloud-trail-badr --region us-east-1
aws s3api put-bucket-policy --bucket log-cloud-trail-badr --policy file://policy.json
aws cloudtrail create-trail --name lab-trail --s3-bucket-name log-cloud-trail-badr --is-multi-region-trail
aws cloudtrail start-logging --name lab-trail
```

![CloudTrail Setup](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-29%2015-46-20.png)

### CloudWatch — alerter sur les comportements suspects

J'ai configuré une alarme CloudWatch qui se déclenche si le compte root est utilisé. Parce que normalement, on travaille jamais avec le root en production.

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name root-login \
  --namespace "CloudTrailMetrics" \
  --metric-name RootAccountUsage \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold
```

![CloudWatch Alarm](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-31%2000-47-57.png)

Si `RootAccountUsage >= 1` sur une fenêtre de 5 minutes → alerte. C'est comme ma règle Wazuh custom du module 8, mais pour le plan de contrôle AWS.

---

## 9.7 — Teardown (tout casser proprement)

### Le principe
Le Cloud c'est facturé à l'usage. Un truc oublié qui tourne = de l'argent qui part. Donc à la fin du lab, je détruis TOUT dans le bon ordre.

### L'ordre de destruction

C'est important de respecter l'ordre sinon AWS refuse de supprimer certaines ressources qui ont des dépendances :

1. **Terminer les instances EC2** (bastion)
2. **Supprimer le NAT Gateway** (si créé)
3. **Libérer l'Elastic IP**
4. **Supprimer l'ALB et le Target Group**
5. **Supprimer les Security Groups**
6. **Détacher et supprimer l'Internet Gateway**
7. **Supprimer les subnets et le VPC**
8. **Désactiver CloudTrail et vider le bucket S3**
9. **Supprimer les alarmes CloudWatch**

```bash
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=bastion-lab" \
  --query "Reservations[*].Instances[*].InstanceId" --output text)
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
```

![Teardown](../screenshots/Module9-Cloud-Security/Screenshot%20from%202026-07-30%2012-04-18.png)

La substitution de commande `$(...)` c'est pratique pour automatiser la récupération des IDs sans les copier-coller à la main. À la fin, surface de facturation = zéro.

---

### Ce que je retiens de ce module

Le Cloud c'est les mêmes concepts qu'en on-premises, mais avec une couche d'abstraction en plus. Un VPC = un réseau, un Security Group = un pare-feu, un ALB = un reverse proxy, CloudTrail = un SIEM. La grosse différence c'est que la sécurité du plan de contrôle (IAM) est aussi importante que la sécurité réseau. Et que si t'oublies de nettoyer, ça te coûte de l'argent.

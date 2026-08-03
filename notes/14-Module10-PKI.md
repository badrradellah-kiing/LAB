# Module 10 — PKI & Certificate Authority

### Mes notes perso

Ce module c'est de la crypto appliquée. L'objectif : construire ma propre infrastructure à clés publiques pour que les machines du réseau ne fassent plus confiance à n'importe qui. Concrètement, je remplace la confiance implicite ("je te fais confiance parce que t'es sur le même réseau") par une validation cryptographique stricte ("je te fais confiance parce que tu as un certificat signé par mon CA").

---

## Sommaire
- [10.1 — Construction de l'autorité de certification](#101--construction-de-lautorité-de-certification)
- [10.2 — Certificat serveur et chaîne de confiance](#102--certificat-serveur-et-chaîne-de-confiance)
- [10.3 — Authentification mutuelle (mTLS)](#103--authentification-mutuelle-mtls)
- [10.4 — Révocation (CRL)](#104--révocation-crl)

---

## 10.1 — Construction de l'autorité de certification

### Le principe
J'ai monté une PKI à deux niveaux : une Root CA (la racine qui signe tout) et une Intermediate CA (l'intermédiaire qui fait le boulot quotidien). Pourquoi ? Parce qu'en prod la Root CA doit rester **hors ligne**. Si l'intermédiaire est compromis, on le révoque sans avoir à reconstruire toute la chaîne de confiance.

### Génération de la Root CA

```bash
openssl genrsa -aes256 -out root.key 4096
openssl req -x509 -new -key root.key -days 7300 -sha256 -out root.crt -subj "/CN=Lab Root CA"
```

Le `-aes256` chiffre la clé privée avec un mot de passe. Donc même si quelqu'un la vole, il lui faut la passphrase pour l'utiliser. Les 7300 jours c'est ~20 ans de validité pour la racine, ce qui est standard.

![Root CA Generation](../screenshots/Module10-PKI/Screenshot%20from%202026-07-31%2023-09-27.png)

### Génération de l'intermédiaire

```bash
openssl genrsa -out intermediate.key 4096
openssl req -new -key intermediate.key -out intermediate.csr -subj "/CN=Lab Intermediate CA"
openssl x509 -req -in intermediate.csr -CA root.crt -CAkey root.key -CAcreateserial -days 3650 -sha256 \
  -extfile <(printf "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign") \
  -out intermediate.crt
```

Le `pathlen:0` c'est important : ça empêche l'intermédiaire de créer d'autres CA en dessous de lui. Il peut signer des certificats "leaf" (serveur/client) mais c'est tout.

![Intermediate CA + Chain](../screenshots/Module10-PKI/Screenshot%20from%202026-07-31%2023-11-08.png)

---

## 10.2 — Certificat serveur et chaîne de confiance

### Le principe
Maintenant que j'ai ma chaîne CA, je peux émettre un certificat pour mon serveur web (`web.lab.local`). C'est ce certificat qui sera présenté aux clients lors du handshake TLS.

### Génération du cert serveur

```bash
openssl genrsa -out web.key 2048
openssl req -new -key web.key -out web.csr -subj "/CN=web.lab.local"
openssl x509 -req -in web.csr -CA intermediate.crt -CAkey intermediate.key \
  -CAcreateserial -days 825 -sha256 \
  -extfile <(printf "subjectAltName=DNS:web.lab.local\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth") \
  -out web.crt
```

J'ai limité à 825 jours parce que c'est la limite imposée par Apple/Google pour les certificats serveur depuis 2020. Le `subjectAltName` est obligatoire, le `CN` seul n'est plus suffisant pour les navigateurs modernes.

Ensuite j'ai construit la fullchain pour Nginx :
```bash
cat web.crt intermediate.crt > web-fullchain.crt
```

![Server Cert + Fullchain](../screenshots/Module10-PKI/Screenshot%20from%202026-07-31%2023-19-41.png)

Pour vérifier que toute la chaîne est valide :
```bash
openssl verify -CAfile root.crt -untrusted intermediate.crt web.crt
# → web.crt: OK
```

---

## 10.3 — Authentification mutuelle (mTLS)

### Le principe
En TLS classique, seul le serveur prouve son identité. Avec mTLS (mutual TLS), le **client aussi** doit présenter un certificat valide. C'est du zero-trust pur : si t'as pas de cert signé par mon CA, tu ne passes pas.

### Génération du certificat client

```bash
openssl genrsa -out client.key 2048
openssl req -new -key client.key -out client.csr -subj "/CN=svc-client"
openssl x509 -req -in client.csr -CA intermediate.crt -CAkey intermediate.key \
  -CAcreateserial -days 825 -sha256 \
  -extfile <(printf "extendedKeyUsage=clientAuth") -out client.crt
```

Le `extendedKeyUsage=clientAuth` c'est ce qui distingue un cert client d'un cert serveur. Si quelqu'un essaye d'utiliser un cert serveur comme client, ça sera rejeté.

![Client Cert](../screenshots/Module10-PKI/Screenshot%20from%202026-07-31%2023-21-08.png)

### Test avec curl

```bash
# Sans certificat client → rejeté
curl https://web.lab.local --cacert root.crt
# → 400 No required SSL certificate was sent

# Avec certificat client → ça passe
curl https://web.lab.local --cacert root.crt --cert client.crt --key client.key
# → 200 OK
```

C'est exactement comme le badge d'accès dans un bâtiment : le gardien vérifie que tu as le bon badge (cert client) avant de te laisser entrer, en plus de s'identifier lui-même (cert serveur).

---

## 10.4 — Révocation (CRL)

### Le principe
Si un certificat est compromis, il faut pouvoir le révoquer. C'est la CRL (Certificate Revocation List) : une liste noire des certificats invalidés avant leur date d'expiration.

### Tentative de révocation

```bash
openssl ca -revoke compromised.crt -keyfile intermediate.key -cert intermediate.crt
openssl ca -gencrl -keyfile intermediate.key -cert intermediate.crt -out lab.crl
```

J'ai eu une erreur `Problem with index file: ./demoCA/index.txt (could not load/parse file)` parce que OpenSSL attend une structure de dossiers type `demoCA/` pour gérer la base de données des certificats. C'est un piège classique quand on fait de la PKI à la main sans passer par `easy-rsa` ou `cfssl`.

![CRL Error](../screenshots/Module10-PKI/Screenshot%20from%202026-07-31%2023-27-36.png)

Pour fix ça, il faudrait initialiser la structure avec `mkdir -p demoCA && touch demoCA/index.txt && echo 01 > demoCA/serial`. Mais l'essentiel est compris : la révocation fait partie du cycle de vie d'un certificat.

---

### Ce que je retiens

La PKI c'est la base de la confiance dans un réseau. Chaque couche du lab s'appuie dessus : Nginx utilise les certs pour HTTPS, le mTLS protège les API internes, et la CRL permet de réagir si un cert fuite. C'est pas glamour, mais sans ça le chiffrement ne sert à rien parce qu'on ne sait pas à QUI on parle.

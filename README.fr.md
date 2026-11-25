*[English](README.md) | Français*

# Spotify natif sur Sailfish OS (Jolla Phone)

Projet personnel, partagé pour essai. Il rassemble tout ce qui permet d'écouter Spotify en natif sur le Jolla Phone, sans l'application Android, et de parcourir sa bibliothèque sur l'écran de la voiture grâce à [Sailplay](https://github.com/0312birdzhang/harbour-sailplay).

Le montage repose sur deux pièces :

- **Spotify Soloist**, le lecteur officiel de Spotify pour Linux, joue la musique sur le téléphone et apparaît comme un appareil Spotify Connect.
- **Hutspot**, une application Sailfish libre, sert de télécommande. Sa version d'origine ne fonctionnait plus avec l'API de Spotify de 2026 : ce dépôt contient un fork adapté.

Librespot n'est pas utilisé : Spotify refuse depuis 2025-2026 les clés de déchiffrement aux comptes récents (erreur `audio key 0 1`), et aucun contournement n'existe.

## Avant d'essayer

- Il faut un compte **Spotify Premium** (Soloist et l'API de lecture l'exigent).
- **Soloist n'est pas fourni.** C'est un logiciel propriétaire, à télécharger chez Spotify. Chaque version cesse de fonctionner 90 jours après sa compilation.
- **L'identifiant d'application Spotify intégré à Hutspot est celui de son auteur d'origine, limité à cinq utilisateurs.** Une personne hors de cette liste ne pourra très probablement pas se connecter dans Hutspot. Le code, le service de la voiture et l'interface D-Bus restent lisibles et vérifiables sans connexion : voir [Intégration à Sailplay](#intégration-à-sailplay-écran-de-la-voiture).
- Tout a été construit et essayé sur un seul appareil : un Jolla Phone (aarch64) sous Sailfish OS 5.

## Contenu du dépôt

| Dossier | Contenu |
|---|---|
| `hutspot/` | Code source du fork, avec tout l'historique du projet d'origine (licence MIT) |
| `soloist-audiores/` | Programme d'accompagnement : lanceur de Soloist, correction du rôle audio, fichier de service systemd |
| `soloist-netwatch/` | Programme d'accompagnement : relance de Soloist après un changement de réseau |
| `releases/` | Chaque version livrée, prête à installer |
| `binaires/` | La partie compilée de Hutspot, prête à copier sur le téléphone sans recompiler |

## Installation complète sur un téléphone neuf

### 1. Créer une clé Soloist et télécharger Soloist

1. Connectez-vous à Spotify for Developers (developer.spotify.com) avec le compte Premium.
2. Créez une **clé d'API Soloist**, en suivant la documentation Soloist du site. La clé commence par `spak_`. Gardez-la pour l'étape 4.
3. Téléchargez `soloist_release_arm64.tar.gz` depuis la page « Downloads and updates » de la documentation Soloist, et copiez-le sur le téléphone.

Puis, dans un terminal sur le téléphone :

```
devel-su pkcon install libatomic
mkdir -p ~/soloist && tar -xzf soloist_release_arm64.tar.gz -C ~/soloist
```

Si Spotify cesse un jour de jouer, retéléchargez d'abord Soloist (limite de 90 jours).

### 2. Installer Hutspot et le fork

Installez Hutspot depuis Chum, puis le module MPRIS nécessaire à son interface :

```
devel-su pkcon install mpris-qt5-qml-plugin
```

Installez ensuite la dernière version du fork :

```
tar xzf releases/hutspot-fork-0.14.0.tar.gz && cd hutspot-fork-0.14.0
devel-su sh install-hutspot-fork.sh
```

Le script sauvegarde les fichiers d'origine, puis installe :

- l'interface (QML) et la traduction française ;
- un fichier `.desktop` de remplacement : bac à sable SailJail désactivé (sinon la connexion est redemandée à chaque lancement), catégorie « lecteur audio », déclaration Sailplay ;
- le service « Parcourir » de l'écran de la voiture, avec ses fichiers d'activation D-Bus ;
- les scripts Soloist utilisés par la page Réglages (`/usr/share/hutspot/scripts/`).

`uninstall-hutspot-fork.sh` permet de revenir en arrière. Une mise à jour de Hutspot depuis Chum écrase le fork : relancez alors le script d'installation.

Le fork a aussi besoin de son propre programme compilé (corrections réseau, gestion de la session). Copiez celui du dossier `binaires/`, après avoir vérifié qu'il n'a pas été abîmé pendant le transfert :

```
cd binaires && sha256sum -c SHA256SUMS
devel-su cp /usr/bin/hutspot /usr/bin/hutspot.orig    # seulement la première fois
devel-su install -m 755 hutspot-0.13.0-aarch64 /usr/bin/hutspot
```

ou compilez-le sur le téléphone (quelques minutes) avec `build-hutspot-binary.sh`, fourni dans le dossier de la version. Le programme de `binaires/` a été compilé en novembre 2026 sur Sailfish OS 5, pour le Jolla Phone (ARM 64 bits). Si une grande mise à jour de Sailfish change la version de Qt, il risque de ne plus démarrer : recompilez-le.

### 3. Installer le lanceur et la correction du volume (`soloist-audiores`)

Sans lui, les boutons de volume règlent la sonnerie au lieu de la musique, et Soloist joue par-dessus les autres lecteurs.

- Le lanceur `soloist-audiores` suit l'état de lecture de Soloist par son interface locale (option `--ws`). Il réserve la ressource « lecture audio » auprès du gestionnaire de ressources de Sailfish dès que la musique démarre, la rend à la pause, et met Soloist en pause quand une autre application (ou un appel) prend la ressource.
- La bibliothèque `libforcerole` remplace le rôle `music` du flux audio de Soloist par `x-maemo`, le seul auquel s'applique le volume des boutons.

```
devel-su pkcon install gcc libresource-devel glib2-devel
tar xzf releases/soloist-audiores-2.1.0.tar.gz && cd soloist-audiores-2.1.0
sh install.sh
systemctl --user enable soloist
```

L'installation se termine en affichant l'état du service `soloist`. S'il n'est pas `active` à ce stade, continuez : la clé n'est enregistrée qu'à l'étape suivante. Le journal du lanceur est `~/.cache/soloist-audiores.log`.

### 4. Saisir la clé Soloist dans Hutspot

1. Ouvrez Hutspot, puis **Réglages**, section **Lecteur du téléphone (Soloist)**.
2. Collez la clé dans **Nouvelle clé Soloist** et touchez **Enregistrer la clé**. Hutspot la range dans `~/.config/soloist/env` (lisible par l'utilisateur seul) et redémarre Soloist.
3. La ligne d'état indique ensuite soit que Soloist est connecté au compte Spotify, soit qu'il n'est pas appairé et qu'il faut utiliser « Réappairer ».

La même opération est possible au terminal ; la clé est demandée sans être affichée :

```
/usr/share/hutspot/scripts/soloist-setkey.sh
```

### 5. Appairer le téléphone au compte Spotify

1. Dans la même section des Réglages, touchez **Réappairer**.
2. Dans les trois minutes, ouvrez une application Spotify sur un autre appareil (ordinateur, autre téléphone) **sur le même Wi-Fi** et choisissez l'appareil « JollaPhone ».
3. Hutspot confirme que l'appairage est fait et que Soloist est connecté.

Équivalent au terminal : `/usr/share/hutspot/scripts/soloist-pair.sh`. Pour vérifier la session : `~/soloist/soloist ctl status` indique `logged in: yes`.

Changer ou révoquer la clé annule la session : il faut alors appairer de nouveau.

Enfin, connectez-vous au compte Spotify dans Hutspot lui-même (voir la limite de cinq utilisateurs plus haut) et choisissez « JollaPhone » dans sa page Appareils.

### 6. Relance automatique après un changement de réseau (`soloist-netwatch`)

Soloist ne rétablit pas lui-même sa connexion aux serveurs de Spotify quand le téléphone change de réseau (Wi-Fi vers données mobiles, autre Wi-Fi) ou perd internet quelques secondes : il disparaît alors de la liste des appareils. Le service `soloist-netwatch` surveille le réseau et relance Soloist une fois la connexion stable. Il le relance aussi quand Soloist perd sa session, et le laisse tranquille quand il attend un appairage.

```
tar xzf releases/soloist-netwatch-1.3.0.tar.gz && cd soloist-netwatch-1.3.0
sh install.sh
```

Le journal des relances se trouve dans `~/.cache/soloist-netwatch.log`. Les délais se règlent dans `~/.config/soloist/netwatch.conf` (modèle : `netwatch.conf.example`).

## Intégration à Sailplay (écran de la voiture)

Cette section s'adresse au développeur de Sailplay et à toute personne qui adapte une autre application musicale.

### Ce que fait le fork

- **Lecture sur l'écran de la voiture.** Hutspot expose un lecteur MPRIS (`hutspot/qml/components/PlaybackState.qml`) : titre, pochette, barre de progression, déplacement, précédent / lecture-pause / suivant.
- **Page « Parcourir ».** Un service séparé, `hutspot/python/sailplay_service.py`, répond aux requêtes `content.browse` de Sailplay à l'aide du SDK Sailplay de `/opt/sailplay`. Sans Sailplay, le service ne démarre pas et Hutspot fonctionne comme avant.

### Déclaration

Le fichier `.desktop` du fork (dans chaque archive de version) déclare :

```
Categories=AudioVideo;Audio;Player;
X-Sailplay-ApiVersion=1
X-Sailplay-Service=org.solboki.Hutspot
X-Sailplay-ObjectPath=/org/sailplay/v1/App
X-Sailplay-Presentation=template
X-Sailplay-Capabilities=content;
X-Sailplay-BackgroundService=org.solboki.hutspot
```

Deux fichiers d'activation D-Bus sont installés dans `/usr/share/dbus-1/services/` :

| Nom sur le bus | Programme lancé | Rôle |
|---|---|---|
| `org.solboki.Hutspot` | `python3 /usr/share/hutspot/python/sailplay_service.py` | Service de contenu pour Sailplay ; s'arrête après dix secondes d'inactivité |
| `org.solboki.hutspot` | `/usr/bin/hutspot` (instance unique) | L'application elle-même, démarrée depuis la voiture au besoin |

### La page « Parcourir »

Elle utilise la composition « musique » des indications de présentation proposées dans la [demande de fusion n° 9 de harbour-sailplay](https://github.com/0312birdzhang/harbour-sailplay/pull/9) :

```
racine        tabs=true, side="queue"   Playlists, Albums, Podcasts, Livres audio, Récents
  Albums      cartes avec pochette      un album par carte
    <album>   liste                     la première ligne lit l'album entier ;
                                        un morceau s'ajoute à la file de lecture
  queue       panneau de droite         file de lecture, morceau en cours marqué « playing »,
                                        options Aléatoire et Répéter
```

Avec un Sailplay qui ne connaît pas ces indications (l'officiel aujourd'hui), le service le détecte à l'import et les mêmes pages s'affichent en listes simples.

Après chaque action qui modifie la file ou une option, le service augmente la `version` de la page racine et la republie, pour que Sailplay relise le panneau de droite.

### D'où viennent les données, et où reste le jeton

- Les onglets et les cartes viennent d'un résumé de la bibliothèque que Hutspot conserve dans sa base LocalStorage (clé `car_library`). Ils s'affichent tout de suite, même sans réseau.
- Les morceaux, la file et les options sont demandés au Hutspot en cours d'exécution par D-Bus : méthode `request(id, method, path, body)` et signal `reply(id, status, body)` de l'interface `org.solboki.HutspotApp`, objet `/app`, nom `org.solboki.hutspot` (`hutspot/qml/components/DBusControl.qml`).
- Hutspot seul détient la session Spotify et la renouvelle. **Le service de la voiture ne voit jamais de jeton.**
- Hutspot n'accepte qu'une liste fermée de requêtes (`carRoutes` dans `DBusControl.qml`) : morceaux d'un album, éléments d'une playlist, épisodes d'un podcast, lecture de l'état du lecteur et de la file, ajout d'un morceau ou d'un épisode à la file, suivant, aléatoire, répétition. Tout le reste est refusé.

### État des essais

Utilisée en voiture le 25 novembre 2026 (Fiat Scudo 2024, CarPlay sans fil) avec une version d'essai de Sailplay qui comprend les indications de présentation : onglets, cartes, ajout de morceaux à la file, Aléatoire et Répéter ont tous fonctionné.

Le service peut aussi être essayé sans voiture ni compte Spotify : une application factice qui répond sous un autre nom de bus, un faux serveur HTTP Spotify, et le service lancé avec les variables d'environnement `HUTSPOT_APP_SERVICE` et `HUTSPOT_CAR_SERVICE` réglées sur des noms d'essai, l'hôte étant simulé avec `sailplay_sdk.content.ContentClient`.

## Versions

### Fork de Hutspot

| Version | Contenu |
|---|---|
| 0.5.1 | Adaptation à l'API Spotify de février 2026 |
| 0.6.0 | Interface en français, menu déroulant Sailfish, mini-lecteur |
| 0.7.0 | Page « À la une », tri des albums (titre, artiste, genre, date) |
| 0.8.0 | Podcasts et livres audio, cache de la liste des albums |
| 0.9.0 | Ajout à la bibliothèque (étoile, appui long), toucher un titre le lit |
| 0.9.1 | Pochette sur l'écran de verrouillage (Amber MPRIS), notifications Sailfish |
| 0.9.2 | Reprise de la lecture quand la session Spotify a disparu (relance de Soloist) |
| 0.9.3 | JollaPhone reste dans la liste des appareils en données mobiles |
| 0.10.0 | Écran de la voiture (Sailplay) : barre de progression et déplacement, bouton « Parcourir », démarrage depuis la voiture ; boutons des écouteurs |
| 0.11.0 | Réglages : état de Soloist, « Réappairer », nouvelle clé ; scripts `soloist-pair.sh` et `soloist-setkey.sh` |
| 0.12.0 | Partie compilée corrigée : les requêtes réseau refonctionnent après un passage Wi-Fi / données mobiles (défaut de Qt 5) ; compilation sur le téléphone avec `build-hutspot-binary.sh` |
| 0.12.1 | Reprise plus rapide après un changement de réseau : Qt oublie les connexions de l'ancien réseau, les requêtes sans réponse depuis 12 s sont annulées, l'état de lecture est revérifié toutes les 2 s tant que Spotify est injoignable ; plus d'erreur 403 au premier appui quand l'état affiché était périmé ; le script de compilation installe avec zypper |
| 0.13.0 | Connexion au compte robuste face aux changements de réseau : une panne réseau pendant le renouvellement du jeton n'efface plus la session (seul un refus explicite de Spotify le fait) ; renouvellement en arrière-plan avec nouvelles tentatives silencieuses ; une requête refusée pour jeton expiré attend le nouveau jeton puis repart ; plus de dialogue « Connexion réseau perdue. Quitter ? » ni de page de connexion ouverte toute seule ; bannières d'erreur réseau limitées à une par minute ; réglage « Gérer la connexion réseau » supprimé |
| 0.14.0 | Page « Parcourir » de la voiture (indications de présentation Sailplay) : onglets Albums, Playlists, Podcasts, Livres audio, Récents ; cartes avec pochette ; morceaux d'un album ou d'une playlist, dont l'appui ajoute à la file ; panneau de droite avec la file de lecture, Aléatoire et Répéter. Les morceaux et la file sont demandés à Hutspot par D-Bus (liste fermée de requêtes), le service ne voit aucun jeton. Partie compilée inchangée (0.13.0). Repli en listes simples avec le Sailplay officiel |

L'archive `hutspot-rpm-0.7.0.tar.gz` contient un fichier de construction RPM, non utilisé : l'installation par script a été préférée.

### soloist-audiores

| Version | Contenu |
|---|---|
| 1.2.0 | Lanceur, rôle audio `x-maemo`, interception du chargement de PulseAudio |
| 2.0.0 | Relais avec les autres lecteurs (Audiobook, SailCast) : Soloist met en pause l'application qui jouait, et se met en pause quand une autre prend la main |
| 2.1.0 | Surveillance de PulseAudio : Soloist se met en pause quand un autre lecteur démarre, même si Sailfish ne signale pas la perte de la ressource ; journal dans `~/.cache/soloist-audiores.log` |

### soloist-netwatch

| Version | Contenu |
|---|---|
| 1.0.0 | Relance de Soloist après un changement de réseau ou une coupure d'internet |
| 1.0.1 | Test d'internet sans la commande `timeout`, absente de Sailfish OS |
| 1.1.0 | Ignore les commandes « soloist ctl » du lanceur |
| 1.2.0 | Ne relance plus un Soloist déconnecté de son compte (en attente d'appairage) |
| 1.3.0 | Relance aussi quand Soloist perd sa session ; relance au plus tard 45 s après un changement de réseau même si le test d'internet échoue ; test d'internet sur plusieurs serveurs |

## Limites connues

- **Données mobiles.** La découverte locale (mDNS) y est impossible : Spotify ne liste alors plus JollaPhone parmi les appareils, bien qu'il accepte toujours les commandes envoyées à son identifiant. Depuis la version 0.9.3, Hutspot rajoute lui-même dans la liste l'appareil choisi en dernier. Si cet appareil est un autre que le téléphone, il reste affiché même éteint.
- **Parties fermées de l'API Spotify.** Spotify a fermé aux applications en mode développeur les nouveautés éditoriales, les catégories, les recommandations, la radio et le contenu des playlists dont on n'est pas propriétaire. La page « À la une » est reconstruite à partir de ce qui reste ouvert.
- **Identifiant d'application.** Celui qui est intégré à Hutspot est celui de son auteur d'origine, limité à cinq utilisateurs : il ne convient pas à une diffusion publique.

## Licences

Le code de Hutspot est sous licence MIT (Willem-Jan de Hoog et contributeurs) ; les modifications du fork suivent la même licence. Soloist est un logiciel propriétaire de Spotify et n'est pas inclus. Le SDK Sailplay utilisé par le service de la voiture est fourni par Sailplay (GPL-3.0-or-later) et n'est pas recopié ici.

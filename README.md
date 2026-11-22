# Spotify natif sur Sailfish OS (Jolla Phone)

Dépôt privé, à usage personnel. Il rassemble tout ce qui permet d'écouter Spotify en natif sur le Jolla Phone, sans l'application Android.

Le montage repose sur deux pièces. Spotify Soloist, le lecteur officiel de Spotify pour Linux, joue la musique sur le téléphone et apparaît comme un appareil Spotify Connect. Hutspot, une application Sailfish libre, sert de télécommande. Sa version d'origine ne fonctionnait plus avec l'API de Spotify de 2026 : ce dépôt contient un fork adapté.

Librespot n'est pas utilisé : Spotify refuse depuis 2025-2026 les clés de déchiffrement aux comptes récents (erreur `audio key 0 1`), et aucun contournement n'existe.

## Contenu

Le dossier `hutspot/` contient le code source du fork, avec tout l'historique du projet d'origine (licence MIT). Le dossier `soloist-audiores/` contient le lanceur de Soloist, la bibliothèque qui corrige son rôle audio et le fichier de service systemd. Le dossier `releases/` contient chaque version livrée, prête à installer. Le dossier `binaires/` contient la partie compilée de Hutspot, prête à copier sur le téléphone sans recompiler.

## Installation complète sur un téléphone neuf

### 1. Soloist

Soloist ne doit pas être redistribué : il se télécharge chez Spotify. Chaque version n'est utilisable que 90 jours après sa compilation. Si Spotify cesse de jouer, retéléchargez d'abord Soloist.

Créez une clé d'API Soloist sur le tableau de bord Spotify for Developers (compte Premium), puis téléchargez `soloist_release_arm64.tar.gz` depuis la page « Downloads and updates » de la documentation Soloist.

```
devel-su pkcon install libatomic
mkdir -p ~/soloist && tar -xzf soloist_release_arm64.tar.gz -C ~/soloist
mkdir -p ~/.config/soloist
read -rs -p "Clé Soloist : " KEY && echo
printf 'SOLOIST_API_KEY=%s\n' "$KEY" > ~/.config/soloist/env && unset KEY
chmod 600 ~/.config/soloist/env
```

### 2. Lanceur et correction du volume

Sans ces deux pièces, les boutons de volume règlent la sonnerie au lieu de la musique, et Soloist joue par-dessus les autres lecteurs. Le lanceur `soloist-audiores` suit l'état de lecture de Soloist par son interface locale (option `--ws`) : il réserve pour Soloist la ressource « lecture audio » auprès du gestionnaire de ressources de Sailfish dès que la musique démarre, la rend à la pause, et met Soloist en pause quand une autre application (ou un appel) prend la ressource. La bibliothèque `libforcerole` remplace le rôle `music` du flux de Soloist par `x-maemo`, le seul auquel s'applique le volume des boutons.

```
devel-su pkcon install gcc libresource-devel glib2-devel
tar xzf releases/soloist-audiores-2.1.0.tar.gz && cd soloist-audiores-2.1.0
sh install.sh
systemctl --user enable soloist
```

Au premier lancement, sélectionnez « JollaPhone » une fois depuis l'application Spotify d'un autre appareil, sur le même Wi-Fi, pour l'appairer. Changer ou révoquer la clé Soloist annule la session : il faut alors appairer de nouveau. `~/soloist/soloist ctl status` indique `logged in: yes` quand la session est active. Le plus simple est d'utiliser les Réglages de Hutspot (section « Lecteur du téléphone »), ou depuis le terminal `/usr/share/hutspot/scripts/soloist-pair.sh` et `/usr/share/hutspot/scripts/soloist-setkey.sh`.

### 3. Relance automatique après un changement de réseau

Soloist ne rétablit pas lui-même sa connexion aux serveurs de Spotify quand le téléphone change de réseau (Wi-Fi vers données mobiles, autre Wi-Fi) ou perd internet quelques secondes : il disparaît alors de la liste des appareils. Le service `soloist-netwatch` surveille le réseau et relance Soloist une fois la connexion stable depuis 10 secondes.

```
tar xzf releases/soloist-netwatch-1.0.1.tar.gz && cd soloist-netwatch-1.0.1
sh install.sh
```

Le journal des relances se trouve dans `~/.cache/soloist-netwatch.log`. Les délais se règlent dans `~/.config/soloist/netwatch.conf` (modèle : `netwatch.conf.example`).

### 4. Hutspot

Installez Hutspot depuis Chum, puis le module MPRIS nécessaire à son interface :

```
devel-su pkcon install mpris-qt5-qml-plugin
```

Installez ensuite la dernière version du fork :

```
tar xzf releases/hutspot-fork-0.12.1.tar.gz && cd hutspot-fork-0.12.1
devel-su sh install-hutspot-fork.sh
```

Le script sauvegarde les fichiers d'origine, installe l'interface et la traduction française, remplace le fichier `.desktop` (bac à sable SailJail désactivé, sinon la connexion est redemandée à chaque lancement ; déclaration de lecteur audio et de Sailplay), et installe le service « Parcourir » de l'écran de la voiture avec ses fichiers d'activation D-Bus. `uninstall-hutspot-fork.sh` permet de revenir en arrière. Une mise à jour de Hutspot depuis Chum écrase le fork : il suffit alors de relancer les deux scripts. `build-hutspot-binary.sh` compile la partie C++ de Hutspot sur le téléphone (quelques minutes) et remplace le programme du paquet Chum, sauvegardé dans `/usr/bin/hutspot.orig`.

Pour éviter de recompiler, on peut installer directement le programme déjà compilé du dossier `binaires/`, après avoir vérifié qu'il n'a pas été abîmé pendant le transfert :

```
cd binaires && sha256sum -c SHA256SUMS
devel-su cp /usr/bin/hutspot /usr/bin/hutspot.orig    # seulement la première fois
devel-su install -m 755 hutspot-0.12.1-aarch64 /usr/bin/hutspot
```

Ce programme a été compilé le 22 novembre 2026 sur Sailfish OS 5, pour le Jolla Phone (processeur ARM 64 bits). Si une grande mise à jour de Sailfish change la version de Qt, il risque de ne plus démarrer : il faut alors recompiler avec `build-hutspot-binary.sh`.

## Versions

| Version | Contenu |
|---|---|
| Hutspot 0.5.1 | Adaptation à l'API Spotify de février 2026 |
| Hutspot 0.6.0 | Interface en français, menu déroulant Sailfish, mini-lecteur |
| Hutspot 0.7.0 | Page « À la une », tri des albums (titre, artiste, genre, date) |
| Hutspot 0.8.0 | Podcasts et livres audio, cache de la liste des albums |
| Hutspot 0.9.0 | Ajout à la bibliothèque (étoile, appui long), toucher un titre le lit |
| Hutspot 0.9.1 | Pochette sur l'écran de verrouillage (Amber MPRIS), notifications Sailfish |
| Hutspot 0.12.0 | Partie compilée corrigée : les requêtes réseau refonctionnent après un passage Wi-Fi / données mobiles (défaut de Qt 5) ; compilation sur le téléphone avec `build-hutspot-binary.sh` |
| Hutspot 0.12.1 | Reprise plus rapide après un changement de réseau : Qt oublie les connexions de l'ancien réseau, les requêtes sans réponse depuis 12 s sont annulées, l'état de lecture est revérifié toutes les 2 s tant que Spotify est injoignable ; plus d'erreur 403 au premier appui quand l'état affiché était périmé ; le script de compilation installe avec zypper |
| Hutspot 0.11.0 | Réglages : état de Soloist, « Réappairer », nouvelle clé ; scripts `soloist-pair.sh` et `soloist-setkey.sh` |
| Hutspot 0.10.0 | Écran de la voiture (Sailplay) : barre de progression et déplacement, bouton « Parcourir », démarrage depuis la voiture ; boutons des écouteurs |
| Hutspot 0.9.2 | Reprise de la lecture quand la session Spotify a disparu (relance de Soloist) |
| Hutspot 0.9.3 | JollaPhone reste dans la liste des appareils en données mobiles |
| soloist-audiores 1.2.0 | Lanceur, rôle audio `x-maemo`, interception du chargement de PulseAudio |
| soloist-netwatch 1.0.0 | Relance de Soloist après un changement de réseau ou une coupure d'internet |
| soloist-audiores 2.0.0 | Relais avec les autres lecteurs (Audiobook, SailCast) : Soloist met en pause l'application qui jouait, et se met en pause quand une autre prend la main |
| soloist-netwatch 1.1.0 | Ignore les commandes « soloist ctl » du lanceur |
| soloist-netwatch 1.3.0 | Relance aussi quand Soloist perd sa session ; relance au plus tard 45 s après un changement de réseau même si le test d'internet échoue ; test d'internet sur plusieurs serveurs |
| soloist-netwatch 1.2.0 | Ne relance plus un Soloist déconnecté de son compte (en attente d'appairage) |
| soloist-audiores 2.1.0 | Surveillance de PulseAudio : Soloist se met en pause quand un autre lecteur démarre, même si Sailfish ne signale pas la perte de la ressource ; journal dans `~/.cache/soloist-audiores.log` |
| soloist-netwatch 1.0.1 | Test d'internet sans la commande `timeout`, absente de Sailfish OS |

L'archive `hutspot-rpm-0.7.0.tar.gz` contient un fichier de construction RPM, non utilisé : l'installation par script a été préférée.

## Limites connues

En données mobiles, la découverte locale (mDNS) est impossible : Spotify ne liste alors plus JollaPhone parmi les appareils, bien qu'il accepte toujours les commandes envoyées à son identifiant. Depuis la version 0.9.3, Hutspot rajoute lui-même dans la liste l'appareil choisi en dernier. Si cet appareil est un autre que le téléphone, il reste affiché même éteint.

Spotify a fermé aux applications en mode développeur les nouveautés éditoriales, les catégories, les recommandations, la radio et le contenu des playlists dont on n'est pas propriétaire. La page « À la une » est reconstruite à partir de ce qui reste ouvert. L'identifiant d'application intégré à Hutspot est celui de son auteur d'origine, limité à cinq utilisateurs : il ne convient pas à une diffusion publique.

## Licences

Le code de Hutspot est sous licence MIT (Willem-Jan de Hoog et contributeurs) ; les modifications du fork suivent la même licence. Soloist est un logiciel propriétaire de Spotify et n'est pas inclus.

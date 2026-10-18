# Faux positifs du 18 octobre 2026

Un outil a annoncé un défaut. Le défaut n'était pas là. On relit ce fichier avant de croire le même outil.

## Journaux nginx lisibles par `deploy`

- Outil : `ls` sur `/var/log/nginx`, plus la lecture de `/etc/logrotate.d/nginx`.
- Ce qui a été annoncé : `deploy` peut lire `access.log` sur les cinq hôtes.
- Ce qui est vrai : le fichier est `-rw-r----- www-data adm`. `deploy` n'est pas dans `adm`. `head` et `wc` répondent permission refusée. Voir le nom d'un fichier n'est pas le lire.

## Seize sites sans formulaire

- Signalé le 18 octobre : un passage a compté seize sites sans formulaire.
- Le défaut annoncé n'existait pas.
- L'outil de ce passage n'a pas été rejoué dans la session qui écrit ce fichier. On ne le nomme pas de mémoire.

## Cinq enregistrements d'une seconde

- Signalé le 18 octobre : cinq enregistrements mesurés à une seconde.
- Le défaut annoncé n'existait pas.
- L'outil de ce passage n'a pas été rejoué ici. On ne le nomme pas de mémoire.

## Le clic qui n'avançait pas sur chauffage

- Signalé le 18 octobre : un clic outil sur chauffage n'avançait pas.
- Le défaut annoncé n'existait pas.
- L'outil de ce passage n'a pas été rejoué ici. On ne le nomme pas de mémoire.

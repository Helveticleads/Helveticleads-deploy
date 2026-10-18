# Faux positifs du 18 octobre 2026

Un outil a annoncé un défaut. Le défaut n'était pas là. On relit ce fichier avant de croire le même outil.

## Règle — citation ou « non confronté »

Un relevé porte sa citation quand chaque fait est accompagné de ce qui est servi : la page, l'endroit, et la ligne copiée telle quelle. La conclusion a été confrontée à cette ligne.

Sinon le relevé est marqué **non confronté**. Il reste une piste. Il n'est pas une mesure. Le présenter comme une mesure coûte une journée à quelqu'un d'autre.

Ce que l'outil retourne (un nom de fichier, un compte, une correspondance) n'est pas la citation. La citation est la ligne servie, relue après coup.

Trois relevés du 18 octobre avaient cette forme : les journaux nginx « lisibles », douze numéros « affichés », dix sites « en retard ». Dans les trois cas la conclusion sortait du retour de l'outil, sans la ligne servie.

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

## Douze numéros « affichés » que la plateforme ne connaît pas

- Outil : expression régulière sur le HTML, le point compté comme séparateur de téléphone, `(?:[\s./-]?\d){7}`.
- Ce qui a été annoncé : douze numéros affichés, absents de la plateforme.
- Ce qui est vrai, re-servi le 19 octobre : neuf de ces douze sont des coordonnées de tracé SVG. Exemple servi sur helvetique-nuisibles.ch : `022.617.46.40` dans `c.405-.022.617.46.402.803a6`. Exemple sur helvetic-heizung.ch : `033 2.34 2.34 0` dans un `path`. Aucune de ces lignes n'est un numéro. Les trois autres sont une clé `"telephone"` dans un script JSON-LD (emergenza-infestanti.ch, schaedlinge-notfall.ch), pas une ligne visible. Le relevé était non confronté.

## Le clic qui n'avançait pas sur chauffage

- Signalé le 18 octobre : un clic outil sur chauffage n'avançait pas.
- Le défaut annoncé n'existait pas.
- L'outil de ce passage n'a pas été rejoué ici. On ne le nomme pas de mémoire.

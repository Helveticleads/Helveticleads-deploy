# Faux positifs du 18–19 octobre 2026

Un outil a annoncé un défaut. Le défaut n'était pas là. On relit ce fichier avant de croire le même outil.

## Règle — citation ou « non confronté »

Un relevé porte sa citation quand chaque fait est accompagné de ce qui est servi : la page, l'endroit, et la ligne servie copiée telle quelle. La conclusion a été confrontée à cette ligne.

Sinon le relevé est marqué **non confronté**. Il reste une piste. Il n'est pas une mesure. Le présenter comme une mesure coûte une journée à quelqu'un d'autre.

Ce que l'outil retourne (un nom de fichier, un compte, une correspondance) n'est pas la citation. La citation est la ligne servie, relue après coup.

## Décision — pas de `Disallow` pour les robots IA

Le parc reste lisible par les LLM et consultable par les outils qu'un prospect ou un acheteur peut interroger. Aucune session ne propose de `Disallow` GPTBot, ClaudeBot, PerplexityBot ou équivalent. La question ne revient pas à chaque relevé. Ce qui se mesure, c'est le coût (bande passante, place en journaux), pas une recommandation de blocage.

## Journaux nginx lisibles par `deploy`

- Outil : `ls` sur `/var/log/nginx`, plus la lecture de `/etc/logrotate.d/nginx`.
- Ce qui a été annoncé : `deploy` peut lire `access.log` sur les cinq hôtes.
- Ce qui est vrai : le fichier est `-rw-r----- www-data adm`. `deploy` n'est pas dans `adm` (sauf après `usermod`). `head` et `wc` répondent permission refusée. Voir le nom d'un fichier n'est pas le lire.

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

## Gabarits de champ téléphone — pas une anomalie

`079 123 45 67`, `079 000 00 00` et `+41 79 000 00 00` sont l'attribut `placeholder` des champs téléphone : le texte grisé qui montre un format et disparaît à la frappe. Personne ne peut les appeler. Confirmé côté DE et côté FR (MODIFS RESEAUX 1 et 2). La rangée de zéros n'apprend aucun format. Les sessions de parc uniformisent sur `079 123 45 67`. Un prochain relevé ne les ressort pas comme un numéro affiché.

## Douze numéros « affichés » que la plateforme ne connaît pas

- Outil : expression régulière sur le HTML, le point compté comme séparateur de téléphone, `(?:[\s./-]?\d){7}`.
- Ce qui a été annoncé : douze numéros affichés, absents de la plateforme.
- Ce qui est vrai, re-servi le 19 octobre : neuf de ces douze sont des coordonnées de tracé SVG. Exemple servi sur helvetique-nuisibles.ch : `022.617.46.40` dans `c.405-.022.617.46.402.803a6`. Exemple sur helvetic-heizung.ch : `033 2.34 2.34 0` dans un `path`. Aucune de ces lignes n'est un numéro. Les trois autres sont une clé `"telephone"` dans un script JSON-LD (emergenza-infestanti.ch, schaedlinge-notfall.ch), pas une ligne visible. Le relevé était non confronté.

## KAIOS compté comme bot IA

- Outil : filtre « AI » ou « bot » dans le User-Agent.
- Ce qui a été annoncé : 324 requêtes KAIOS en six secondes sur Infomaniak FR, le 15 octobre, comme agent IA.
- Ce qui est vrai : KAIOS est un système de téléphone. Le sous-mot `AI` est dans le nom. Sorti du compte.

## Dernière connexion = `tail -1` du dernier fichier

- Outil : `zgrep … | grep Accepted publickey | tail -1`, fichiers listés avec `auth.log` en premier.
- Ce qui a été annoncé : dernières connexions des trois clés Infomaniak FR le 23 septembre 2026.
- Ce qui est vrai : `tail -1` prend la dernière ligne du dernier fichier lu, pas le maximum des horodatages. Les vraies dernières sont le 17 octobre 2026, depuis des adresses Azure (runners GitHub). Les trois clés sont actives. Un inventaire intitulé « dormantes » qui les rangeait avec les dormantes Netcup invitait à retirer ce qui fait tourner la CI.

# Affirmation de verdict

Une garde doit **écrire** son verdict, pas seulement rendre un code :

- `GATE_OK …` — mesuré, accepté
- `GATE_FAIL …` — mesuré, refusé
- `GATE_SKIP …` — mesuré, laisser passer sans le chemin nominal
- `GATE_PANNE <nom>:…` — la garde n’a pas pu mesurer (crash, pas de ligne)

L’étape appelante utilise `exiger-verdict.sh` : si aucune ligne `GATE_OK|FAIL|SKIP` n’apparaît, elle émet `GATE_PANNE <nom>:pas_de_verdict` et sort en 2. Un exit 0 sans ligne n’est plus un feu vert.

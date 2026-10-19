# Affirmation de verdict

Une garde doit **écrire** son verdict, pas seulement rendre un code :

- `GATE_OK …` — mesuré, accepté
- `GATE_FAIL …` — mesuré, refusé
- `GATE_SKIP …` — mesuré, laisser passer sans le chemin nominal
- `GATE_PANNE <nom>:…` — la garde n’a pas pu mesurer (crash, pas de ligne)

L’étape appelante utilise `exiger-verdict.sh` : si aucune ligne `GATE_OK|FAIL|SKIP` n’apparaît, elle émet `GATE_PANNE <nom>:pas_de_verdict` et sort en 2. Un exit 0 sans ligne n’est plus un feu vert.

## Retour — une seule copie

Tant que `exiger-verdict.sh` n’est pas sur le tag `v1`, les quatre jobs garde (pro, guêpes, punaise, rongeurs) **inlinent** la vérification. Ce n’est pas le même texte que ce script (`mktemp`, `"$@"`, contrôle d’usage) : même squelette `grep` / `GATE_PANNE`, commande `node` et `GARDE_NOM` propres à chaque dépôt.

**Condition de retour.** Le remplacement n'est pas une factorisation : `exiger-verdict.sh` n'est pas le squelette inline (`mktemp`, `trap`, `"$@"`, contrôle d'usage). Il se fait **après** que le script a été prouvé équivalent sur les quatre jobs — même corpus, même `GARDE_NOM`, mêmes quatre sorties (`GATE_OK`, `GATE_FAIL`, `GATE_SKIP`, absence de ligne → `GATE_PANNE <nom>:pas_de_verdict`). Porter le même rôle ne suffit pas. Une garde recopiée se re-mesure sur le corpus de destination.

Le jour où cette équivalence est écrite (suite dans ce dossier) **et** que `ops/garde-appel/exiger-verdict.sh` est sur `v1` (le SHA que `@v1` résout), les quatre inline se remplacent par :

```yaml
- name: Verdict affirmé
  env:
    GARDE_NOM: <nom-du-job>
  run: |
    # checkout du workflow réutilisable au SHA @v1, puis :
    GARDE_NOM="$GARDE_NOM" bash ops/garde-appel/exiger-verdict.sh -- node <script-de-garde>
```

Pas de cinquième variante entre-temps. Après le remplacement, ce README ne décrit plus que l’appel.

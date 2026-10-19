# Provision hôte — placeholder nginx

## Incident 2026-10-17

Le 17 octobre, un agent (session MODIFS RESEAUX 2 / Infomaniak FR) a :

1. Posé correctement `releases/placeholder` + `current` pour **guêpes, punaise, pro-nuisibles** avec `if [ ! -e current ]`.
2. Puis, sur ordre explicite « aligner rongeurs sur les trois autres », basculé `helvetique-rongeurs.ch/current` de `releases/20260917-110251` (217 pages) vers un placeholder vide — **sans lire si le lien résolvait déjà**.

Résultat : 217 pages hors ligne pendant deux jours. Les releases pleines étaient encore là ; seul le lien avait été écrasé.

Ce n’était pas un script durable sur l’hôte : des commandes inline. `poser-placeholder.sh` fixe la règle pour la suite.

## Règle

`readlink current` avant d’écrire. **Si ça résout vers un répertoire → refus.** Même esprit que la garde anti-perte : présence ≠ licence d’écraser.

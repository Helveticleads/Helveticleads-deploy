# api-server — sauvetage depuis binaires (2026-09-27)

Voir [COMPTE-RENDU.md](./COMPTE-RENDU.md).

Sources récupérées (sanitisées) : `from-hosts/<hôte>/`.  
Métadonnées et comparaison : `meta/`.

**Ne pas rebuild / redéployer** l’api-server tant que le stub git n’a pas été remplacé volontairement par une variante validée.

Réconciliation (caractérisation + arbre unique) : voir [RECONCILIATION.md](./RECONCILIATION.md).

```bash
cd ops/api-server-sauvetage && npm test
# ou : CHAR_TARGET=extract|reconciled npx vitest run characterization
```

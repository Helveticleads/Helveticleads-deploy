# api-server — sauvetage depuis binaires (2026-09-27)

Voir [COMPTE-RENDU.md](./COMPTE-RENDU.md).

Sources récupérées (sanitisées) : `from-hosts/<hôte>/`.  
Métadonnées et comparaison : `meta/`.  
Réconciliation : [RECONCILIATION.md](./RECONCILIATION.md).  
Runbook bascule IONOS (pas d’exécution tant que GO) : [BASCULE-IONOS.md](./BASCULE-IONOS.md).

```bash
cd ops/api-server-sauvetage
npm ci
npm run ci   # caractérisation extract+reconciled + build dist/index.mjs + smoke boot
# build seul : npm run build   → dist/index.mjs (+ .map), HOST_PROFILE requis au boot
```

`dist/` est gitignored ; le binaire se produit en local / CI, puis se pose sur l’hôte le jour J.

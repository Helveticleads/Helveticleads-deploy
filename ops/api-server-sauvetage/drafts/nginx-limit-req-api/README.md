# Draft — limit_req sur location /api/ (non déployé)

Mesure d’accès nginx **refusée** (logs `www-data:adm`, `sudo -n` indisponible sur
ionos / lws / infomaniak-fr / infomaniak-de / hetzner). Pas de max POST/IP/heure
observé sur 90 j.

Proxy CRM (90 j, sources `tracking`+`webchat` = ce qui touche l’API formulaire) :
pic **16 leads / heure** tous IP confondus (2026-07-29) — pas une cadence par IP.
Trafic légitime = quelques leads / jour / parc.

Plafond proposé : **20 req/heure / IP**, burst 5 — largement au-dessus d’un humain,
sous un spray bot. À recalibrer dès que la lecture des access logs est possible.

Déploiement : **un serveur à la fois**, pas le soir de rédaction. Exclusivité FR puis DE.

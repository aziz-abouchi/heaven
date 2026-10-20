# HTTPS WIP — diagnostic (2026-10-20)

## Etat
https.hvn : @tls_connect + @tls_write OK (handshake ~70ms).
@tls_read retourne 0 bytes sur dbpedia.org:443.
curl equivaut 200 + 367 bytes sans UA.

## Hypotheses
1. Boucle @tls_read (engine_expr.zig:1240) : SSL_read retourne 0
   (WANT_READ) au 1er tour -> break immediat. Fix : boucler sur
   SSL_ERROR_WANT_READ via SSL_get_error, pas sur n==0.
2. SSL_set_fd : net_connect retourne Int, est-ce un vrai fd POSIX
   ou un handle interne ? A verifier.
3. @tls_write retourne 0 sans ecrire : logguer le retour.

## Effort
Investigation : 1 session. Fix : 1-3 blocs selon hypothese.

## Non-bloquant
Test local test_ontology_derivation.hvn sert d'interim.

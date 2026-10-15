# Bug parser : escapes \x non supportes

**Date** : 2026-10-15

## Symptome

`"\x12\x34"` en string Heaven n'interprete pas `\x12` comme
byte 0x12. Le parser laisse les 4 chars litteraux.

## Impact

- DNS query (header binaire) non construite via string escapes.
- Idem pour tout protocole binaire (Diameter, AMQP, Cassandra).

## Workaround

Utiliser `poke_byte` + `string_of_bytes` :

    dns_build _ =
      let buf = (raw_alloc 12) in
      let _ = (poke_byte buf 0 0x12) in
      ...
      (string_of_bytes buf 12)

Marche (test "header 12 bytes" passe 3/3).

## Fix propre

Dans le lexer, reconnaitre `\xNN` comme byte hex. Effort 30 min.
Basse priorite (poke_byte couvre).

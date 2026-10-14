# Effets réseau

Heaven est a evaluation paresseuse.

## Regle d'Or
Utilisez des expressions sequentielles :

```heaven
let cap=(cap_acquire "net:listen:8080") in
let sock=(@net_listen cap 8080) in
(print "OO")
let client=(@net_accept cap sock) in
(@net_close cap client)
```

# Tuto : ecrire du code impératif sans let-chain

Heaven a un bug connu : `let a = e1 in let b = e2 in body`
n'est pas evalue (voir `_let_chain_bug.md`). Voici comment
ecrire un programme qui marche.

## Regle d'or

**Un seul `let` par fonction, au top-level.**

    fn compute _ = (let x = (+ 1 2) in (* x 3))
    (compute 0)

`compute` retourne 9. Marche.

## Sequencer des effets

Utiliser `seq e1 e2` (evalue `e1`, puis `e2`, retourne `e2`).

    fn greet _ = (seq (print "Hello") (seq (print "World") "done"))
    (greet 0)

Sortie : `"Hello"`, `"World"`, `"done"`. Marche.

## Passer des valeurs entre etapes

Ecrire une fonction par etape, passer les valeurs en parametres.

    fn double x _ = (* x 2)
    fn add_one x _ = (+ x 1)
    fn pipeline _ = (add_one (double 5 0) 0)
    (pipeline 0)   -- = 11

## Serveur HTTP one-shot (pattern complet)

    fn respond cap cl _ = (seq (@net_write cap cl "HTTP/1.1 200 OK") (@net_close cap cl))
    fn accept cap sock _ = (respond cap (@net_accept cap sock) 0)
    fn setup _ = (seq (print "listen") (accept (cap_acquire "net:8080") (@net_listen (cap_acquire "net:8080") 8080) 0))
    (setup 0)

Attention : `cap_acquire` est appele 2 fois, chaque appel cree un
capability. A tester si l'acquisition est idempotente.

## Pieges

- `let` en argument : `f (let x = v in body) arg` echoue
  (`UnboundVariable`). Extraire en fonction.
- `let` chain : `let a = ... in let b = ... in body` = AST non-evalue.
- Multi-ligne : `splitStatements` traite chaque ligne non-indentee
  comme un statement separe. Ecrire en une ligne, ou indenter les
  continuations (mais `convertLetIn` multi-ligne est aussi casse).
- CRLF dans les strings : `"\r\n"` devient des vrais newlines,
  casse le parse. Utiliser `\n` seul, ou `@net_http_respond`.


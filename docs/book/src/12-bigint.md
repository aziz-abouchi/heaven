# Chapitre 13 — BigInt et calcul en précision arbitraire

`i64` plafonne à environ `9.2 * 10^18`. Pour les RSA, les tests de
primalité, ou simplement compter les graines de sable, il faut plus.
Heaven fournit un **BigInt** dans `core/bigint.hvn` — entièrement
écrit en Heaven, aucun magic supplémentaire.

## Représentation

Un BigInt est **signe + liste de digits** (0..9), MSB-first :

    data BList  = BNil | BCons Int BList
    data BigInt = BZero | BPos BList | BNeg BList

Par exemple, `123` = `BPos (BCons 1 (BCons 2 (BCons 3 BNil)))`.
Les zéros de tête sont interdits (sauf `BZero`).

## Construction

    from_int 42           -- BPos (BCons 4 (BCons 2 BNil))
    from_int (- 0 42)     -- BNeg (BCons 4 (BCons 2 BNil))
    from_string "12345"   -- parse depuis une string

## Opérations

Toutes les opérations arithmétiques sont signées :

    badd A B              -- A + B (gère tous les signes)
    bsub A B              -- A - B
    bmul A B              -- A * B
    bcmp A B              -- -1, 0, ou 1

    (to_int (badd (from_int 10) (from_int 5)))       -- 15
    (to_int (bsub (from_int 3) (from_int 10)))       -- -7
    (to_int (bmul (from_int 123) (from_int 456)))    -- 56088
    (bcmp (from_int 10) (from_int 10))               -- 0

## Conversion vers string

    bto_string B           -- "12345" ou "-42"
    from_string "9876"     -- BPos ...

Le round-trip est stable :

    (bto_string (from_string "9876543210")) == "9876543210"

## Dépasser i64

Les tests valident `10^26` :

    (bcmp (badd (from_string "99999999999999999999999999")
                (from_string "1"))
          (from_string "99999999999999999999999999"))
    -- 1 (plus grand)

## Style lisible

Grâce à D18 (let-in multi-ligne), la logique s'écrit naturellement :

    bsub_signed A B = (badd_signed A (bneg B))

    bmul_signed A B =
      let sa = bsign A in
      let sb = bsign B in
      let r = bmul_bl (babs_bl A) (babs_bl B) in
      if (bnull r) BZero
      (if (= (* sa sb) 1) (BPos r) (BNeg r))

## Ce qui manque (v2)

- `bdivmod` : division euclidienne `(quotient, reste)`.
- `bmod` : reste.
- Multiplication rapide (Karatsuba) pour les gros nombres.

## Comment ça marche — addition

L'addition se fait **de droite à gauche** (LSB-first), avec carry :

    badd_lsb_l (BCons a ar) (BCons b br) carry =
      let s = (+ (+ a b) carry) in
      BCons (% s 10) (badd_lsb_l ar br (/ s 10))

On reverse, on additionne, on reverse, on strip les zéros. C'est
exactement la méthode apprise à l'école, mais sur des listes.

## Comment ça marche — multiplication

Digit par digit, en accumulant les décalages :

    bmul_l (BCons a ar) B =
      (badd_bl (bmul_digit B a) (bmul_l ar (bshift_bl B)))

où `bshift_bl` multiplie par 10 (ajoute un zéro à droite).

C'est **quadratique** (O(n²)), ce qui est acceptable jusqu'à ~1000
digits. Au-delà, il faudra Karatsuba.

## Pour aller plus loin

- `tests/test_bigint.hvn` : 22 tests qui couvrent tous les cas.
- `docs/DECISIONS.md` D17 : décision de design.
- Prochaine étape : `bdivmod` pour compléter (RSA, pgcd).

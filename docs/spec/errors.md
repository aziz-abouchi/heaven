# Heaven - Catalogue des erreurs canoniques

**Version** : 1.0 (2026-10-01)
**Statut** : descriptif (WYSIWYG). Decrit les erreurs telles qu'elles sont
produites par Heaven aujourd'hui.

Ce document catalogue toutes les erreurs que Heaven peut emettre, classees
par phase de traitement (lexing, parsing, type-checking, execution).

---

## 1. Erreurs de syntaxe (Lexer/Parser)

### 1.1 Lexing

| Code | Message | Cause | Exemple |
|------|---------|-------|---------|
| LEX_UNTERMINATED_STRING | unterminated string literal | Chaine non fermee | "bonjour |
| LEX_INVALID_ESCAPE | invalid escape sequence | Sequence d'echappement invalide | "\q" |
| LEX_UNEXPECTED_CHAR | unexpected character | Caractere non reconnu | @ (sauf dans @import) |

### 1.2 Parsing

| Code | Message | Cause | Exemple |
|------|---------|-------|---------|
| PARSE_EXPECTED_IDENT | expected identifier | Identificateur manquant | data = Nil |
| PARSE_EXPECTED_TYPE | expected type expression | Type manquant apres : | sig f : |
| PARSE_UNEXPECTED_EOF | unexpected end of file | Fichier tronque | theorem t : |
| PARSE_UNEXPECTED_TOKEN | unexpected token | Token inattendu | data Foo = Bar Baz (manque |) |
| PARSE_MALFORMED_S_EXPR | malformed s-expression | Parentheses mal equilibrees | (foo (bar) |

**Note** : Le parser accepte 1.2.3 comme un token unique (lexer permissif),
mais la conversion en nombre echoue ensuite avec PARSE_INVALID_NUMBER.

---

## 2. Erreurs de type (Type Checker / Elaborator)

### 2.1 Verification structurelle

| Code | Message | Cause | Exemple |
|------|---------|-------|---------|
| TYPE_ARITY_MISMATCH | constructor arity mismatch | Mauvais nombre d'arguments | head Nil (Nil attend 0 args, domaine en attend 1) |
| TYPE_KIND_MISMATCH | constructor kind mismatch | Constructeur incompatible avec le domaine | nameOf apple contre Color -> String |
| TYPE_BASE_STEP_MISMATCH | base/step convention mismatch | Pattern base vs domaine step | head _ Nil contre (n : Nat) -> Vec (succ n) -> a |

### 2.2 Unification

| Code | Message | Cause | Exemple |
|------|---------|-------|---------|
| UNIFY_OCCURS_CHECK | occurs check failed | Variable apparait dans son propre type | x = List x |
| UNIFY_CLASH | type clash | Types incompatibles | 42 : Bool |
| UNIFY_ARROW_MISMATCH | arrow type mismatch | Domaine/codomaine incompatibles | f : Int -> Bool, f true |

### 2.3 Inference

| Code | Message | Cause | Exemple |
|------|---------|-------|---------|
| INFER_UNKNOWN | cannot infer type | Type non inferable | _ sans contexte |
| INFER_AMBIGUOUS | ambiguous type | Plusieurs types possibles | id sans annotation |

---

## 3. Erreurs de module (Import/Export)

| Code | Message | Cause | Exemple |
|------|---------|-------|---------|
| MODULE_NOT_FOUND | module not found | Fichier introuvable | import "nonexistent.hvn" |
| MODULE_CYCLE | circular import detected | Cycle dans les imports | A -> B -> A |
| MODULE_EXPORT_ENFORCEMENT | symbol not exported | Acces a un symbole non-exporte | M.secret quand secret n'est pas dans export |
| MODULE_IMPORT_FAILED | import failed | Erreur dans le fichier importe | Fichier avec erreur de syntaxe |

**Note** : L'enforcement est actuellement faible. L'enforcement fort est planifie (roadmap #module v3).

---

## 4. Erreurs de preuve (Tactics / Proof State)

| Code | Message | Cause | Exemple |
|------|---------|-------|---------|
| TACTIC_UNKNOWN | unknown tactic | Tactique non reconnue | prove t by { foo } |
| TACTIC_FAILED | tactic failed | Tactique a echoue | reflexivity sur x + 0 = x |
| TACTIC_HYPOTHESIS_NOT_FOUND | hypothesis not found | Hypothese manquante | rewrite H quand H n'existe pas |
| TACTIC_GOAL_NOT_SOLVED | unsolved goals remaining | Buts non resolus en fin de preuve | Preuve incomplete |
| PROOF_UNIFY_FAILED | proof unification failed | Echec d'unification dans le contexte de preuve | rewrite avec equation incompatible |

---

## 5. Erreurs d'execution (Runtime)

| Code | Message | Cause | Exemple |
|------|---------|-------|---------|
| EVAL_UNDEFINED | undefined symbol | Symbole non defini | foo 42 quand foo n'existe pas |
| EVAL_ARITY_MISMATCH | function arity mismatch | Mauvais nombre d'arguments | add 1 (add attend 2 args) |
| EVAL_PATTERN_MATCH_FAILURE | pattern match failure | Aucun pattern ne correspond | head Nil sans cas pour Nil |
| EFFECT_UNHANDLED | unhandled effect | Effet sans handler | perform "ReadFile" "x.txt" sans handle |
| IO_FILE_NOT_FOUND | file not found | Fichier inexistant | readFile "nonexistent.txt" |

---

## 6. Erreurs de test (Test Runner)

| Code | Message | Cause | Exemple |
|------|---------|-------|---------|
| TEST_ASSERT_FAILED | assertion failed | assert_eq a echoue | assert_eq 1 2 |
| TEST_PARSE_ERROR | test parse error | Erreur de syntaxe dans le test | test "foo" : 1 + |
| TEST_EVAL_ERROR | test evaluation error | Erreur pendant l'evaluation du test | Division par zero |

---

## 7. Format des messages d'erreur

Tous les messages d'erreur suivent ce format :

<phase>: <code>: <message>
  at <file>:<line>:<column>
  <context_snippet>

**Exemple** :
parse: PARSE_EXPECTED_IDENT: expected identifier
  at core/test.hvn:42:10
    data = Nil
         ^

---

## 8. Comment ajouter une nouvelle erreur

1. Identifier la phase (lexing, parsing, type-checking, etc.)
2. Choisir un code unique en majuscules avec underscores
3. Rediger un message clair et concis
4. Ajouter une entree dans ce document avec cause et exemple
5. Implementer l'emission de l'erreur dans le code Zig correspondant

**Regles** : Toute nouvelle erreur emise par le code doit apparaitre ici
avant le prochain commit.

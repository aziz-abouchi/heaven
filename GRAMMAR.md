# 📜 Spécification Formelle de la Grammaire Heaven (EBNF)

Ce document définit la grammaire formelle du langage de programmation **Heaven**. Il est généré en miroir exact de `vendor/tree-sitter-heaven/grammar.js` et sert de référence unique pour le parser Zig, les outils de développement (LSP, formateurs) et la documentation.

## 1. Notation EBNF utilisée
- `::=` : "est défini comme"
- `|` : choix alternatif (OU)
- `[ ... ]` : optionnel (0 ou 1 fois)
- `{ ... }` : répétition (0 ou plusieurs fois)
- `( ... )` : groupement
- `"..."` : chaîne de caractères littérale (terminal)

---

## 2. Structure du Programme

Program       ::= { Declaration | Comment }
Declaration   ::= FnDecl | DataDecl | TypeAlias | ModuleDecl | ExportDecl | TheoremDecl | EffectDecl | ActorDecl | ...
Comment       ::= "--" { any character except newline } newline
                | "//" { any character except newline } newline
                | "/*" { any character } "*/"

---

## 3. Expressions (Le cœur du langage)

Expr          ::= LambdaExpr 
                | ForExpr 
                | IfExpr 
                | MatchExpr 
                | CallExpr 
                | MemberExpr 
                | IndexExpr 
                | BinaryExpr 
                | Literal 
                | Identifier

/* Abstraction (Fonction anonyme) - 3 styles supportés */
LambdaExpr    ::= "λ" Identifier "." Expr                  /* Style 1: λx. body */
                | "\" Identifier "." Expr                 /* Style 1 bis: \x. body */
                | "λ" Identifier ("=>" | "→") Expr         /* Style 2: λx => body */
                | "\" Identifier ("=>" | "→") Expr        /* Style 2 bis: \x => body */
                | ("λ" | "\" | "fn") "(" [ Param { "," Param } ] ")" ("=>" | "→") Expr /* Style 3: λ(x) => body */

/* Compréhension (Désucrage en map/filter dans le parser Zig) */
ForExpr       ::= "(" "for" "(" Identifier "<-" Expr ")" [ "(" "when" Expr ")" ] Expr ")"

/* Conditionnelle */
IfExpr        ::= "if" Expr "then" Expr "else" Expr

/* Application et Accès */
CallExpr      ::= Expr "(" [ Expr { "," Expr } ] ")"
MemberExpr    ::= Expr ( "." | "::" ) Identifier
IndexExpr     ::= Expr "[" Expr "]"

/* Opérateurs Binaires (par ordre de précédence croissante) */
BinaryExpr    ::= Expr "within" Expr
                | Expr ("or" | "||" | "∨") Expr
                | Expr ("and" | "&&" | "∧") Expr
                | Expr ("==" | "!=" | "≡" | "≢") Expr
                | Expr ("<" | ">" | "<=" | ">=" | "≤" | "≥" | "∈" | "∉" | "⊂" | "⊃" | "≃") Expr
                | Expr ("++" | "∘" | "<>") Expr
                | Expr ("+" | "-") Expr
                | Expr ("*" | "/" | "%" | "×" | "÷") Expr
                | Expr ">>=" Expr
                | Expr ">>" Expr

---

## 4. Déclarations Clés

/* Définition de fonction avec motif et garde optionnelle */
FnDecl        ::= Identifier PatternList [ "|" GuardExpr ] "=" Expr

/* Définition de type de données (Algébrique / GADT) */
DataDecl      ::= "data" Identifier { TypeVar } "=" Constructor { "|" Constructor }

/* Types et Alias */
TypeAlias     ::= "type" Identifier "=" TypeExpr
ForallType    ::= ("forall" | "∀") { Identifier } "." TypeExpr

---

## 5. Notes d'Implémentation et Synchronisation

1. **Parser Zig vs Tree-sitter** : 
   - Le parser Zig (`src/core/parse.zig`) implémente la logique de désucrage pour `ForExpr` (traduction en `map`/`filter`) et gère nativement le slicing UTF-8 du caractère `λ` (2 octets).
   - Le Tree-sitter (`vendor/tree-sitter-heaven/grammar.js`) fournit l'AST brut et la coloration syntaxique. Les deux sont désormais **parfaitement synchronisés** sur la syntaxe des lambdas et des compréhensions.

2. **S-Expressions** : Le cœur de l'évaluation repose sur des S-Expressions imbriquées `(f a b)`, ce qui simplifie l'unification et la réécriture via les E-Graphs.

*Document maintenu en synchronisation avec `vendor/tree-sitter-heaven/grammar.js` et `src/core/parse.zig`.*

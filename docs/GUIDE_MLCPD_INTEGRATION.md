# Guide MLCPD - Preuve d'Equivalence Inter-Langages

## Architecture

1. Parsing JSON MLCPD
2. Normalisation cross-langage (booleans, snake_case)
3. Conversion en Expr IR Heaven (lambda calcul type)
4. Inference de types avec contexte
5. Normalisation WHNF
6. Comparaison structurelle
7. Generation de certificat de preuve

## Format JSON MLCPD

Champs requis :
- "snippet" (PAS "text") : contenu du noeud
- "semantic_role" ou "role" : role semantique
- "children_start", "children_count" : indices enfants

## Roles supportes

- function_decl, parameter_decl
- identifier_expr, literal_expr, binary_expr
- if_stmt, return_stmt, block_stmt

## Utilisation REPL

heaven> :equiv 2 + 3 == 5
heaven> :prove file1.json file2.json
heaven> :help

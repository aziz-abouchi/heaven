# Exemples d'Equivalence

## Exemple 1: is_adult (Python vs Java)

Python: def is_adult(age): return age >= 18
Java: boolean isAdult(int age) { return age >= 18; }
Resultat: equivalent=true, strategy=congruence

## Exemple 2: Litteraux

Python: 42
Java: 42
Resultat: equivalent=true, strategy=congruence

## Patterns d'equivalence

- True/true -> equivalent
- isAdult/is_adult -> equivalent (snake_case)
- >=/==/&&/|| -> equivalent entre langages

#!/bin/bash

gen() {
	echo "$1" > /tmp/_t.hvn
	CC=gcc tree-sitter parse /tmp/_t.hvn | sed -E 's/ [[0-9]+, [0-9]+] - [[0-9]+, [0-9]+]//g'
}

SEP="================================================================================" DASH="--------------------------------------------------------------------------------"

write_test() {
	local file="$1" name="$2" code="$3"
	printf '%s\n%s\n%s\n\n%s\n\n%s\n\n%s\n\n' "$SEP" "$name" "$SEP" "$code" "$DASH" "$(gen "$code")" >> "test/corpus/$file"
}

rm -f test/corpus/*.txt

write_test core.txt "Simple function" 'fn add(a: i64, b: i64) -> i64 { return a + b; }'
write_test core.txt "Public function" 'pub fn main() { let x = 42; }'
write_test core.txt "Struct" 'struct Point { x: f64, y: f64, }'
write_test core.txt "For loop" 'fn t() { for i in 0..10 { print(i); } }'
write_test core.txt "Atom" 'fn t() { let s = :ok; }'
write_test core.txt "Lambda" 'fn t() { let f = |x| { x + 1 }; }'
write_test effects.txt "Effect" 'effect State<S> { fn get() -> S; fn put(s: S) -> (); }'
write_test effects.txt "Perform" 'fn t() { let x = perform get(); }'
write_test logic.txt "Fact" 'fact parent(tom, bob).'
write_test logic.txt "Rule" 'rule ancestor(X, Y) :- parent(X, Y).'
write_test logic.txt "Query" 'query ancestor(tom, Who)?'
write_test temporal.txt "After" 'fn t() { after 5s { cleanup(); } }'
write_test temporal.txt "Timeout" 'fn t() { timeout 100ms { risky(); } or_else { fallback(); } }'
write_test meta.txt "Macro" 'macro unless(cond) { if not(cond) { return true; } }'
write_test meta.txt "Rewrite" 'rewrite { match: bubble_sort(x), replace: merge_sort(x), }'
echo ─── More core ───
write_test core.txt "While loop" 'fn t() { while x > 0 { x -= 1; } }'
write_test core.txt "If else" 'fn t() { if x > 0 { return x; } else { return 0; } }'
write_test core.txt "Match" 'fn t() { match x { 0 => { return 1; }, _ => { return 0; }, } }'
write_test core.txt "Spawn send" 'fn t() { let pid = spawn Counter(0); pid ! Increment(); }'
write_test core.txt "Await" 'fn t() { let d = await fetch("url"); }'
write_test core.txt "If expr" 'fn t() { let x = if a > b then a else b; }'
write_test core.txt "Pipe" 'fn t() { let r = data |> map(f) |> sum; }'
write_test core.txt "Math sum" 'fn t() { let s = ∑(1, 100, i); }'
write_test core.txt "Duration" 'fn t() { let t = 100ms; }'
write_test core.txt "Unit lit" 'fn t() { let e = 0.5J; }'
write_test core.txt "Index" 'fn t() { let x = data[0]; }'
write_test core.txt "Return" 'fn t() { return 42; }'
write_test core.txt "Impl" 'impl Point { fn dist(self) -> f64 { return 0.0; } }'
write_test core.txt "Enum" 'enum Shape { Circle(f64), }'

echo ─── Equational ───
write_test equational.txt "Signature" 'total sum : [i64] -> i64'
write_test equational.txt "Equation" 'sum [] = 0'
write_test equational.txt "Type alias" 'type Genome = i64;'

echo ─── Typeclasses ───
write_test typeclasses.txt "Category" 'category Cat { id : forall a . a -> a }'
write_test typeclasses.txt "Functor" 'functor F : Cat -> Cat { map_ob : Type -> Type }'

echo ─── Proofs ───
write_test proofs.txt "Axiom" 'axiom add_zero<N> : Nat;'

echo ─── HoTT ───
write_test hott.txt "HIT" 'HIT Circle { base : Circle, loop_path : Path Circle base base, }'

echo ─── Actors ───
write_test actors.txt "Supervisor" 'supervisor Pool { strategy: :one_for_one, max_restarts: 5, }'

echo ─── Scheduler ───
write_test scheduler.txt "Scheduler" 'scheduler EB implements ES { strategy: :energy_steal, sample_rate: 50ms, }'

echo ─── Tests ───
write_test tests.txt "Simple test" 'test "add" { let r = add(1, 2); assert r == 3; }'
write_test tests.txt "Verify" 'verify sort_fn with [100, 1000] as n { assert scaling == :linear; }'

echo ─── Probabilistic ───
write_test probabilistic.txt "Sample" 'fn t() { let x = sample(normal(0.0, 1.0)); }'

echo ─── Contracts ───
write_test contracts.txt "Sensor" 'sensor Thermal : TemperatureSource'

echo ─── Energy ───
write_test energy.txt "Profile" 'profile "pipeline" { let data = read_file("large.csv"); }'

echo ─── Narrative ───
write_test narrative.txt "Explain" 'explain energy_steal { for :newcomer { style: :metaphor, detail: :low, } }'

echo ─── Transpiler ───
write_test transpiler.txt "Registry" 'registry Languages { python: python_def, rust: rust_def, }'
write_test transpiler.txt "Pipeline" 'pipeline Ingest : RawData ~> IndexedData { parse : RawData -> ParsedData }'

echo ─── FFI ───
write_test ffi.txt "Vessel" 'vessel WasmModule from "module.wasm" { export add(a: i32, b: i32) -> i32; }'

echo ─── Distributed ───
write_test distributed.txt "Dist fn" 'distributed fn remote(data: [i64]) -> i64 { return sum(data); }'

echo "Generated $(ls test/corpus/*.txt | wc -l) files" 

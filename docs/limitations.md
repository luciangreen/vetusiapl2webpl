# Limitations and Safe Fallbacks — vetusiapl2webpl (Stage 16)

## Overview

`vetusiapl2webpl` is a source-to-source compiler from terminal Prolog to
SWI-Prolog HTTP server programs.  Not every Prolog construct maps cleanly
to the stateless HTTP request/response model.  This document lists all
known hard cases, the warning system used to report them, and the fallback
strategy applied when a construct cannot be converted safely.

---

## Warning System

When the converter encounters an unsupported or partially-supported
construct it emits warnings in **two places**:

1. **Terminal output** — a `print_message(warning, ...)` message is
   written to the standard error stream at conversion time.  All Stage 16
   messages are prefixed with `[vetusiapl2webpl Stage 16]`.

2. **Generated code comments** — a `%% UNSUPPORTED:` or `%% TODO:` comment
   is inserted directly above the generated HTTP handler clause that
   contains the problematic goal.  This makes unsupported constructs
   immediately visible to anyone reading the generated file.

The warning system is implemented in `src/control_flow_transformer.pl`
(issue detection and `print_message` hooks) and `src/continuation_extractor.pl`
(comment emission in `write_cont_step/3`).

---

## Fallback Strategy

The converter follows a **safe pass-through** fallback for every unsupported
construct:

* The problematic goal is **emitted unchanged** into the generated handler
  clause body.  Conversion does not abort.
* An `%% UNSUPPORTED:` comment is placed above the clause explaining why the
  goal may behave differently in the HTTP context.
* A terminal warning is printed at conversion time via `print_message`.
* The developer is responsible for reviewing and correcting the flagged goals
  before deploying the generated server.

This strategy ensures that:
- Conversion **never silently generates incorrect handlers**.
- Every unsupported construct is **clearly marked** in both terminal output
  and generated code.
- The generated file is **syntactically valid** Prolog and can be loaded and
  inspected even when it contains unsupported goals.

---

## Preservation Classes

Each construct is classified as one of:

| Class | Meaning |
|-------|---------|
| `fully_preserved` | Semantics identical in the web version |
| `approximately_preserved(Reason)` | Semantics similar; `%% TODO:` comment emitted |
| `not_preserved(Reason)` | Semantics may differ; `%% UNSUPPORTED:` comment emitted |

---

## Known Hard Cases

### 1. Dynamic Meta-Calls — `call(Pred, Arg)`

**Issue kind:** `dynamic_meta_call`

`call/N` goals whose principal functor is a Prolog variable at conversion
time (e.g. `call(Pred, X)`) cannot be statically analysed.  The converter
cannot determine whether the called goal contains any I/O checkpoints or
unsupported side effects.

**Fallback:** goal passes through unchanged.  
**Warning:** terminal + `%% UNSUPPORTED:` comment.

---

### 2. Arbitrary `call/1` Chains — `call(Goal)`

**Issue kind:** `arbitrary_call_chain`

`call(Goal)` where `Goal` is a Prolog variable or a complex term built at
runtime (rather than a plain atom) cannot be statically resolved.  This
includes patterns such as:

```prolog
G = foo(X),
call(G)
```

**Fallback:** goal passes through unchanged.  
**Warning:** terminal + `%% UNSUPPORTED:` comment.

---

### 3. Runtime-Generated Goals — `T =.. L`

**Issue kind:** `runtime_generated_goal`

Goals constructed via `(=..)/2` (univ), `functor/3`, or `arg/3` and then
executed with `call/1` cannot be analysed by the static converter.
Example:

```prolog
Goal =.. [Name | Args],
call(Goal)
```

**Fallback:** the `=..` goal passes through unchanged; subsequent `call`
will also be flagged if it wraps a variable.  
**Warning:** terminal + `%% UNSUPPORTED:` comment.

---

### 4. Dynamic Database Mutation — `assert`/`retract`/`abolish`

**Issue kind:** `dynamic_database_mutation`

Affected predicates: `assert/1`, `asserta/1`, `assertz/1`, `retract/1`,
`retractall/1`, `abolish/1`.

These predicates modify the SWI-Prolog in-process database.  In a terminal
program each run starts with a fresh process, so mutations are confined to
that run.  In an HTTP server the same process services many concurrent
requests; a mutation made in one request is visible to all subsequent
requests.  This breaks the expected per-session isolation.

**Fallback:** goal passes through unchanged.  
**Warning:** terminal + `%% UNSUPPORTED:` comment.  
**Recommended fix:** replace with session-scoped state (e.g. use the
`http_session` library or pass state as hidden form fields).

---

### 5. Complex Stream Manipulation — `open`/`close`/stream I/O

**Issue kind:** `complex_stream_manipulation`

Affected predicates: `open/3`, `open/4`, `close/1`, and any predicate that
reads from or writes to a named stream handle.

Stream handles are OS-level file descriptors scoped to the process.  They
cannot be serialised into HTTP form fields and therefore cannot survive the
boundary between one HTTP request and the next.  A stream opened in one
handler step will not be available in subsequent steps.

**Fallback:** goal passes through unchanged.  
**Warning:** terminal + `%% UNSUPPORTED:` comment.  
**Recommended fix:** open and close streams within a single handler step,
or use file-level I/O that does not require handle persistence.

---

### 6. Terminal-Timing Side Effects

**Issue kind:** `terminal_side_effects`

Affected predicates: `halt/0`, `halt/1`, `sleep/1`, `nb_setval/2`,
`nb_getval/2`, `b_setval/2`, `b_getval/2`.

These predicates carry process-level or terminal-program-lifetime semantics
that do not map to the stateless HTTP model:

* **`halt/0-1`** — terminates the entire SWI-Prolog process, taking down
  the HTTP server and all active sessions.
* **`sleep/1`** — blocks the calling thread; in an HTTP server this ties up
  a handler thread and may starve other requests.
* **`nb_setval/nb_getval`**, **`b_setval/b_getval`** — global mutable
  variables are shared across all HTTP sessions, breaking per-user isolation.

**Fallback:** goal passes through unchanged.  
**Warning:** terminal + `%% UNSUPPORTED:` comment.  
**Recommended fix:** remove `halt` calls; replace global variables with
session-scoped state.

---

### 7. Exception Handling — `catch`/`throw`

**Issue kind:** `exception_handling`  
**Preservation class:** `not_preserved`

`catch/3` and `throw/1` survive in the generated handler body but their
interaction with the SWI-Prolog HTTP server dispatcher is unverified.
An uncaught exception in a handler body may produce a 500 error page rather
than being handled as intended.

**Fallback:** goal passes through unchanged.  
**Warning:** terminal warning via `print_message`.

---

### 8. Negation-as-Failure over Goals with Side Effects — `\+`

**Issue kind:** `negation_as_failure`  
**Preservation class:** `approximately_preserved`

`\+(G)` is safe when `G` is a pure relational test (e.g. `\+(X = Y)`).
When `G` has side effects (output, I/O, database mutation) those effects
will be suppressed on failure and not rolled back on success, which may
differ from terminal behaviour.

**Fallback:** goal passes through unchanged.  
**Warning:** terminal warning when `G` is not a recognised pure test.

---

### 9. Cut — `!`

**Issue kind:** `cut_sequential` / `cut_in_branch`  
**Preservation class:** `approximately_preserved`

HTTP handlers are deterministic by design — there are no open choice points
within a handler clause — so a bare cut has no observable effect.  A
`%% TODO:` comment is emitted to alert the developer.

---

## Constructs That Are Fully Preserved

The following are converted correctly with no warnings:

| Construct | Notes |
|-----------|-------|
| Conjunction `(A, B)` | Goal order maintained |
| If-then-else `(C -> T ; E)` | Mapped to inline conditional in handler |
| If-then `(C -> T)` | Mapped to conditional with empty else |
| Direct recursion / retry loop | Compiled to HTTP redirect back to landing-pad |
| `read_string/5` | Converted to HTML form step (the primary use case) |
| `read_password/1-2` | Converted to password-type HTML input |
| `writeln/1`, `write/1`, `nl`, `format/1-2`, `print/1` | Converted to HTML paragraph/span output |
| Pure arithmetic and relational goals | Passed through as compute goals |

---

## Summary Table

| Issue Kind | Source Construct | Preservation | Comment Marker |
|---|---|---|---|
| `dynamic_meta_call` | `call(Var, Arg)` | not_preserved | `%% UNSUPPORTED:` |
| `arbitrary_call_chain` | `call(VarOrComplex)` | not_preserved | `%% UNSUPPORTED:` |
| `dynamic_database_mutation` | `assert/retract/abolish` | not_preserved | `%% UNSUPPORTED:` |
| `complex_stream_manipulation` | `open/close` | not_preserved | `%% UNSUPPORTED:` |
| `runtime_generated_goal` | `T =.. L` | not_preserved | `%% UNSUPPORTED:` |
| `terminal_side_effects` | `halt/sleep/nb_setval/…` | not_preserved | `%% UNSUPPORTED:` |
| `exception_handling` | `catch/throw` | not_preserved | terminal warning only |
| `negation_as_failure` | `\+(NonPureGoal)` | approximately_preserved | terminal warning |
| `cut_sequential` | `!` in sequence | approximately_preserved | `%% TODO:` |
| `cut_in_branch` | `!` inside branch | approximately_preserved | `%% TODO:` |

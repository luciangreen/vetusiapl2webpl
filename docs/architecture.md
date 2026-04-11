# Architecture — vetusiapl2webpl

## Overview

`vetusiapl2webpl` is a source-to-source compiler written in SWI-Prolog.
It reads a *terminal* Prolog program that interacts with the user via
`read_string/5`, and emits an equivalent *web* Prolog program that runs as
an SWI-Prolog HTTP server, replacing each `read_string` interaction with an
HTML form round-trip.

The compiler is organised into two stages:

| Stage | Module | Responsibility |
|-------|--------|----------------|
| **Stage 2** | `src/reader.pl` | Read the source file; normalise every clause into a tagged internal representation |
| **Stage 3+** | `src/vetusiapl2webpl.pl` | Transform the normalised representation into an HTTP server program |

---

## Stage 2 — Input Program Reader and Normaliser (`src/reader.pl`)

### Purpose

Stage 2 loads the source program from disk and converts it into a
traversable data structure without performing any semantic reinterpretation.
The result is a list of *normalised clause* terms.

### Normalised clause forms

| Term | Meaning |
|------|---------|
| `norm_clause(Head, NormBody, VarNames)` | A regular clause (rule or fact).  For a fact `NormBody = norm_true`. |
| `directive(Goal)` | A top-level directive (`:- Goal`). |

### Normalised body forms (`NormBody`)

| Term | Source construct |
|------|-----------------|
| `norm_true` | `true` or empty body |
| `norm_cut` | `!` |
| `norm_conj(A, B)` | conjunction `(A , B)` |
| `norm_disj(A, B)` | disjunction `(A ; B)` |
| `norm_if_then(Cond, Then)` | soft-cut `(Cond -> Then)` |
| `norm_if_then_else(Cond, Then, Else)` | if-then-else `(Cond -> Then ; Else)` |
| `norm_read_string(S, Sents, Pad, Len, Var)` | `read_string/5` |
| `norm_read_password(Prompt, Var)` | `read_password/2` |
| `norm_read_password(Var)` | `read_password/1` |
| `norm_output(Goal)` | any recognised terminal-output predicate |
| `norm_goal(Goal)` | any other goal |

### Public API

```prolog
read_and_normalise(+File, -NormClauses)   % read file → normalised list
normalise_clause(+Term, +VarNames, -Norm) % normalise one raw term
normalise_body(+Body, -NormBody)          % normalise one clause body
is_output_goal(+Goal)                     % recognise output predicates
```

### Detection coverage

Stage 2 detects and tags:

- **predicates / clauses** — every term is wrapped in `norm_clause/3` or
  `directive/1`
- **conjunctions** — `norm_conj/2`
- **disjunctions** — `norm_disj/2`
- **if-then-else** — `norm_if_then_else/3` (checked before bare disjunction)
- **if-then** — `norm_if_then/2`
- **cuts** — `norm_cut`
- **`read_string/5`** — `norm_read_string/5`
- **`read_password/1-2`** — `norm_read_password/1-2`
- **terminal output** — `norm_output/1` (covers `write/1`, `writeln/1`,
  `nl`, `format/1-2`, `writef/2`, `print/1`)

Variable names (the `Name = Var` association list from `read_term/3`) are
preserved inside each `norm_clause` for use by later stages.

---

## Pipeline (Stage 3+ — vetusiapl2webpl.pl)

```
Input .pl file
      │
      ▼
 read_source/2          — read_term/3 + variable_names option
      │  list of (Term, VarNames) pairs
      ▼
  find_main/4           — locate the main/0 clause
      │  Body (Prolog conjunction), VarNames list
      ▼
 conjunction_to_list/2  — flatten conjunction → [Goal, ...]
      │
      ▼
 split_at_reads/3       — partition at every read_string/5 call
      │  [seg(Goals, ReadVarName), ...]
      ▼
 annotate_accumulated/3 — add accumulated-variable lists to each segment
      │  [seg(Goals, ReadVarName, AccVarNames), ...]
      ▼
 write_web_program/4    — emit the SWI-Prolog HTTP server file
      │
      ▼
Output .pl file
```

---

## Key Data Structures

### `(Term, VarNames)` pair

Returned by `read_source/2`.  `Term` is a Prolog term (clause or directive).
`VarNames` is the `Name = Var` list returned by
`read_term/3` with the `variable_names/1` option — it maps source-level
variable names (atoms) to actual Prolog logical variables shared with `Term`.

### `seg(Goals, ReadVarName, AccVarNames)`

One *step segment* produced by `annotate_accumulated/3`.

| Field | Type | Meaning |
|-------|------|---------|
| `Goals` | `list(goal)` | Goals that execute during this step (before the `read_string` call, if any) |
| `ReadVarName` | `atom \| none` | Name of the variable captured by the trailing `read_string`, or `none` for the last segment |
| `AccVarNames` | `list(atom)` | Names of all variables captured by *previous* `read_string` calls — these must be threaded forward via hidden form fields and `http_parameters/2` |

---

## Conversion Rules

### Output goals → HTML terms

| Terminal goal | HTML term (inside `reply_html_page/2`) |
|---------------|----------------------------------------|
| `writeln(X)` | `p(X)` |
| `write(X)` | `span(X)` |
| `nl` | `br([])` |
| `print(X)` | `p(X)` |
| `format(Fmt, Args)` | kept as-is in the result step (raw format output); simplified `p(Fmt)` in intermediate steps |
| `format(Fmt)` | `p(Fmt)` |

### `read_string` → form step

Each occurrence of

```prolog
read_string(Stream, Sentinel, Padding, _, VarName)
```

becomes:

1. An `<input type="text" name="VarName">` field in the *current* step's
   HTML form.
2. An `http_parameters(Request, ['VarName'(VarName, [atom])])` call at the
   start of the *next* step's handler.

### Variable threading

Variables captured by earlier `read_string` calls are passed forward as:

* **Hidden form fields** in the emitted HTML form:
  `input([type=hidden, name='VarName', value=VarName])`

* **HTTP parameters** extracted at the top of each subsequent handler:
  `http_parameters(Request, ['VarName'(VarName, [atom]), ...])`

The variable names (atoms) are taken directly from the `variable_names`
metadata read alongside the original clause.

---

## Generated File Structure

```prolog
%% Generated by vetusiapl2webpl ...

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_parameters)).

:- http_handler(root(.), step_0, []).
:- http_handler(root(step_1), step_1, [method(post)]).
...

:- initialization(main, main).
main :- http_server(http_dispatch, [port(8080)]).

step_0(_Request) :-
    reply_html_page(title('Step 0'),
        [ form([method=post, action='/step_1'], [...]) ]).

step_1(Request) :-
    http_parameters(Request, ['Var1'(Var1, [atom])]),
    reply_html_page(title('Step 1'),
        [ form([method=post, action='/step_2'],
               [ input([type=hidden, name='Var1', value=Var1]), ...]) ]).

step_N(Request) :-      % final step
    http_parameters(Request, [...]),
    format('Content-type: text/html\n\n'),
    format('<html><body>\n'),
    ...,                % original output goals (writeln → format('<p>~w</p>'))
    format('</body></html>\n').
```

---

## Module and File Layout

```
vetusiapl2webpl/
├── src/
│   ├── reader.pl            ← Stage 2: source reader and normaliser
│   └── vetusiapl2webpl.pl   ← Stage 3+: converter module (entry point: convert/2)
├── examples/
│   ├── input_example.pl     ← sample terminal Prolog input
│   └── output_example.pl    ← reference web Prolog output
├── tests/
│   ├── test_reader.pl       ← Stage 2 plunit test suite
│   └── test_vetusiapl2webpl.pl  ← Stage 3+ plunit test suite
├── docs/
│   └── architecture.md      ← this document
├── output/                  ← default directory for generated files
├── README.md
└── LICENSE
```

---

## Extending the Converter

### Adding new output-goal patterns

Add a clause to `is_output_goal/1` and a matching clause to
`goal_to_html_term/2` in `src/vetusiapl2webpl.pl`.

### Handling auxiliary predicates

Non-main, non-directive clauses from the input are passed through unchanged
by `emit_aux_clauses/2`.  They appear at the bottom of the generated file
and can be called from any handler step.

### Supporting `read_term` and other input predicates

Extend `split_at_reads_/4` to recognise additional input predicates
(e.g. `read_term/2`, `read/1`) alongside `read_string/5`.

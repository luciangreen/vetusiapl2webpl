# Architecture — vetusiapl2webpl

## Overview

`vetusiapl2webpl` is a source-to-source compiler written in SWI-Prolog.
It reads a *terminal* Prolog program that interacts with the user via
`read_string/5`, and emits an equivalent *web* Prolog program that runs as
an SWI-Prolog HTTP server, replacing each `read_string` interaction with an
HTML form round-trip.

The compiler is organised into three stages:

| Stage | Module | Responsibility |
|-------|--------|----------------|
| **Stage 2** | `src/reader.pl` | Read the source file; normalise every clause into a tagged internal representation |
| **Stage 3** | `src/checkpoint_detector.pl` | Detect web conversion points (checkpoints) — one per input goal — and capture the surrounding metadata needed by the code generator |
| **Stage 4+** | `src/vetusiapl2webpl.pl` | Transform the normalised representation into an HTTP server program |

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

## Stage 3 — Web Conversion Point Detector (`src/checkpoint_detector.pl`)

### Purpose

Stage 3 analyses a normalised clause body and identifies every *input goal*
(`norm_read_string` or `norm_read_password`) as a **checkpoint** — a point
where the terminal program pauses for user input and the web converter must
insert an HTML form page boundary.

For each checkpoint the module captures all metadata required by the code
generator:

* **unique ID** — positive integer assigned in left-to-right, depth-first order
* **kind** — `read_string` or `read_password`
* **variable name** — the atom from the `VarNames` list (or `anon`)
* **prompts** — `norm_output/1` goals accumulated since the previous checkpoint
  (shown as HTML content on the form page)
* **continuation** — the normalised body that executes *after* this checkpoint
* **live variables** — names of variables bound by previous reads that appear
  free in the continuation (must be threaded forward as hidden form fields)
* **context** — the surrounding control-flow structure

### Checkpoint term structure

```prolog
checkpoint(Id, Kind, VarName, Prompts, Continuation, LiveVars, Context)
```

| Field | Type | Meaning |
|-------|------|---------|
| `Id` | positive integer | Unique identifier, assigned left-to-right depth-first (1, 2, …) |
| `Kind` | `read_string` \| `read_password` | Source of the user input |
| `VarName` | atom \| `anon` | Name of the receiving variable |
| `Prompts` | `list(norm_output/1)` | Output goals displayed before the input on this form page |
| `Continuation` | `NormBody` | Normalised body executed after this checkpoint |
| `LiveVars` | `list(atom)` | Variable names from `VarNames` that were bound by earlier reads and appear free in `Continuation` |
| `Context` | atom \| compound | Surrounding control flow (see below) |

### Context values

| Value | Meaning |
|-------|---------|
| `sequential` | Plain straight-line conjunction |
| `menu` | Inside an arm of a disjunction `(A ; B)` |
| `branch` | Inside the `Then` or `Else` arm of an if-then(-else) |
| `loop(F/A)` | Inside a branching construct (disjunction or if-then-else) where at least one arm contains a recursive call to predicate `F/A` (requires the optional `ClauseHead` argument to `detect_checkpoints/4`) |

### Public API

```prolog
detect_checkpoints(+NormBody, +VarNames, -Checkpoints)
    % Detect all checkpoints in NormBody (no loop detection).

detect_checkpoints(+NormBody, +VarNames, +ClauseHead, -Checkpoints)
    % Like above; ClauseHead = F/A enables loop(F/A) context detection.

collect_live_vars(+Term, +VarNames, -LiveVarNames)
    % Utility: find all named vars from VarNames that appear free in Term.
```

### Detection coverage

* **`norm_read_string/5`** — detected as `Kind = read_string`
* **`norm_read_password/1-2`** — detected as `Kind = read_password`
* **`norm_disj/2`** — arms get `menu` context
* **`norm_if_then/2`** — Then arm gets `branch` context
* **`norm_if_then_else/3`** — Then and Else arms get `branch` context
* **Recursive calls** — any of the above become `loop(F/A)` when another arm
  contains `norm_goal(Call)` with `functor(Call, F, A)` matching `ClauseHead`

---

## Pipeline (Stage 4+ — vetusiapl2webpl.pl)

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
│   ├── reader.pl                ← Stage 2: source reader and normaliser
│   ├── checkpoint_detector.pl   ← Stage 3: web conversion point detector
│   ├── continuation_extractor.pl← Stage 4: continuation extraction engine
│   ├── web_server_generator.pl  ← Stage 5: web server skeleton generator
│   └── vetusiapl2webpl.pl       ← original single-module converter (convert/2)
├── examples/
│   ├── input_example.pl         ← sample terminal Prolog input
│   └── output_example.pl        ← reference web Prolog output
├── tests/
│   ├── test_reader.pl               ← Stage 2 plunit test suite
│   ├── test_checkpoint_detector.pl  ← Stage 3 plunit test suite
│   ├── test_continuation_extractor.pl ← Stage 4 plunit test suite
│   └── test_web_server_generator.pl ← Stage 5 plunit test suite
├── docs/
│   └── architecture.md          ← this document
├── output/                      ← default directory for generated files
├── README.md
└── LICENSE
```

---

## Stage 5 — Web Server Skeleton Generator (`src/web_server_generator.pl`)

### Purpose

Stage 5 ties together the complete conversion pipeline (Stages 2–4) and
emits a **standalone, runnable SWI-Prolog HTTP server program** from a
terminal Prolog source file.

Key additions over the raw Stage 4 output:

* A configurable **`vetusia_server(Port)`** entry predicate so users can
  start the server on any port without editing the generated file.
* A **`main/0`** predicate that calls `vetusia_server/1` with a default port
  (supplied to `generate_web_server/3`, default 8080).
* An **`:- initialization(main, main)`** directive so the generated file is
  immediately runnable with `swipl <file>`.
* All five required HTTP libraries are imported.
* **Auxiliary clauses** from the input program (non-main, non-directive
  clauses) are reconstructed from the normalised form and appended at the
  bottom of the generated file.
* No JavaScript is used for control flow or input handling.

### Generated file structure

```prolog
%% Generated by vetusiapl2webpl — web_server_generator

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_header)).

:- http_handler(root(.), step_0, []).          % root GET handler
:- http_handler(root(step_1), step_1, [method(post)]).
...

vetusia_server(Port) :-
    http_server(http_dispatch, [port(Port)]).

:- initialization(main, main).

main :- vetusia_server(8080).   % default port; override via vetusia_server/1

step_0(_Request) :- ...         % landing page — renders first form
step_1(Request)  :- ...         % POST handler for continuation step 1
...
<auxiliary clauses from input>
```

### Public API

```prolog
generate_web_server(+InputFile, +OutputFile)
    % Convert InputFile to a web server in OutputFile (port 8080).

generate_web_server(+InputFile, +OutputFile, +Port)
    % Like above; main/0 starts the server on Port.
```

### Pipeline

```
InputFile
    │
    ▼
read_and_normalise/2          (Stage 2)
    │  list of norm_clause/directive
    ▼
wsg_find_main/4               (Stage 5)
    │  MainBody (NormBody), VarNames, AuxNorms
    ▼
detect_checkpoints/4          (Stage 3)
    │  list of checkpoint/7
    ▼
extract_continuations/4       (Stage 4)
    │  list of cont_step/4
    ▼
wsg_write_program/5           (Stage 5)
    │  → boilerplate + handler decls + vetusia_server/1 + main/0
    │  → maplist(write_cont_step/3) for each step handler
    │  → wsg_emit_aux_clauses/2 for auxiliary predicates
    ▼
OutputFile
```

---



### Adding new output-goal patterns

Add a clause to `is_output_goal/1` and a matching clause to
`goal_to_html_term/2` in `src/vetusiapl2webpl.pl`.

### Handling auxiliary predicates

Non-main, non-directive clauses from the input are passed through unchanged
by `emit_aux_clauses/2`.  They appear at the bottom of the generated file
and can be called from any handler step.

### Supporting `read_term` and other input predicates

Extend `is_input_goal/3` in `src/checkpoint_detector.pl` (Stage 3) and
`split_at_reads_/4` in `src/vetusiapl2webpl.pl` (Stage 4+) to recognise
additional input predicates (e.g. `read_term/2`, `read/1`) alongside
`read_string/5`.

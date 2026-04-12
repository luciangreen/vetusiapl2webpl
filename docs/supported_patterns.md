# Supported Patterns — vetusiapl2webpl

This document is a reference for every Prolog source pattern that
`vetusiapl2webpl` recognises, the HTML/HTTP construct it maps to, and
example code for each pattern.

---

## Table of Contents

1. [Sequential read_string calls](#1-sequential-read_string-calls)
2. [Output predicates before read_string](#2-output-predicates-before-read_string)
3. [Password input detection](#3-password-input-detection)
4. [Numbered menus → radio/select widgets](#4-numbered-menus--radioselect-widgets)
5. [If-then-else branching](#5-if-then-else-branching)
6. [Recursive retry loops](#6-recursive-retry-loops)
7. [Auxiliary predicates](#7-auxiliary-predicates)
8. [Directives and initialization](#8-directives-and-initialization)
9. [Pure computation goals](#9-pure-computation-goals)
10. [format/2 result output](#10-format2-result-output)
11. [read_password/1-2](#11-read_password12)
12. [Unsupported patterns](#12-unsupported-patterns)

---

## 1. Sequential read_string calls

**Pattern**: one or more `read_string/5` calls in a straight-line conjunction.

**Terminal**:
```prolog
main :-
    writeln('Enter your name:'),
    read_string(user, "\n", "\r", _, Name),
    writeln('Enter your age:'),
    read_string(user, "\n", "\r", _, Age),
    format("Hello, ~w! You are ~w years old.~n", [Name, Age]).
```

**Conversion**: one HTTP handler per `read_string`, plus a final result handler.

| Step | Method | What it does |
|------|--------|--------------|
| `step_0` | GET | Shows "Enter your name:" + text input for `Name` |
| `step_1` | POST | Receives `Name`, shows "Enter your age:" + text input for `Age`; carries `Name` as hidden field |
| `step_2` | POST | Receives `Name` and `Age`, renders the greeting |

**Key rule**: the variable name in the fifth argument of `read_string/5` (here
`Name` and `Age`) must be a named SWI-Prolog variable (not `_`).  It becomes
the `<input name="…">` attribute and the `http_parameters/2` key.

---

## 2. Output predicates before read_string

**Recognised output predicates**:

| Predicate | HTML on form pages | Result page |
|-----------|--------------------|-------------|
| `writeln(Text)` | `p(Text)` | `html_writeln(Text)` |
| `write(Text)` | `span(Text)` | `html_write(Text)` |
| `nl` | `br([])` | `html_br` |
| `format(Fmt)` | `p(Fmt)` | `format(Fmt)` (verbatim) |
| `format(Fmt, Args)` | `p(Fmt)` (simplified) | `format(Fmt, Args)` (verbatim) |
| `print(Text)` | `p(Text)` | `html_writeln(Text)` |
| `writef(Fmt, Args)` | `p(Fmt)` (simplified) | `writef(Fmt, Args)` (verbatim) |

All output goals that appear immediately before a `read_string` call become
`<p>` or `<span>` content inside the `reply_html_page/2` form for that step.

**HTML fragment pass-through**: if a `writeln/write` argument is a ground atom
that contains both `<` and `>`, the converter passes it through as raw HTML
rather than wrapping it:

```prolog
writeln('<h1>Welcome</h1>')  →  \(format('~w~n',['<h1>Welcome</h1>']))
writeln('Plain text')        →  p('Plain text')
```

---

## 3. Password input detection

**Pattern**: a `read_string/5` call whose fifth argument is a variable with a
name that contains the substring `password` (case-insensitive).

```prolog
read_string(user, "\n", "\r", _, Password)   % → <input type="password">
read_string(user, "\n", "\r", _, UserPass)   % → <input type="password">
read_string(user, "\n", "\r", _, Token)      % → <input type="text">
```

The detection is purely name-based; no semantic analysis is performed.

---

## 4. Numbered menus → radio/select widgets

**Pattern**: a sequence of `writeln` prompts that include `'N. Label'`-style
items (where N is an integer), followed by a `read_string`, followed by an
if-then-else chain whose conditions test the read variable against the string
values `"1"`, `"2"`, etc.

**Terminal**:
```prolog
writeln('1. Register'),
writeln('2. Login'),
writeln('3. Forgot Password'),
writeln('Enter choice (1/2/3):'),
read_string(user, "\n", "\r", _, Choice),
( Choice = "1" -> ...
; Choice = "2" -> ...
; Choice = "3" -> ...
; main                  % retry loop
).
```

**Conversion rules**:

| Number of choices | Widget emitted |
|-------------------|----------------|
| ≤ 4 | `input([type=radio, name='Choice', value="N"])` per option |
| ≥ 5 | `select` element with `option` children |

Each choice option also has its label emitted as a `<p>` element above the
widget so the user sees the full menu text.

---

## 5. If-then-else branching

**Pattern**: `(Cond -> Then ; Else)` in the clause body.  Nested chains of
`( C1 -> T1 ; C2 -> T2 ; ... ; Else )` are fully supported.

**Conversion**: the branching structure is preserved inside the HTTP handler
via a `cond_resp` internal representation that maps directly to nested
`( Cond -> reply_html_page(...) ; ... )` Prolog in the generated clause.
Each branch may direct the user to a *different* next step URL.

**Terminal**:
```prolog
( Choice = "1" ->
    writeln('Enter username:'),
    read_string(user, "\n", "\r", _, Username),
    ...
; Choice = "2" ->
    writeln('Enter email:'),
    read_string(user, "\n", "\r", _, Email),
    ...
).
```

**Generated** (`step_1`):
```prolog
step_1(Request) :-
    http_parameters(Request, [ 'Choice'(Choice_raw, [atom]) ]),
    state_deserialise(Choice_raw, Choice),
    (   Choice = "1"
    ->  reply_html_page(title('Form'),
            [ form([method=post, action='/step_2'],
                  [ p('Enter username:'), input([type=text, name='Username',...]),
                    input([type=submit, value='Next']) ]) ])
    ;   Choice = "2"
    ->  reply_html_page(title('Form'),
            [ form([method=post, action='/step_5'],
                  [ p('Enter email:'), input([type=text, name='Email',...]),
                    input([type=submit, value='Next']) ]) ])
    ).
```

**Condition goals** (`Choice = "1"`) are reproduced verbatim.  Any pure
relational goal is valid as a condition (arithmetic, unification, comparison).

---

## 6. Recursive retry loops

**Pattern**: a recursive call to the same predicate (`main/0` or another
predicate with the same functor/arity) inside the final `else` arm of a
branching construct.

```prolog
main :-
    ...
    ( ValidCondition -> handle
    ; writeln('Invalid. Try again.'), main   % ← recursive call
    ).
```

**Conversion**: the converter detects this pattern (context tag `loop(F/A)`)
and replaces the recursive call with an HTTP redirect:

```prolog
;   http_redirect(see_other, root(.), Request)
```

This sends the browser back to `step_0` (the landing page), which re-displays
the first form — the exact web equivalent of re-running `main/0`.

**Limitation**: only direct recursion to the same predicate in the final else
arm is detected.  Mutual recursion, `repeat/0`-based loops, and helper
predicates that call back into the main flow are not detected and pass through
with a warning.

---

## 7. Auxiliary predicates

**Pattern**: any clause in the source file whose head is not `main/0` and is
not a directive.

```prolog
validate_age(Age) :-
    atom_number(Age, N), N >= 0, N =< 120.

greet(Name, Age) :-
    format("Hello, ~w! You are ~w years old.~n", [Name, Age]).
```

**Conversion**: auxiliary predicates are passed through **verbatim** and
appended at the bottom of the generated file.  They can be called from any
handler step.  The converter does **not** apply continuation extraction to
auxiliary predicates — only the `main/0` clause is transformed.

---

## 8. Directives and initialization

**Pattern**: top-level directives in the source file.

| Directive | Treatment |
|-----------|-----------|
| `:- initialization(main, main).` | Replaced by `main :- vetusia_server(Port).` + `:- initialization(main, main).` |
| `:- use_module(...)` | Passed through verbatim |
| `:- module(...)` | Passed through verbatim |
| Any other directive | Passed through verbatim |

---

## 9. Pure computation goals

**Pattern**: any goal in the clause body that is neither an output predicate
nor a `read_string` call.

Examples:
```prolog
atom_number(Age, N),
N > 18,
succ(N, N1),
string_concat(First, Last, Full),
my_helper(X, Y)
```

**Conversion**: pure computation goals are collected into the `PreGoals` list
of the current `cont_step` and emitted verbatim at the top of the handler
body, before the HTML response is generated.

This means arithmetic, string operations, list processing, and user-defined
helper calls all survive conversion unchanged.

---

## 10. format/2 result output

**Pattern**: `format/2` (and `format/1`) calls in the *final* clause segment
(after the last `read_string`).

```prolog
format("Registered: ~w / ~w (email: ~w)~n", [Username, Password, Email])
```

**Conversion**: the format goal is kept verbatim in the result handler,
wrapped between `html_page_header('Result')` and `html_page_footer`:

```prolog
step_4(Request) :-
    http_parameters(Request, [...]),
    state_deserialise(...),
    html_page_header('Result'),
    format("Registered: ~w / ~w (email: ~w)~n", [Username, Password, Email]),
    html_page_footer.
```

The format string, argument list, and all variable bindings are preserved
exactly.

---

## 11. read_password/1-2

**Pattern**: `read_password/2` (prompt + variable) or `read_password/1`
(variable only) — a Vetusia-specific predicate for password input.

```prolog
read_password('Enter password: ', Password)
read_password(Password)
```

**Conversion**: treated identically to `read_string` but always produces
`<input type="password">` regardless of the variable name.

---

## 12. Unsupported patterns

The following patterns are **not converted** and pass through with warnings:

| Pattern | Warning kind |
|---------|-------------|
| `call(Var, Arg)` — variable as predicate | `dynamic_meta_call` |
| `call(Goal)` — variable/complex goal | `arbitrary_call_chain` |
| `T =.. L` followed by `call` | `runtime_generated_goal` |
| `assert/retract/abolish` | `dynamic_database_mutation` |
| `open/close` / stream handles | `complex_stream_manipulation` |
| `halt/0-1` | `terminal_side_effects` |
| `sleep/1` | `terminal_side_effects` |
| `nb_setval/nb_getval`, `b_setval/b_getval` | `terminal_side_effects` |
| `catch/throw` | `exception_handling` |
| `\+(G)` with side effects in `G` | `negation_as_failure` |
| `!` (cut) | `cut_sequential` / `cut_in_branch` |

Warnings appear as:

1. A `print_message(warning, …)` message on stderr during conversion,
   prefixed with `[vetusiapl2webpl Stage 16]`.
2. A `%% UNSUPPORTED:` or `%% TODO:` comment in the generated file above the
   affected handler clause.

The generated file remains syntactically valid Prolog and can be loaded and
inspected.  The developer is responsible for reviewing and correcting the
flagged goals before deploying the server.

For the full list of limitations and recommended fixes, see
[`docs/limitations.md`](limitations.md).

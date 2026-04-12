# vetusiapl2webpl — Vetusia Prolog-to-Web-Prolog Converter

`vetusiapl2webpl` takes a **terminal-based Prolog program** that uses
`read_string/5` for user input and converts it into a **SWI-Prolog HTTP
server program** that serves HTML pages — one page per `read_string`
interaction, with no JavaScript required.

---

## Table of Contents

1. [What the Converter Does](#what-the-converter-does)
2. [How Conversion Works](#how-conversion-works)
   - [read_string Page Cut-offs](#read_string-page-cut-offs)
   - [How Continuations Are Generated](#how-continuations-are-generated)
   - [How State Is Preserved](#how-state-is-preserved)
3. [Before-and-After Examples](#before-and-after-examples)
4. [Quick Start](#quick-start)
5. [Running the Generated Web Server](#running-the-generated-web-server)
6. [Known Limitations](#known-limitations)
7. [Recommended Coding Style](#recommended-coding-style)
8. [Running the Tests](#running-the-tests)
9. [Project Layout](#project-layout)
10. [Architecture](#architecture)
11. [PR Completion Criteria](#pr-completion-criteria)
12. [License](#license)

---

## What the Converter Does

`vetusiapl2webpl` is a **source-to-source compiler** written entirely in
SWI-Prolog.  It reads a terminal Prolog program — one that prompts the user
with `writeln/1` and reads responses with `read_string/5` — and emits an
equivalent web program that:

- Runs as a **SWI-Prolog HTTP server** on a configurable port (default 8080).
- Replaces each `read_string/5` call with an **HTML form** that collects the
  same value from the user's browser.
- Threads all captured variable values forward across HTTP requests using
  **hidden form fields** and `http_parameters/2`, with no session storage or
  cookies required.
- Converts `writeln/1`, `write/1`, `nl`, and `format/1-2` calls to HTML
  `<p>`/`<span>` elements.
- Preserves every non-I/O computation predicate verbatim.
- Recognises numbered menus and emits radio-button or dropdown widgets
  instead of free-text inputs.
- Detects `read_string` variables named `Password` (case-insensitive) and
  emits `<input type="password">` automatically.
- Detects recursive retry loops and replaces them with HTTP redirects.
- Generates a **fully self-contained** file — no runtime library files are
  needed alongside it; all helper predicates are inlined.

The converter requires only SWI-Prolog ≥ 8.x and has no other external
dependencies.

---

## How Conversion Works

### read_string Page Cut-offs

Every call to `read_string/5` in the terminal program is a **page cut-off
point** — a boundary where the browser must pause, display a form, and wait
for the user to submit it before the program can continue.

The converter inserts a cut-off at each such call because:

1. HTTP is **stateless and request-driven**: the server cannot pause mid-clause
   waiting for user input the way a terminal program can.
2. Each cut-off becomes a separate **HTTP POST handler** (`step_N`) in the
   generated server.
3. Everything that runs *before* the `read_string` in the original clause
   (the prompts, the computation goals) becomes the **body of the current
   handler** — it executes and renders an HTML form.
4. Everything that runs *after* the `read_string` (the continuation) moves
   into the **next handler**, which is invoked when the user submits the form.

In other words:

```
… goals before read_string …        →  executed in step_N; form rendered
read_string(user, "\n", "\r", _, V) →  HTML text input <input name="V">
… goals after read_string …         →  executed in step_(N+1) after submit
```

For a program with *k* `read_string` calls, the converter produces *k+1*
handler steps (step_0 … step_k).  Step_0 is a GET handler that shows the
first form; all others are POST handlers.

### How Continuations Are Generated

A **continuation** is the code that must run *after* a `read_string` returns.
The converter builds continuations by analysing the normalised clause body with
a depth-first traversal:

1. **Stage 2 (reader)** reads the source file and tags every construct with a
   distinct internal form: `norm_read_string`, `norm_output`, `norm_conj`,
   `norm_if_then_else`, and so on.

2. **Stage 3 (checkpoint detector)** locates every `norm_read_string` node and
   records a *checkpoint* containing:
   - The variable name that will receive the user's input.
   - The prompts (`writeln` goals) that precede this input.
   - The **continuation** — the normalised subtree that follows the
     `read_string` within the clause body.
   - The **live variables** — variables already bound by earlier `read_string`
     calls that appear free in the continuation (these must be threaded forward).

3. **Stage 4 (continuation extractor)** turns each checkpoint into a
   `cont_step/4` term describing one HTTP handler:
   - `RecvVarNames` — the set of variables to extract from the incoming POST
     request via `http_parameters/2`.
   - `PreGoals` — pure computation goals to run before rendering.
   - `Response` — a `form_resp`, `menu_resp`, `result_resp`, or `cond_resp`
     term that describes the HTML page to emit.

4. **Stage 5 (web server generator)** writes the final `.pl` file from these
   `cont_step` terms, emitting boilerplate, handler declarations, and one
   clause per step.

Branching continuations (if-then-else chains) are handled by emitting a
`cond_resp` that mirrors the original `->` structure inline within the handler
clause.  Each branch of the condition may direct the user to a different next
step URL.

### How State Is Preserved

HTTP is stateless: values bound in one request are not automatically visible
in the next.  The converter implements **form-field threading** to preserve
state across requests:

1. **Serialisation** — at the end of each intermediate handler, every
   variable that is *live* in the downstream continuation is serialised to an
   atom with `state_serialise/2` (implemented via `term_to_atom/2`) and
   written as an `<input type="hidden">` field in the outgoing HTML form.

2. **Deserialisation** — at the start of each handler, those hidden fields are
   extracted from the POST body with `http_parameters/2`, then restored to
   their original Prolog term with `state_deserialise/2`.

3. **Liveness analysis** — the converter only serialises variables that
   actually appear free in later steps.  Variables that are no longer needed
   downstream are dropped, keeping forms minimal.

Example (two-step flow with one live variable `Name`):

```
step_1 receives Name_raw, deserialises → Name
step_1 serialises Name → Name_s
step_1 renders hidden field: <input type="hidden" name="Name" value=Name_s>
step_2 receives Name_raw, deserialises → Name
step_2 uses Name in format/2
```

The round-trip guarantee is: for every ground Prolog term `T`,
`state_serialise(T, A), state_deserialise(A, T2)` implies `T2 == T`.
This holds for atoms, integers, floats, SWI strings, lists, and compound
terms.  When the atom cannot be parsed as Prolog (e.g. plain user-typed text
like `"Alice"`), `state_deserialise/2` returns the atom unchanged as a
fallback.

---

## Before-and-After Examples

### Example 1 — Simple sequential two-step form

**Input** (`examples/input_example.pl`):

```prolog
:- initialization(main, main).

main :-
    writeln('Enter your name:'),
    read_string(user, "\n", "\r", _, Name),
    writeln('Enter your age:'),
    read_string(user, "\n", "\r", _, Age),
    format("Hello, ~w! You are ~w years old.~n", [Name, Age]).
```

**Output** (abridged — see `examples/output_example.pl`):

```prolog
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_header)).

:- http_handler(root(.), step_0, []).
:- http_handler(root(step_1), step_1, [method(post)]).
:- http_handler(root(step_2), step_2, [method(post)]).

vetusia_server(Port) :- http_server(http_dispatch, [port(Port)]).
:- initialization(main, main).
main :- vetusia_server(8080).

%% Step 0: show "Enter your name:" and an empty text input
step_0(_Request) :-
    reply_html_page(title('Form'),
        [ form([method=post, action='/step_1'],
              [ p('Enter your name:'),
                input([type=text, name='Name', autofocus=autofocus]),
                input([type=submit, value='Next'])
              ]) ]).

%% Step 1: receive Name, show "Enter your age:" and carry Name forward
step_1(Request) :-
    http_parameters(Request, [ 'Name'(Name_raw, [atom]) ]),
    state_deserialise(Name_raw, Name),
    state_serialise(Name, Name_s),
    reply_html_page(title('Form'),
        [ form([method=post, action='/step_2'],
              [ input([type=hidden, name='Name', value=Name_s]),
                p('Enter your age:'),
                input([type=text, name='Age', autofocus=autofocus]),
                input([type=submit, value='Next'])
              ]) ]).

%% Step 2: receive Age and Name, output the greeting
step_2(Request) :-
    http_parameters(Request, [ 'Age'(Age_raw,[atom]), 'Name'(Name_raw,[atom]) ]),
    state_deserialise(Age_raw, Age),
    state_deserialise(Name_raw, Name),
    html_page_header('Result'),
    format("Hello, ~w! You are ~w years old.~n", [Name, Age]),
    html_page_footer.
```

**What changed:**
- Two `read_string` calls → three HTTP handlers (`step_0`, `step_1`, `step_2`).
- `writeln('Enter your name:')` → `p('Enter your name:')` inside a form.
- `read_string(…, Name)` → `<input type="text" name="Name">` in the form;
  `http_parameters(…, ['Name'(Name_raw,…)])` + `state_deserialise` in the next step.
- `Name` is threaded forward as a serialised hidden field from step_1 to step_2.
- `format/2` in the last step is kept verbatim, wrapped in `html_page_header/footer`.

---

### Example 2 — Branching menu with retry loop

See [`examples/auth_example.pl`](examples/auth_example.pl) (terminal input)
and [`examples/auth_web_example.pl`](examples/auth_web_example.pl) (generated
output) for a full multi-flow authentication example.  The converter:

- Recognises the numbered menu pattern and emits radio buttons.
- Splits the single `main/0` clause into **eight** HTTP handlers.
- Replaces the recursive `main` call (invalid-choice retry) with an
  `http_redirect(see_other, root(.), Request)` that sends the browser back to
  `step_0`.
- Threads only the live variables through each branch (e.g. `Choice` is
  dropped after branching; `Username` and `Password` are carried forward only
  in the branches that need them).

See [`docs/auth_example_comparison.md`](docs/auth_example_comparison.md) for
a line-by-line explanation of every structural difference.

---

## Quick Start

### Requirements

- [SWI-Prolog](https://www.swi-prolog.org/) ≥ 8.x

#### Installation (Ubuntu/Debian)

```bash
sudo apt-get install swi-prolog
```

#### Installation (macOS with Homebrew)

```bash
brew install swi-prolog
```

#### Installation (Windows)

Download the installer from <https://www.swi-prolog.org/Download.html>.

### CLI (recommended)

```bash
# Basic conversion (port defaults to 8080)
swipl -q -g main -s src/vetusia_converter.pl -- examples/input_example.pl -o output/web_example.pl

# Custom port
swipl -q -g main -s src/vetusia_converter.pl -- examples/input_example.pl \
      -o output/web_example.pl --port 9090

# All options
swipl -q -g main -s src/vetusia_converter.pl -- examples/input_example.pl \
      -o output/web_example.pl --port 9090 --root myapp --state-mode hidden

# Show help / usage
swipl -q -g main -s src/vetusia_converter.pl -- --help
```

**CLI options**

| Option | Default | Description |
|--------|---------|-------------|
| `<input.pl>` | *(required)* | Terminal Prolog source file to convert |
| `-o <output.pl>` | *(required)* | Output web Prolog server file |
| `--port PORT` | `8080` | Default port for the generated server |
| `--root PREFIX` | `.` | Root path prefix for HTTP handlers |
| `--state-mode MODE` | `hidden` | State passing mode: `hidden` \| `url` \| `session` |
| `--help` | | Show usage and exit |

The converter exits **0** on success and **1** on any error (bad arguments,
missing input file, or conversion failure), printing a clear error message
to stderr.

### Prolog API

```bash
swipl -g "use_module('src/web_server_generator'), \
           generate_web_server('examples/input_example.pl', \
                               'output/web_example.pl'), halt" -t halt
```

Use `generate_web_server/3` to choose a custom port:

```bash
swipl -g "use_module('src/web_server_generator'), \
           generate_web_server('examples/input_example.pl', \
                               'output/web_example.pl', 9090), halt" -t halt
```

### Interactive REPL

```prolog
?- use_module('src/web_server_generator').
?- generate_web_server('examples/input_example.pl', 'output/web_example.pl').
?- generate_web_server('examples/input_example.pl', 'output/web_example.pl', 9090).
```

---

## Running the Generated Web Server

```bash
swipl output/web_example.pl
```

Then open <http://localhost:8080> in your browser (or the port you specified).

To start the server on a different port without regenerating the file:

```bash
swipl -g "consult('output/web_example.pl'), vetusia_server(9090), halt" -t halt
```

Every generated file exposes a `vetusia_server(Port)` predicate that starts
the HTTP server on the given port.  The `main/0` predicate calls
`vetusia_server(8080)` (or your chosen default port) and is invoked
automatically by the `:- initialization(main, main)` directive when you run
the file with `swipl`.

---

## Known Limitations

The converter handles the common patterns well but has hard boundaries where
the stateless HTTP model fundamentally conflicts with the terminal execution
model.  The following constructs are flagged with `%% UNSUPPORTED:` comments
in the generated file and a warning on stderr:

| Construct | Problem | Recommended fix |
|-----------|---------|-----------------|
| `call(Var, Arg)` — dynamic meta-call | Cannot be statically analysed; may contain hidden I/O. | Replace with a named predicate call. |
| `call(Goal)` where `Goal` is a variable | Same as above. | Replace with `call(my_pred)` or inline the body. |
| `T =.. L` + `call(Goal)` — runtime goal construction | Static converter cannot trace the call target. | Avoid `=..`/`functor`/`arg` in conversion-critical code paths. |
| `assert/retract/abolish` | Database mutations are shared across all HTTP sessions; breaks per-user isolation. | Use hidden fields or the `http_session` library for mutable state. |
| `open/close` / stream handles | Stream handles cannot survive the HTTP request boundary. | Open and close streams within a single step; use file paths, not handles. |
| `halt/0-1` | Terminates the entire server process. | Remove `halt` calls from program logic. |
| `sleep/1` | Blocks the handler thread, starving other requests. | Avoid in HTTP handlers. |
| `nb_setval/nb_getval`, `b_setval/b_getval` | Global variables are shared across sessions. | Replace with hidden form fields. |
| `catch/throw` | Interaction with SWI HTTP dispatcher is unverified; uncaught exceptions produce 500 pages. | Wrap in explicit error-handling steps if needed. |
| `\+(G)` where `G` has side effects | Side effects inside `\+` may be suppressed or not rolled back correctly. | Use pure relational tests inside `\+`. |
| `!` (cut) | Handlers are deterministic by design; cut has no observable effect. | Remove cuts or replace with if-then-else. |

For a complete description of every limitation and the preservation class of
each construct, see [`docs/limitations.md`](docs/limitations.md).

---

## Recommended Coding Style

To get the best conversion results, write your terminal program following
these guidelines:

### Use descriptive variable names for read_string

The variable name becomes the HTML `<input name="…">` attribute and the
HTTP parameter name.  Use `CamelCase` atoms (matching SWI-Prolog's default
pretty-printing of variable names):

```prolog
% Good — clear field name
read_string(user, "\n", "\r", _, Username)

% Avoid — anonymous variable loses the name
read_string(user, "\n", "\r", _, _)
```

### Name password variables with "password" in the name

Any variable whose name contains the substring `password` (case-insensitive)
is automatically given an `<input type="password">` widget:

```prolog
read_string(user, "\n", "\r", _, Password)   % → type=password  ✓
read_string(user, "\n", "\r", _, UserPass)   % → type=password  ✓ (contains "pass")
read_string(user, "\n", "\r", _, Secret)     % → type=text      (no match)
```

### Use numbered menu prompts before branching read_string calls

The menu recogniser fires when the `writeln` prompts directly preceding a
`read_string` contain items like `'1. Option'`, `'2. Option'`, etc.:

```prolog
% Recognised as a menu → radio buttons (≤4 choices) or dropdown (5+)
writeln('1. Register'),
writeln('2. Login'),
writeln('3. Forgot Password'),
writeln('Enter choice (1/2/3):'),
read_string(user, "\n", "\r", _, Choice),
( Choice = "1" -> ... ; Choice = "2" -> ... ; Choice = "3" -> ... ; main ).

% Not recognised — free-text prompt only
writeln('Enter option:'),
read_string(user, "\n", "\r", _, Choice)
```

### Encode retry loops as direct recursion

A recursive call to the same predicate inside the final `else` arm of a
branching body is detected as a retry loop and converted to an HTTP redirect:

```prolog
main :-
    ...
    ( ValidChoice -> handle(Choice)
    ; writeln('Invalid. Try again.'), main   % ← recursive call → HTTP redirect
    ).
```

Any other form of looping (e.g. `repeat/0`, tail-call to a helper, `goto`
simulation via `assertz`) is not detected and passes through unchanged with
an `%% UNSUPPORTED:` warning.

### Keep computation predicates pure and self-contained

Non-I/O helper predicates are reproduced verbatim at the bottom of the
generated file.  They can call each other freely, but should not contain
`read_string` calls (the converter only transforms the `main/0` clause body).

### Minimise use of global or dynamic state

Each HTTP request is handled in a fresh logical context.  `nb_setval`,
`assertz`, and similar predicates modify process-global state that is shared
across all concurrent users.  Pass all per-user state forward as Prolog
variables that the converter will thread through hidden form fields.

### Use standard SWI-Prolog output predicates

Only `writeln/1`, `write/1`, `nl/0`, `format/1`, and `format/2` are
recognised as output goals and converted to HTML.  Other output predicates
(e.g. `write_term/2`, `print_message/2`) pass through as `norm_goal` and
appear unchanged in the generated handler body — they will write to
`current_output`, which in an HTTP context goes to the raw response stream.

---

## Running the Tests

```bash
# Stage 13 — example-based conversion (auth login/register/forgot-password)
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_web_server_generator.pl

# Stage 12 — CLI entrypoint
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_vetusia_converter.pl

# Stage 5 — web server generator
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_web_server_generator.pl

# Stage 4 — continuation extractor
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_continuation_extractor.pl

# Stage 3 — checkpoint detector
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_checkpoint_detector.pl

# Stage 2 — reader and normaliser
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_reader.pl

# Original converter
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_vetusiapl2webpl.pl
```

---

## Project Layout

```
vetusiapl2webpl/
├── src/
│   ├── reader.pl                 ← Stage 2: source reader and normaliser
│   ├── checkpoint_detector.pl    ← Stage 3: web conversion point detector
│   ├── continuation_extractor.pl ← Stage 4: continuation extraction engine
│   ├── web_server_generator.pl   ← Stage 5: web server skeleton generator (entry point)
│   ├── html_output.pl            ← Stage 6: HTML output conversion helpers
│   ├── state_serialiser.pl       ← Stage 8: state serialisation helpers
│   ├── menu_recogniser.pl        ← Stage 9: menu pattern recognition
│   ├── form_generator.pl         ← Stage 7: HTML form generation
│   ├── web_support.pl            ← Stage 11: runtime helper library
│   ├── control_flow_transformer.pl ← Stage 10: unsupported-construct warnings
│   ├── vetusia_converter.pl      ← Stage 12: CLI entrypoint
│   └── vetusiapl2webpl.pl        ← original single-module converter (convert/2)
├── examples/
│   ├── auth_example.pl           ← Stage 13: terminal login/register/forgot-password input
│   ├── auth_web_example.pl       ← Stage 13: reference web output for auth_example.pl
│   ├── input_example.pl          ← sample terminal Prolog input
│   ├── output_example.pl         ← reference web Prolog output (simple sequential)
│   └── web_support_example.pl    ← Stage 11: web_support.pl variant of output_example
├── tests/
│   ├── test_reader.pl                ← Stage 2 test suite
│   ├── test_checkpoint_detector.pl   ← Stage 3 test suite
│   ├── test_continuation_extractor.pl← Stage 4 test suite
│   ├── test_web_server_generator.pl  ← Stage 5 + Stage 13 test suite
│   ├── test_html_output.pl           ← Stage 6 test suite
│   ├── test_state_serialiser.pl      ← Stage 8 test suite
│   ├── test_menu_recogniser.pl       ← Stage 9 test suite
│   ├── test_form_generator.pl        ← Stage 7 test suite
│   ├── test_web_support.pl           ← Stage 11 test suite
│   ├── test_vetusia_converter.pl     ← Stage 12 test suite
│   ├── test_integration_server.pl    ← integration test suite
│   └── test_vetusiapl2webpl.pl       ← original converter test suite
├── docs/
│   ├── architecture.md              ← design and extension guide
│   ├── supported_patterns.md        ← supported Prolog patterns reference
│   ├── limitations.md               ← known limitations and fallback strategy
│   ├── web_support_helpers.md       ← runtime helper library reference
│   └── auth_example_comparison.md   ← Stage 13: comparison notes for auth conversion
├── output/                       ← default output directory
├── README.md
└── LICENSE
```

---

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for a detailed description
of the conversion pipeline, data structures, and extension points.

See [`docs/supported_patterns.md`](docs/supported_patterns.md) for a
reference of every Prolog pattern the converter handles, with examples.

---

## PR Completion Criteria

See [`docs/completion_criteria.md`](docs/completion_criteria.md) for the
Stage 18 pull-request completion checklist.  That document maps each of the
seven formal requirements (working code, examples, test suite, README,
demonstration, no-JavaScript constraint, supported/unsupported construct
reference) to the concrete files in this repository, and includes an
acceptance-standard table showing how `examples/auth_example.pl` →
`examples/auth_web_example.pl` satisfies every criterion.

---

## License

BSD 3-Clause — see [`LICENSE`](LICENSE).

# vetusiapl2webpl — Vetusia Prolog-to-Web-Prolog Converter

`vetusiapl2webpl` takes a **terminal-based Prolog program** that uses
`read_string/5` for user input and converts it into a **SWI-Prolog HTTP
server program** that serves HTML pages — one page per `read_string`
interaction, with no JavaScript required.

---

## Features

- Converts each `read_string/5` call into an HTML form step.
- Threads captured variables forward via hidden form fields and
  `http_parameters/2`.
- Rewrites `writeln/1`, `write/1`, `nl`, and `format/1-2` calls to HTML
  paragraph/span elements inside `reply_html_page/2`.
- Preserves all non-I/O (computation) predicates verbatim.
- Generates a self-contained SWI-Prolog HTTP server on port 8080.
- Written entirely in Prolog; no external dependencies beyond SWI-Prolog.

---

## Requirements

- [SWI-Prolog](https://www.swi-prolog.org/) ≥ 8.x

### Installation (Ubuntu/Debian)

```bash
sudo apt-get install swi-prolog
```

### Installation (macOS with Homebrew)

```bash
brew install swi-prolog
```

### Installation (Windows)

Download the installer from <https://www.swi-prolog.org/Download.html>.

---

## Quick Start

### CLI (Stage 12 — recommended)

Convert using the CLI entrypoint (`src/vetusia_converter.pl`):

```bash
# Basic conversion (port defaults to 8080)
swipl -q -g main -s src/vetusia_converter.pl -- examples/input_example.pl -o output/web_example.pl

# Custom port
swipl -q -g main -s src/vetusia_converter.pl -- examples/input_example.pl -o output/web_example.pl --port 9090

# All options
swipl -q -g main -s src/vetusia_converter.pl -- examples/input_example.pl -o output/web_example.pl \
      --port 9090 --root myapp --state-mode hidden

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

### One-command conversion (Stage 5 — Prolog API)

```bash
swipl -g "use_module('src/web_server_generator'), \
           generate_web_server('examples/input_example.pl', \
                               'output/web_example.pl'), halt" -t halt
```

This reads `examples/input_example.pl` (a terminal Prolog program) and
writes `output/web_example.pl` (a runnable SWI-Prolog HTTP server).

Use `generate_web_server/3` to choose a custom port:

```bash
swipl -g "use_module('src/web_server_generator'), \
           generate_web_server('examples/input_example.pl', \
                               'output/web_example.pl', 9090), halt" -t halt
```

### Run the generated server

```bash
swipl output/web_example.pl
```

Then open <http://localhost:8080> in your browser (or the custom port you
chose).  You can also start the server on a different port without
regenerating the file:

```bash
swipl -g "consult('output/web_example.pl'), vetusia_server(9090), halt" -t halt
```

---

## Interactive Usage (SWI-Prolog REPL)

```prolog
?- use_module('src/web_server_generator').
?- generate_web_server('examples/input_example.pl', 'output/web_example.pl').
?- generate_web_server('examples/input_example.pl', 'output/web_example.pl', 9090).
```

---

## Conversion Example

### Input (`examples/input_example.pl`)

```prolog
:- initialization(main, main).

main :-
    writeln('Enter your name:'),
    read_string(user, "\n", "\r", _, Name),
    writeln('Enter your age:'),
    read_string(user, "\n", "\r", _, Age),
    format("Hello, ~w! You are ~w years old.~n", [Name, Age]).
```

### Output (`output/web_example.pl`) — abridged

```prolog
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_parameters)).

:- http_handler(root(.), step_0, []).
:- http_handler(root(step_1), step_1, [method(post)]).
:- http_handler(root(step_2), step_2, [method(post)]).

:- initialization(main, main).
main :- http_server(http_dispatch, [port(8080)]).

step_0(_Request) :-
    reply_html_page(title('Step 0'),
        [ form([method=post, action='/step_1'],
              [ p('Enter your name:'),
                input([type=text, name='Name']),
                input([type=submit, value='Next'])
              ]) ]).

step_1(Request) :-
    http_parameters(Request, [ 'Name'(Name, [atom]) ]),
    reply_html_page(title('Step 1'),
        [ form([method=post, action='/step_2'],
              [ input([type=hidden, name='Name', value=Name]),
                p('Enter your age:'),
                input([type=text, name='Age']),
                input([type=submit, value='Next'])
              ]) ]).

step_2(Request) :-
    http_parameters(Request, [ 'Age'(Age,[atom]), 'Name'(Name,[atom]) ]),
    format('Content-type: text/html\n\n'),
    format('<html><body>\n'),
    format('<p>~w</p>\n', [Age]),
    format('<p>~w</p>\n', [Name]),
    format("Hello, ~w! You are ~w years old.~n", [Name, Age]),
    format('</body></html>\n').
```

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

# Original converter (Stage 4+)
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_vetusiapl2webpl.pl
```

---

## Stage 13 — Example-Based Conversion

`examples/auth_example.pl` is a terminal authentication program with three
flows (register, login, forgot password) and a retry loop for invalid input.
`examples/auth_web_example.pl` is the hand-annotated reference web output.

See [`docs/auth_example_comparison.md`](docs/auth_example_comparison.md)
for a detailed explanation of every expected difference between the terminal
input and the generated web output.

---

## Project Layout

```
vetusiapl2webpl/
├── src/
│   ├── reader.pl                 ← Stage 2: source reader and normaliser
│   ├── checkpoint_detector.pl    ← Stage 3: web conversion point detector
│   ├── continuation_extractor.pl ← Stage 4: continuation extraction engine
│   ├── web_server_generator.pl   ← Stage 5: web server skeleton generator (entry point)
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
│   └── test_vetusiapl2webpl.pl       ← original converter test suite
├── docs/
│   ├── architecture.md              ← design and extension guide
│   └── auth_example_comparison.md   ← Stage 13: comparison notes for auth conversion
├── output/                       ← default output directory
├── README.md
└── LICENSE
```

---

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for a detailed description
of the conversion pipeline, data structures, and extension points.

---

## License

BSD 3-Clause — see [`LICENSE`](LICENSE).

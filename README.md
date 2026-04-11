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

### One-command conversion

```bash
swipl -g "use_module('src/vetusiapl2webpl'), \
           convert('examples/input_example.pl', \
                   'output/web_example.pl'), halt" -t halt
```

This reads `examples/input_example.pl` (a terminal Prolog program) and
writes `output/web_example.pl` (a runnable SWI-Prolog HTTP server).

### Run the generated server

```bash
swipl output/web_example.pl
```

Then open <http://localhost:8080> in your browser.

---

## Interactive Usage (SWI-Prolog REPL)

```prolog
?- use_module('src/vetusiapl2webpl').
?- convert('examples/input_example.pl', 'output/web_example.pl').
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
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_vetusiapl2webpl.pl
```

---

## Project Layout

```
vetusiapl2webpl/
├── src/
│   └── vetusiapl2webpl.pl        ← converter (entry point: convert/2)
├── examples/
│   ├── input_example.pl          ← sample terminal Prolog input
│   └── output_example.pl         ← reference web Prolog output
├── tests/
│   └── test_vetusiapl2webpl.pl   ← plunit test suite
├── docs/
│   └── architecture.md           ← design and extension guide
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

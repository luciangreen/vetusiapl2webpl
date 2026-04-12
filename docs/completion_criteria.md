# Stage 18 — Pull Request Completion Criteria

This document records what counts as *done* for the `vetusiapl2webpl`
project, and maps each formal requirement to the concrete evidence already
present in this repository.

---

## PR Completion Checklist

### 1. Working converter code

| Item | Location |
|------|----------|
| Main entry point (CLI) | `src/vetusia_converter.pl` |
| Pipeline orchestrator | `src/web_server_generator.pl` |
| Source reader / normaliser | `src/reader.pl` |
| Checkpoint detector | `src/checkpoint_detector.pl` |
| Continuation extractor | `src/continuation_extractor.pl` |
| Control-flow transformer (warnings) | `src/control_flow_transformer.pl` |
| HTML / form output | `src/html_output.pl` |
| Form widget generator | `src/form_generator.pl` |
| Menu recognition | `src/menu_recogniser.pl` |
| State serialisation helpers | `src/state_serialiser.pl` |
| Runtime web-support library | `src/web_support.pl` |
| Public converter API | `src/vetusiapl2webpl.pl` |

All modules are written in pure SWI-Prolog and require no external
dependencies beyond the standard SWI-Prolog library (≥ 8.x).

---

### 2. Example input and generated output

| File | Role |
|------|------|
| `examples/input_example.pl` | Simple two-step input example — terminal source |
| `examples/output_example.pl` | Hand-annotated reference output for the simple example |
| `examples/auth_example.pl` | Multi-branch menu example — terminal source |
| `examples/auth_web_example.pl` | Hand-annotated reference output for the menu example |
| `examples/web_support_example.pl` | Illustration of the runtime helper API |

To regenerate `output/web_example.pl` from source:

```bash
swipl -q -g main -s src/vetusia_converter.pl -- \
      examples/input_example.pl -o output/web_example.pl
```

---

### 3. Test suite

| Test file | What it covers |
|-----------|---------------|
| `tests/test_vetusiapl2webpl.pl` | Top-level converter predicates, end-to-end conversion |
| `tests/test_reader.pl` | Stage 2 — reader and normaliser |
| `tests/test_checkpoint_detector.pl` | Stage 3 — checkpoint detection |
| `tests/test_continuation_extractor.pl` | Stage 4 — continuation extraction |
| `tests/test_web_server_generator.pl` | Stage 5 — server code emitter |
| `tests/test_html_output.pl` | Stage 6 — HTML output helpers |
| `tests/test_control_flow_transformer.pl` | Stage 10 — control-flow warnings |
| `tests/test_form_generator.pl` | Form widget generation |
| `tests/test_menu_recogniser.pl` | Menu pattern recognition |
| `tests/test_state_serialiser.pl` | State serialise/deserialise round-trips |
| `tests/test_web_support.pl` | Runtime web-support helpers |
| `tests/test_vetusia_converter.pl` | CLI converter integration |
| `tests/test_integration_server.pl` | End-to-end HTTP server integration |

**Running all tests:**

```bash
swipl -g "load_test_files([]), run_tests, halt" -t halt \
      tests/test_vetusiapl2webpl.pl
```

Or, to run every test file individually:

```bash
for f in tests/test_*.pl; do
  echo "=== $f ==="
  swipl -g "load_test_files([]), run_tests, halt" -t halt "$f"
done
```

---

### 4. README with installation and usage

`README.md` (project root) includes:

- **What the converter does** — overview and goals
- **How conversion works** — `read_string` page cut-offs, continuation
  generation, state preservation
- **Before-and-after examples** — simple two-step and multi-branch auth
- **Quick Start** — SWI-Prolog installation instructions for Ubuntu/Debian,
  macOS (Homebrew), and Windows; CLI usage with all options; Prolog API and
  interactive-REPL usage
- **Running the generated web server** — how to launch the output file and
  open it in a browser
- **Known limitations** — pointer to `docs/limitations.md`
- **Recommended coding style**
- **Running the tests**
- **Project layout**
- **Architecture**
- **License**

---

### 5. Demonstration — terminal `read_string` flow → working Prolog web workflow

The `examples/auth_example.pl` / `examples/auth_web_example.pl` pair is the
canonical end-to-end demonstration.  See §Acceptance Standard below for the
full mapping.

A detailed side-by-side comparison of the terminal and web versions (with
inline commentary) is in `docs/auth_example_comparison.md`.

---

### 6. No JavaScript dependency

The generated server programs are pure SWI-Prolog HTTP applications.
No JavaScript is emitted, loaded, or required at any point in the
application flow:

- All interactivity is handled by standard HTML `<form>` elements with
  `method=post`.
- State is threaded via `<input type="hidden">` fields — no `localStorage`,
  `sessionStorage`, cookies, or `XMLHttpRequest`.
- The `src/web_support.pl` runtime helper contains only Prolog predicates
  and no JavaScript.

This constraint is enforced by design: `html_output.pl` and
`form_generator.pl` never emit `<script>` tags or JavaScript attributes.

---

### 7. Supported and unsupported constructs

| Document | Content |
|----------|---------|
| `docs/supported_patterns.md` | Complete reference of every recognised pattern, its HTML/HTTP mapping, and a worked example: sequential inputs, output predicates, password detection, numbered menus → radio/select, if-then-else branching, recursive retry loops, auxiliary predicates, directives, pure computation, `format/2` output, `read_password/1-2` |
| `docs/limitations.md` | Every known hard case: dynamic meta-calls, `call/1` chains, DCG rules, `assert`/`retract`, global state, `catch`/`throw`, multi-clause predicates, `aggregate_all`, `nb_getval`/`nb_setval`; the warning system; the safe pass-through fallback strategy; preservation class table |
| `docs/architecture.md` | Pipeline stage descriptions, normalised form reference, public API of each module |
| `docs/web_support_helpers.md` | Runtime helper predicates provided to generated programs |
| `docs/auth_example_comparison.md` | Line-by-line comparison showing how each terminal construct becomes a web construct |

---

## Acceptance Standard

> *A sample Prolog program using `read_string` for menu navigation and user
> input should convert into a Prolog HTTP program that:*
> - *starts a web server*
> - *renders the first page*
> - *accepts form input*
> - *resumes the original logic in stages*
> - *preserves branching and repeated prompts*

**Demonstrated by:** `examples/auth_example.pl` → `examples/auth_web_example.pl`

### Terminal program (`examples/auth_example.pl`)

```prolog
:- initialization(main, main).

main :-
    writeln('=== Authentication System ==='),
    writeln('1. Register'),
    writeln('2. Login'),
    writeln('3. Forgot Password'),
    writeln('Enter choice (1/2/3):'),
    read_string(user, "\n", "\r", _, Choice),
    ( Choice = "1" ->
        writeln('-- Register --'),
        writeln('Enter username:'),
        read_string(user, "\n", "\r", _, Username),
        writeln('Enter password:'),
        read_string(user, "\n", "\r", _, Password),
        writeln('Enter email:'),
        read_string(user, "\n", "\r", _, Email),
        format("Registered: ~w / ~w (email: ~w)~n", [Username, Password, Email])
    ; Choice = "2" ->
        writeln('-- Login --'),
        writeln('Enter username:'),
        read_string(user, "\n", "\r", _, Username),
        writeln('Enter password:'),
        read_string(user, "\n", "\r", _, Password),
        format("Welcome back, ~w! (pass: ~w)~n", [Username, Password])
    ; Choice = "3" ->
        writeln('-- Forgot Password --'),
        writeln('Enter your email:'),
        read_string(user, "\n", "\r", _, Email),
        format("Password reset link sent to: ~w~n", [Email])
    ;
        writeln('Invalid choice. Please try again.'),
        main
    ).
```

### How the acceptance criteria are met

| Criterion | Evidence in `examples/auth_web_example.pl` |
|-----------|---------------------------------------------|
| **Starts a web server** | `main/0` calls `vetusia_server(8080)` which calls `http_server(http_dispatch, [port(8080)])`. |
| **Renders the first page** | `step_0/1` is a GET handler on `root(.)`. It serves an HTML page with the full authentication menu rendered as radio buttons, and a submit button pointing to `/step_1`. |
| **Accepts form input** | Every POST handler (`step_1` through `step_7`) calls `http_parameters/2` to extract submitted form fields, then calls `state_deserialise/2` to restore each field to its original Prolog term. |
| **Resumes the original logic in stages** | The 8-handler chain mirrors the terminal execution order exactly: `step_1` dispatches on `Choice`; `step_2`–`step_4` implement the Register flow; `step_5`–`step_6` implement Login; `step_7` implements Forgot Password. Each handler runs only the goals that would have executed at that point in the original `main/0`. |
| **Preserves branching** | `step_1` contains a Prolog if-then-else chain (`( Choice = "1" -> … ; Choice = "2" -> … ; Choice = "3" -> … ; http_redirect(…) )`) that exactly mirrors the terminal program's `->` structure. |
| **Preserves repeated prompts** | The invalid-choice else branch calls `http_redirect(see_other, root(.), Request)`, sending the browser back to `step_0` — the web equivalent of the `main` recursive call in the terminal program. |

### Running the demonstration

**Step 1 — Convert the terminal program:**

```bash
swipl -q -g main -s src/vetusia_converter.pl -- \
      examples/auth_example.pl -o output/auth_web.pl
```

The generated file is also provided verbatim at `examples/auth_web_example.pl`.

**Step 2 — Start the generated web server:**

```bash
swipl examples/auth_web_example.pl
```

Expected output:

```
% Started server at http://localhost:8080/
```

**Step 3 — Open the application:**

Navigate to `http://localhost:8080/` in a browser.  The authentication menu
appears with radio buttons for Register, Login, and Forgot Password.
Selecting a choice and clicking *Next* advances through the relevant
multi-step form, collecting the required inputs before displaying the result.

---

## File Index

| Path | Stage 18 requirement addressed |
|------|-------------------------------|
| `src/` | #1 — working converter code |
| `examples/input_example.pl` | #2 — example input |
| `examples/output_example.pl` | #2 — generated output |
| `examples/auth_example.pl` | #2, #5 — demo input |
| `examples/auth_web_example.pl` | #2, #5 — demo output |
| `tests/` | #3 — test suite |
| `README.md` | #4 — installation and usage |
| `docs/supported_patterns.md` | #7 — supported constructs |
| `docs/limitations.md` | #7 — unsupported constructs |
| `docs/auth_example_comparison.md` | #5, #7 — annotated demo |
| `docs/completion_criteria.md` | This document — Stage 18 summary |

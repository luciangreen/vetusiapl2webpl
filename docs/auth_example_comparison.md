# Stage 13 — Auth Example Conversion: Comparison Notes

## Overview

This document explains the expected differences between
`examples/auth_example.pl` (terminal input) and
`examples/auth_web_example.pl` (generated web output), and why each
difference exists.

---

## Example input (`examples/auth_example.pl`)

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

---

## Generated output (`examples/auth_web_example.pl`)

See the file directly.  The key structural changes are described below.

---

## Expected differences and their rationale

### 1. Eight HTTP handlers replace one predicate

The converter splits `main/0` into **eight** `step_N` handlers because
the source has one sequential read (Choice) followed by three mutually
exclusive branching flows each containing further reads:

| Handler | Method | Role |
|---------|--------|------|
| `step_0` | GET  | Landing page — authentication system menu |
| `step_1` | POST | Dispatch on Choice (→ register, login, forgot, or retry) |
| `step_2` | POST | Register: collect Password (after Username) |
| `step_3` | POST | Register: collect Email (after Password) |
| `step_4` | POST | Register: show confirmation result |
| `step_5` | POST | Login: collect Password (after Username) |
| `step_6` | POST | Login: show welcome result |
| `step_7` | POST | Forgot password: show reset confirmation |

The step numbers follow the checkpoint detector's left-to-right,
depth-first traversal order.

---

### 2. Menu → radio buttons (Stage 9 — menu recogniser)

**Terminal**: five `writeln` calls followed by a free-text `read_string`.

**Web**: the converter recognises the menu pattern — prompts that
contain numbered items (`1. Register`, `2. Login`, `3. Forgot Password`)
followed by an if-then-else chain — and emits a `form` with
`input([type=radio, ...])` elements for each choice, plus a submit button.

With three choices (≤ 4), the `menu_input_kind/2` predicate selects
`radio` over `select`.  Five or more choices would produce a dropdown.

The prompt labels (`1. Register`, etc.) are also rendered as `<p>`
elements above the radio widget so the user sees the full menu text.

---

### 3. Branching becomes nested if-then-else in step_1

**Terminal**: a chain of `( Choice = "1" -> ... ; Choice = "2" -> ... ; ... )`
executed top-to-bottom inside a single clause.

**Web**: `step_1` receives `Choice` via `http_parameters/2`, deserialises
it with `state_deserialise/2`, then re-runs the same if-then-else.
Each branch renders a fresh form directing the user to the correct
next step (`/step_2`, `/step_5`, or `/step_7`).

The `cond_resp` nesting in the converter's internal representation
maps directly onto the nested `(Cond -> Then ; Else)` Prolog structure
in the generated clause.

---

### 4. Invalid choice → HTTP redirect (retry loop handling)

**Terminal**: the final `else` arm calls `main` recursively, causing the
menu to be re-displayed.

**Web**: the converter detects the recursive call to `main/0` (context tag
`loop(main/0)`) and replaces it with
`http_redirect(see_other, root(.), Request)`, which sends the browser
back to `step_0` — the web equivalent of a menu retry loop.

The `writeln('Invalid choice. Please try again.')` line is dropped in the
web output because that `else` arm is handled entirely by the redirect;
no HTML page is rendered for it.

---

### 5. State serialisation (Stage 8)

**Terminal**: Prolog variables (`Username`, `Password`, `Email`) are live in
memory throughout the clause execution — no explicit threading needed.

**Web**: each HTTP request is stateless.  The converter uses
`state_serialise/2` and `state_deserialise/2` (Stage 8) to round-trip
Prolog terms through HTML hidden form fields.

Variables are only serialised when they are *live* — i.e., they appear
free in the downstream continuation.  For example:

- `Choice` is **not** serialised after step_1 because it does not appear
  in any continuation beyond the branch dispatch.
- `Username` **is** serialised in step_2 because it appears in the final
  `format/2` call in steps 4 and 6.
- Both `Username` and `Password` are serialised in step_3 because both
  appear in the step_4 result.

This selective serialisation keeps forms minimal.

---

### 6. Password field uses `input([type=password, ...])`

**Terminal**: `read_string` with the variable named `Password` (plain text).

**Web**: the Stage 7 form generator detects that the variable name
contains the substring `password` (case-insensitive) and emits an
`input([type=password, ...])` element instead of `input([type=text, ...])`.

---

### 7. `writeln` prompts → `<p>` elements

**Terminal**: `writeln('-- Register --')` writes a line to stdout.

**Web**: each `writeln(Text)` call that precedes a `read_string` becomes a
`p(Text)` HTML term inside `reply_html_page/2` via
`norm_output_to_html_term/2` (Stage 6).

---

### 8. Final output (`format/2`) → raw format calls via result page

**Terminal**: `format("Registered: ~w / ~w (email: ~w)~n", ...)` writes
directly to stdout.

**Web**: the result handlers (step_4, step_6, step_7) wrap the output in
`html_page_header('Result')` / `html_page_footer` and keep the original
`format/2` call verbatim, so the format string and variable bindings are
preserved exactly.

---

### 9. What is preserved character-for-character

- The `format/2` goal strings (e.g. `"Registered: ~w / ~w (email: ~w)~n"`)
- All variable names (`Username`, `Password`, `Email`, `Choice`)
- The branching conditions (`Choice = "1"`, `Choice = "2"`, `Choice = "3"`)
- The `writeln` prompt strings (as `p(...)` content)

### 10. What is intentionally changed

| Terminal form | Web form | Reason |
|---------------|----------|--------|
| `read_string(user, "\n", "\r", _, V)` | `http_parameters/2` + `state_deserialise/2` | stateless HTTP |
| `writeln(Text)` before a prompt | `p(Text)` in `reply_html_page/2` | HTML rendering |
| `main` (recursive retry) | `http_redirect(see_other, root(.), Request)` | HTTP redirect |
| Single `main/0` clause | 8 `step_N/1` HTTP handlers | one step per read |
| `:- initialization(main, main).` | `vetusia_server(8080)` in `main/0` | server start-up |

---

## Running the comparison

1. Run the terminal version:
   ```bash
   swipl examples/auth_example.pl
   ```

2. Generate and run the web version:
   ```bash
   swipl -q -g main -s src/vetusia_converter.pl -- \
         examples/auth_example.pl -o output/auth_web.pl
   swipl output/auth_web.pl
   # Open http://localhost:8080 in a browser
   ```

3. Compare the reference output:
   ```bash
   diff examples/auth_web_example.pl output/auth_web.pl
   ```
   Expected differences: comment formatting, variable name capitalisation
   choices, and whitespace.  The handler structure, HTTP routes, and
   branching logic should match.

# ninox.d-gotmpl

This package provides a template system like go's [`text/template`](https://pkg.go.dev/text/template#pkg-index).

## License

The code in this repository is licensed under AGPL-3.0-or-later; for more details see the `LICENSE` file in the [repository](https://codearq.net/bithero-dlang/ninox.d-gotmpl).

## Usage

To use the engine, you first need to parse a template. To do this, use one of the `parse*` variants of `Template`:

```d
import ninox.gotmpl : Template;

// This parses a template from the string "content", and gives it the name "name".
auto tmpl = Template.parseString("name", "content");

// This method parses a template from a file, and gives it the name "name".
auto tmpl = Template.parseFile("name", "path/to/template");

// It is also possible to parse directly from a libc stream handle (`FILE*`):
import core.stdc.stdio : FILE;
FILE* file = /*...*/;
auto tmpl = Template.parseFile("name", file);
```

## Differences:

- Unimplemented builtin functions:
    - `printf`
    - `html`
    - `js`
    - `urlquery`
    - `slice`

Diagram Generator
=================

This Lua filter is used to create figures from code blocks: images
are generated from the code with the help of external programs.
The filter processes diagram code for Asymptote, Graphviz,
Mermaid, PlantUML, Ti*k*Z, and D2.


Usage
-----

The filter modifies the internal document representation; it can
be used with many publishing systems that are based on pandoc.

Please make sure to read the section on [security](#security) if
you are going to use this filter with third-party input documents.

> [!IMPORTANT]
> This filter makes the generated images available to pandoc, but
> *does not* write image files by itself. Use pandoc's
> `--extract-media` to write the generated images to disk. Or,
> when producing HTML, use `--embed-resources` to incorporate the
> images in the output file via `data` URIs.

### Plain pandoc

Pass the filter to pandoc via the `--lua-filter` (or `-L`) command
line option.

    pandoc --lua-filter diagram.lua ...

### Quarto

Users of Quarto can install this filter as an extension with

    quarto install extension pandoc-ext/diagram

and use it by adding `diagram` to the `filters` entry in their
YAML header.

``` yaml
---
filters:
  - diagram
---
```

#### Notes on usage with Quarto

Quarto comes with its own system for diagram generation that can
be used for a variety of diagrams. Especially Mermaid diagram
generation is much faster with Quarto's built-in diagram handling.

Due to the way in which Quarto handles code blocks, *do not* add
`filename` attributes to code block attribute lists.

`````` markdown
``` {.tikz filename="my-graph"}
% DON'T use the filename attribute on code blocks
...
``````

Instead, use the "comment-pipe" syntax to define the graphic's
file name.

`````` markdown
``` tikz
%%| filename: my-graph
% This should work ok.
...
```
``````

### R Markdown

Use `pandoc_args` to invoke the filter. See the [R Markdown
Cookbook](https://bookdown.org/yihui/rmarkdown-cookbook/lua-filters.html)
for details.

``` yaml
---
output:
  word_document:
    pandoc_args: ['--lua-filter=diagram.lua']
---
```

Diagram types
-------------

The table below lists the supported diagram drawing systems, the
class that must be used for the system, and the main executable
that the filter calls to generate an image from the code. The
*environment variables* column lists the names of env variables
that can be used to specify a specific executable.

| System      | code block class  | executable | env variable    |
|-------------|-------------------|------------|-----------------|
| [Asymptote] | `asymptote`       | `asy`      | `ASYMPTOTE_BIN` |
| [GraphViz]  | `dot`             | `dot`      | `DOT_BIN`       |
| [Mermaid]   | `mermaid`         | `mmdc`     | `MERMAID_BIN`   |
| [PlantUML]  | `plantuml`        | `plantuml` | `PLANTUML_BIN`  |
| [Ti*k*Z]    | `tikz`            | `pdflatex` | `PDFLATEX_BIN`  |
| [cetz]      | `cetz`            | `typst`    | `TYPST_BIN`     |
| [D2]        | `d2`              | `d2`       | `D2_BIN`        |

### Other diagram engines

The filter can be extended with local packages; see
[Configuration](#configuration) below.

[Asymptote]: https://asymptote.sourceforge.io/
[GraphViz]: https://www.graphviz.org/
[Mermaid]: https://mermaid.js.org/
[PlantUML]: https://plantuml.com/
[Ti*k*Z]: https://github.com/pgf-tikz/pgf
[Cetz]: https://github.com/cetz-package/cetz
[D2]: https://d2lang.com/

Figure options
--------------

Options can be given using the syntax pioneered by [Quarto]:

````
``` {.dot}
//| label: fig-boring
//| fig-cap: "A boring Graphviz graph."
digraph boring {
  A -> B;
}
```
````

[Quarto]: https://quarto.org/

Configuration
-------------

The filter can be configured with the `diagram` metadata entry.

Currently supported options:

- `cache`: controls whether the images are cached. If the cache is
  enabled, then the images are recreated only when their code
  changes. This option is *disabled* by default.

- `cache-dir`: Sets the directory in which the images are cached.
  The default is to use the `pandoc-diagram-filter` subdir of the
  a common caching location. This will be, in the order of
  preference, the value of the `XDG_CACHE_HOME` environment
  variable if it is set, or alternatively `%USERPROFILE%\.cache` on
  Windows and `$HOME/.cache` on all other platforms.

  Caching is disabled if none of the environment variables
  mentioned above have been defined.

- `engine`: options for specific engines, e.g. `plantuml` or
  `mermaid`. The options must be nested below the engine name.
  Allowed settings are either `true` or `false` to enable or
  disable the engine, respectively, or a map of options.
  The available settings are:

  + `mime-type`: the output MIME type that should be produced with
    this engine. This can be used to choose a specific type, or to
    disable certain output formats. For example, the following
    disables support for PDF output in PlantUML, which can be
    useful when the necessary libraries are unavailable on a
    system:

    ``` yaml
    diagram:
      engine:
        plantuml:
          mime-type:
            application/pdf: false
    ```

  + `line_comment_start`: the character sequence that starts a
    line comment; unset or change this to disable or modify the
    syntax of user options in the diagram code.

  + `execpath`: the path to the engine's executable. Use this to
    override the default executable name listed in the table
    above.

    Use a list to pass additional arguments to the executable.
    E.g., `execpath: ['xelatex' '-halt-on-error']` will use
    `xelatex` as the executable and pass `-halt-on-error` as the
    first argument.

  + `package`: if this option is set then the filter will try to
    `require` a Lua package with the given name. If the operation
    is successful, then the result will be used as the compiler
    for that diagram type.

  + Any other option is passed through to the engine. See the
    engine-specific settings below.

### Engine-specific options

Some engines accept additional options. These options can either
be passed globally as part of the respective `engine` entry, or
locally by adding `opt-NAME` as an attribute to the diagram code
block. Global options always override local options for security
reasons.

#### Ti*k*Z

The Ti*k*Z engine accepts the `header-includes` and
`additional-packages` options. Both options are added to the
intermediary TeX file that is used to produce the output file. The
options differ only in how string values are handled, with bare
strings in `header-includes` being escaped and those in
`additional-packages` being treated as TeX code.

While mentioned above, it should be highlighted that the
`execpath` option can be used to select a specific LaTeX engine.
The default is `pdflatex`.

Example:

``` yaml
---
diagram:
  engine:
    tikz:
      execpath: lualatex
      header-includes:
        - '\usepackage{adjustbox}'
        - '\usetikzlibrary{arrows, shapes}'
---
```

Security
--------

This filter **should not** be used with **untrusted documents**,
***unless*** local configs prevent the setting of filter options
in the metadata: An attacker that can set the execpath for an
engine can execute any binary on the system with the user's
permissions. It is hence recommended to review any document before
using it with this filter to avoid malicious and misuse of the
filter.

The security is improved considerably if the `diagram` metadata
field is unset or set to a predefined value before this filter is
called, e.g., via another filter or a defaults file.

Here is an example defaults file that configures the filter such
that the configs cannot be overwritten by the document.

``` yaml
# file: diagram-filter.yaml
filters: ['diagram.lua']
metadata:
  diagram:
    engine:
      # enable dot/GraphViz and PlantUML with default options
      dot: true
      plantuml: true

      # disable processing of asymptote and Mermaid diagrams
      asymptote: false
      mermaid: false

      # Use LuaLaTeX to compile TikZ, define headers
      tikz:
        execpath: lualatex
        additional-packages: |
          \usepackage{adjustbox}
          \usetikzlibrary{arrows, shapes}
```

Usage:

    pandoc -d diagram-filter ...

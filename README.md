Diagram Generator
=================

This Lua filter is used to create figures from code blocks: images
are generated from the code with the help of external programs.
Currently PlantUML, Graphviz, Ti*k*Z and Python can be processed.


Usage
-----

The filter modifies the internal document representation; it can
be used with many publishing systems that are based on pandoc.

### Plain pandoc

Pass the filter to pandoc via the `--lua-filter` (or `-L`) command
line option.

    pandoc --lua-filter diagram.lua ...

### Quarto

While it is possible to use this filter with Quarto, it is not
encouraged. Quarto comes its own system for diagram generation,
and that should be used instead.

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

| System      | code block class  | executable | environment variables |
|-------------|-------------------|------------|-----------------------|
| [Asymptote] | `asymptote`       | `asy`      | `ASYMPTOTE`, `ASY`    |
| [GraphViz]  | `graphviz`, `dot` | `dot`      | `DOT`                 |
| [PlantUML]  | `plantuml`        | `plantuml` | `PLANTUML`            |
| [Ti*k*Z]    | `tikz`            | `pdflatex` | `PDFLATEX`            |

[Asymptote]:
[GraphViz]: https://www.graphviz.org/
[PlantUML]: https://plantuml.org/
[Ti*k*Z]: https://en.wikipedia.org/wiki/PGF/TikZ

Configuration
-------------

The filter can be configured with the `diagram` metadata entry.

Currently supported options:

- `path`: map from executable names to file paths. Just like with
  environment variables, this will override the binary that is
  called to convert an image. The entries in the metadata have the
  highest priority, so if both a metadata field and an env var is
  set, then the value from the metadata will be used.

- `cache`: controls whether the images are cached. If the cache is
  enabled, then the images are recreated only when their code
  changes. This option is *enabled* by default.

- `cache-dir`: Sets the directory in which the images are cached.
  The default is to use the `pandoc-diagram-filter` subdir of the
  a common caching location. This will be, in the order of
  preference, the value of the `XDG_CACHE_HOME` environment
  variable if it is set, or alternatively `%USERPROFILE%\.cache` on
  Windows and `$HOME/.cache` on all other platforms.

  Caching is disabled if none of the environment variables
  mentioned above has been defined.


Security
--------

This filter **must not** be used with **untrusted documents**. The
filter effectively turns the document into a script that can run
arbitrary commands with the user's permissions. It is hence
recommended to review any document before using it with this
filter.

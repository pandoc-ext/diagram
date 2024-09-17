# diagram

The diagram filter is versioned using [Semantic Versioning][].

[Semantic Versioning]: https://semver.org/

## v1.1.0

Released 2024-09-17.

- Provide better errors if TikZ fails to render.

- Use pandoc's own warn- and logging-system when possible.

- Use SVG only as a fallback option when targeting office formats.

- Transfer attributes from the code block to the image, unless the
  attribute has a special meaning. The ID is still transferred to
  the generated figure element.

- Add version field to the filter.

- Improved docs.

## v1.0.0

Released 2023-05-22.

- First release of the Lua filter; may it live long and prosper.

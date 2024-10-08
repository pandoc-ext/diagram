### Mermaid

Mermaid is a JavaScript-based diagramming and charting tool.

``` mermaid
%%| filename: flowchart
%%| fig-cap: A simple flowchart.
%%{
  init: {
    'theme': 'base',
    'themeVariables': {
      'primaryColor': '#BB2528',
      'primaryTextColor': '#fff',
      'primaryBorderColor': '#7C0000',
      'lineColor': '#F8B229',
      'secondaryColor': '#006100',
      'tertiaryColor': '#fff'
    }
  }
}%%
graph TD;
    A-->B;
    A-->C;
    B-->D;
    C-->D;
```

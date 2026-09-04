# Examples

Four generated reports, each committed with the producer graph that produced
it, a screenshot, and the exact command that rebuilds it.

Open any `.html` straight from a clone. Every byte of the document comes from
PSGraphRender; this module maps and configures, and renders nothing itself.

Every command below is run **from the repository root**.

| Example | What it shows | Artifacts | Regenerate |
| --- | --- | --- | --- |
| **Nesting** | Three repositories, modules nested four deep via `parentId`, an unresolved `sources` edge carried rather than dropped, and a theme naming this producer's own classifications. | [html](nesting/nested.html) · [input](input/nested-graph.json) · [png](nesting/nested.png) | `pwsh -NoProfile -File examples/Build-Examples.ps1 -Only nesting` |
| **Precedence — built-ins** | No options at all. `foundation`, `structure`, `ZoomSpeed 1.25`, and every node in `KindColorFallback` because nothing names this producer's types. | [html](precedence/builtins.html) · [input](input/precedence-graph.json) · [png](precedence/builtins.png) | `pwsh -NoProfile -File examples/Build-Examples.ps1 -Only builtins` |
| **Precedence — defaults file** | The same graph and the same call, plus `-DefaultsRoot`. [`graphrender.defaults.psd1`](precedence/graphrender.defaults.psd1) moves three keys and a heat ramp; everything it does not name stays at its built-in. | [html](precedence/file-defaults.html) · [input](input/precedence-graph.json) · [png](precedence/file-defaults.png) | `pwsh -NoProfile -File examples/Build-Examples.ps1 -Only file` |
| **Precedence — explicit** | The same graph, the same defaults file, plus an explicit `-Options`. Layout, colouring and theme all change. | [html](precedence/explicit.html) · [input](input/precedence-graph.json) · [png](precedence/explicit.png) | `pwsh -NoProfile -File examples/Build-Examples.ps1 -Only explicit` |

Rebuild all four with `pwsh -NoProfile -File examples/Build-Examples.ps1`.

## Precedence, highest first

**explicit `-Options` > `graphrender.defaults.psd1` > built-in defaults.**

The three precedence reports are the same nine-node graph rendered three ways,
so any difference between them is the option system and nothing else:

| | Layout | ColorBy | ZoomSpeed | Node fill |
| --- | --- | --- | --- | --- |
| [built-ins](precedence/builtins.html) | `foundation` | `structure` | 1.25 | all fallback grey |
| [defaults file](precedence/file-defaults.html) | `testorder` | `blastRadius` | **2.5** | the file's heat ramp |
| [explicit](precedence/explicit.html) | `callflow` | `structure` | 1.25 | the options object's kind map |

### The part that surprises

Look at `ZoomSpeed` on the bottom row. The defaults file says `2.5`, the
defaults file is still in play, and the rendered document says **1.25**.

That is correct. `-Options` is not a patch — it is a **complete object**.
`New-GraphRenderOptions` fills every parameter it was not given with that
parameter's own default, so an explicit object outranks the file on every key,
including keys the caller never mentioned.

The whole-key merge that lets a three-line defaults file be meaningful is the
merge one level down, between the **file** and the **built-ins**: the
[defaults file](precedence/graphrender.defaults.psd1) names four things and
leaves `Backend`, `FocusDepth`, `NodeLimit`, `MinReadableZoom` and `Title`
exactly where they were.

## Colour is the producer's vocabulary, not this module's

`repository`, `module`, `variable`, `output`, `provider` and `local` are words
this example's graph made up. The renderer knows none of them, which is why
[built-ins](precedence/builtins.png) draws every node the same grey — nothing
had told it what those words are worth.

Naming them in a theme's `KindColor` map is the whole fix, and it is data:

```powershell
New-GraphRenderOptions -Theme @{
    KindColor = @{ repository = '#3b7fc4'; module = '#00a884'; variable = '#c98a1e' }
}
```

Compare [builtins.png](precedence/builtins.png) with
[explicit.png](precedence/explicit.png): same graph, same layout engine, one
hashtable.

## These reports are not byte-reproducible

Rebuilding produces a document that differs from the committed one in exactly
one field. `ConvertTo-GraphRenderViewModel` stamps `meta.generatedAt` from
`[DateTime]::UtcNow` and does not read the producer's own
`graph.meta.generatedUtc`, so the timestamp in the header is the moment of the
render rather than the moment of the scan.

To compare a rebuild against what is committed, normalise that one line:

```powershell
$a = (Get-Content examples/precedence/explicit.html -Raw) -replace '"generatedAt":\s*"[^"]*"', ''
```

Everything else — layout, options, colours, node and edge data — is
deterministic.

## No absolute paths

`graph.meta.roots` and every `node.path` in the committed inputs begin with the
literal `REPLACE-WITH-YOUR-CLONE-PATH`. A real producer emits real absolute
paths there, and those name the machine that ran the scan; these files are
meant to be read from a clone by someone who is not their author.

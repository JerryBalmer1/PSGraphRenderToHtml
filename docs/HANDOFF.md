# HANDOFF

**Read this first.** It assumes you know nothing about this repository.

## State, as of pass 0043

**Where it is.** v0.1.3, no tag taken this pass. `examples/` holds four
generated reports — one nesting demonstration and the three-way precedence
trio — each with its producer graph, a 1600x900 screenshot, and a paste-able
rebuild command. `README.md` leads with the nesting screenshot;
[`examples/README.md`](../examples/README.md) is the full index.

**What pass 0043 did here.** Documentation and generated artifacts only. **No
`src/` file was changed.**

**What it found, and did not fix.** Two things, both recorded rather than
touched:

1. **`meta.generatedAt` is a clock reading, not the producer's fact.**
   `ConvertTo-GraphRenderViewModel` sets it from `[DateTime]::UtcNow` and never
   reads `graph.meta.generatedUtc`, which the producer contract defines and
   every example input carries. Two renders of one unchanged graph therefore
   differ in one field, so these reports cannot be byte-compared — the examples
   index says so and gives the one-line normalisation. Whether the producer's
   scan time should win is a real question and nobody has been asked it.

2. **An explicit `-Options` beats the defaults file on every key**, including
   keys the caller never named, because `New-GraphRenderOptions` returns a
   complete object rather than a patch. This is defensible and it is not what
   a reader expects from "whole-key merge", which describes the level below.
   `examples/precedence/` now demonstrates it deliberately rather than leaving
   it to be discovered.

**Next.** Neither finding is a defect with a failing test behind it. Both want
a decision before any code moves.

## What this is

The battery between a producer and a renderer.

A producer — something that scans a domain and finds things and relationships —
emits a **producer graph**. This module validates it, maps it onto
PSGraphRender's view model, and hands it over to be rendered. It is the piece
that means a producer author never has to learn the render contract, and never
has to compute anything that can be derived.

Four exported commands:

| Command | Does |
| --- | --- |
| `Test-ProducerGraph` | validates a graph — schema and semantics — naming every violation with a JSON path |
| `New-GraphRenderOptions` | builds the options object: backend, layout, interaction, theme, editor links |
| `ConvertTo-GraphRenderViewModel` | maps a producer graph to a view model valid against PSGraphRender 1.1.0 |
| `Export-ProducerGraphHtml` | composes the two with the renderer, in one call |

`./build.ps1` is the only entry point.

## Contract

`contract/producer-graph.schema.json`, version **0.1.0**, versioned
independently of the module.

It is deliberately **smaller** than the render contract. The rule that decides
whether a field belongs: *if a producer would have to compute it rather than
observe it, it does not belong.* Depth is the worked example — it is a function
of the `parentId` chain, it is derived in `ConvertTo-GraphRenderViewModel` and
nowhere else, and a producer that stored it would have two sources of truth that
nothing would notice disagreeing. `additionalProperties` is `false` at every
level so a stored depth is a validation *error* rather than a field nobody reads.

Change protocol, mirroring the render contract's:

1. **Additive changes bump minor; shape changes bump major.** A field gained is
   minor. A field renamed, removed, or given a new type is major, and the old
   name survives as an alias with a `since` marker. **Removal is not an
   operation this contract has.**
2. A producer written for 0.1.0 must keep validating against every later 0.x.
3. `meta.contractVersion` is optional, and absent means NOT STATED — a payload
   written before the field existed must still validate.

What the schema cannot express is checked by `Test-ProducerGraph`: unique ids,
every edge endpoint resolving, acyclic `parentId` chains, and an edge marked
`resolved: false` that states no `reason`. **A schema-valid graph is not
necessarily a usable one**, which is why validation is one command and not one
`Test-Json`.

## Boundaries

- **It never parses a producer's domain.** It has never read a `.tf` file, a
  `.ps1` file or a pipeline YAML, and nothing in it may learn how. `type`,
  `scope` and `kind` are free strings this module never enumerates — the moment
  it enumerated them it would know what a producer's domain is, and a second
  producer would need a code change here.
- **It never emits HTML itself.** Every byte of a rendered document comes from
  PSGraphRender. What happens here is validation, mapping and configuration.
  There is no template, no markup and no styling in this repository.
- **It never modifies PSGraphRender.** Settings reach the renderer only through
  a template-set directory, so an option is applied by copying the chosen
  backend to a temporary overlay, merging the values, and passing
  `-TemplateSetPath`. That parameter exists precisely to make a backend the
  renderer does not ship possible. The overlay is removed after every render.
- **Containment is `parentId`, never an edge.** A `contains` edge and a
  `parentId` would be two statements of one fact. `Test-ProducerGraph` refuses
  the edge by name.
- **An unresolved reference is carried, never dropped.** A producer that
  silently drops what it could not resolve reports a graph that looks complete
  and is not. `resolved: false` plus a `reason` survives into the view model as
  `resolution: unresolved` and an entry in `data.unresolved`.

## Version ledger

| Version | What it marks |
| --- | --- |
| producer contract `0.1.0` | the first producer graph contract |
| `v0.1.0` | this module's first release. Contract, options, mapping, battery |

Consumes **PSGraphRender v0.13.0** (view model contract 1.1.0). The manifest
declares `ModuleVersion = '0.13.0'` in `RequiredModules`, which is a **floor**:
it accepts every version above it. That is deliberate — a pin would make every
renderer patch a breaking change here — and the battery is what catches an
incompatible one. PSGraphRender's own handoff names this floor-not-a-pin hazard;
it applies here too, and knowing it is the mitigation.

Module version: **patch** for a normal implementation, **minor** when a command,
an option or a contract field is added, **major** when the producer contract
changes shape.

## How it is operated

Plan-by-plan from the `AI.Agent.Claude.PowerShellModuleBuilder` harness project,
under its **decision 0010**. Work happens on a `pass-NNNN-*` branch; after a
green pass `main` is fast-forwarded with ancestry verified by
`git merge-base --is-ancestor`, never forced. No history rewrites, no
`Publish-Module`, no force pushes. There is no resident agent process here.

## The battery is the enforcement point

`tests/ProducerContract.Battery.ps1` is the reason this module exists as a
separate thing rather than as a helper inside a producer.

A producer does not *support* the contract because its author read the schema.
It supports the contract because the battery is green against its real output,
in its own build, on its own machine:

```powershell
Invoke-Pester -Container (New-PesterContainer `
    -Path <path>/tests/ProducerContract.Battery.ps1 `
    -Data @{ GraphPath = './output/graph.json' })
```

It is parameterised on a **file**, not an object, deliberately: a producer that
can hand it a file has serialised its graph, and serialisation is where the
shapes that only exist in memory stop being valid and start being caught.

Its last assertion is the one that earns its keep — that the graph maps to a
view model the *renderer* accepts. A graph can be perfectly valid against the
producer contract and still map to something PSGraphRender refuses. That is a
defect in **this** module, and a producer running the battery is what finds it.

## Open

- **One real producer has now run the battery.** PSTerraformGraph v0.2.0 runs
  it in its own build against its own output and passes 7/7, including the
  assertion that earns its keep: that the graph maps to a view model
  PSGraphRender accepts. Before that, every assertion had been exercised only
  against a hand-written sample and against violating graphs made by mutating a
  known-good one — and the sample was written by the same pass that wrote the
  contract, which is the weakest kind of evidence there is.

  What that does and does not settle: the contract fits a domain nobody had in
  mind while writing it, which was the open question. It is still **one**
  producer. Two would be a measurement.
- **The absent-versus-false rule was read as being about one field.** The schema
  states of an edge's `resolved` that absent means NOT STATED, and calls it the
  same rule the render contract uses for its optional fields — meaning it
  generally. PSTerraformGraph wrote `hasValidation: false` on every node that
  had no validation, and it cost 28 differences against a hand-authored oracle
  before anyone read the sentence as general. If the rule is meant to hold for
  every optional field in the producer contract, it should say so where a
  producer author will look, not once inside one field's description.
- **The producer contract has one producer's worth of design in it.** `type`,
  `scope`, `parentId` and four edge kinds were chosen against a Terraform-shaped
  and a PowerShell-shaped graph. The second real producer is what turns that
  from a claim into a measurement.
- **Nothing checks that the rendered page is *right*.** The integration tests
  assert a document was produced, is large, and contains its configuration.
  Whether the graph is laid out correctly, whether the links point where they
  claim, whether a reader can use it — no automated gate here sees any of that.
  PSGraphRender's own browser gate covers the renderer; nothing covers the
  mapping's effect on a drawn page.
- **`ConvertTo-GraphRenderViewModel` decides what becomes a metric by type.** A
  numeric attribute becomes a metric and everything else becomes a node
  property, because the render contract types `metrics` as numbers. A producer
  emitting a numeric-looking string gets a property where it expected a metric,
  and nothing warns.
- **The overlay copies a whole backend per render.** For the cytoscape backend
  that is roughly half a megabyte of vendored JavaScript copied to temp and
  deleted, every time. Correct, and wasteful if something ever renders in a
  loop.

## Consumers

| Repository | Status |
| --- | --- |
| PSTerraformGraph | **shipped.** v0.2.0. Runs the battery in its own build, 7/7 |
| PSModuleGraph | today renders through PSGraphRender directly; could move here |
| PSAzureDevOpsGraph | a candidate; emits a graph of pipelines and repositories |

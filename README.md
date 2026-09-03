# PSGraphRenderToHtml

**The battery between a producer and a renderer.** A producer says what it
found; this turns that into an interactive HTML report, and refuses the graph by
name when it cannot.

```powershell
Import-Module PSGraphRenderToHtml

Get-TfConfigurationGraph -Path ./infra |
    Export-ProducerGraphHtml -OutputPath ./report.html
```

## The one rule

**A producer states what it observed. Everything derivable is derived here.**

Depth is the worked example. It is a function of the `parentId` chain, so the
contract refuses to carry it — `additionalProperties` is `false`, and a node
with a `depth` field is a validation *error*. A stored depth and a parent chain
are two sources of truth for one fact, and nothing would notice them
disagreeing.

That rule is what keeps a producer small. It observes; it does not compute.

## The producer graph

`contract/producer-graph.schema.json`, version 0.1.0.

```json
{
  "graph": {
    "meta":  { "producer": "PSTerraformGraph", "producerVersion": "0.1.0" },
    "nodes": [
      { "id": "repo:app", "label": "app", "type": "repository", "scope": "app" },
      { "id": "app:root", "label": "root", "type": "module", "scope": "app",
        "parentId": "repo:app", "path": "C:/src/app/main.tf" }
    ],
    "edges": [
      { "from": "app:root", "to": "repo:app", "kind": "references" },
      { "from": "app:root", "to": "app:gone", "kind": "sources",
        "resolved": false, "reason": "source path exists in no scanned repository" }
    ]
  }
}
```

Four required node fields — `id`, `label`, `type`, `scope` — and three required
edge fields — `from`, `to`, `kind`. `type`, `scope` and `kind` are **free
strings**: this module never enumerates them, because the moment it did it would
know what a producer's domain is and a second producer would need a code change
here.

Containment is `parentId`, never an edge. An unresolved reference is carried
with a `reason`, never dropped.

## Commands

| Command | Does |
| --- | --- |
| `Test-ProducerGraph` | schema + semantic validation. Names every violation with a JSON path, returns a result object, never a bare `$true` |
| `New-GraphRenderOptions` | backend, layout, interaction knobs, theme, editor-link map |
| `ConvertTo-GraphRenderViewModel` | producer graph → view model valid against PSGraphRender 1.1.0 |
| `Export-ProducerGraphHtml` | all of the above plus the render, in one call |

```powershell
$result = Test-ProducerGraph -Path ./graph.json
$result.Violations | ForEach-Object { "$($_.Path): [$($_.Rule)] $($_.Message)" }
```

Layouts are the three the cytoscape backend implements — `foundation`,
`testorder`, `callflow` — plus the `plain` backend, which renders tables and
vendors nothing. Both lists were read out of PSGraphRender v0.13.0 rather than
written from memory.

```powershell
Export-ProducerGraphHtml -Path ./graph.json -OutputPath ./flow.html `
    -Options (New-GraphRenderOptions -Layout callflow -ZoomSpeed 2)
```

### Defaults a producer repository can declare

Drop `graphrender.defaults.psd1` at the producer's repository root:

```powershell
@{ Layout = 'callflow'; ZoomSpeed = 2.0 }
```

Precedence is **explicit options beat the file beat the built-ins**, merged per
key — a file that sets only `ZoomSpeed` leaves everything else at its built-in.
An unknown key is refused by name, because silently ignoring a typo reads as
"the setting did nothing" and costs somebody an afternoon.

## The battery

`tests/ProducerContract.Battery.ps1` is the ecosystem's enforcement point. A
producer runs it against its own real output, in its own build:

```powershell
Invoke-Pester -Container (New-PesterContainer `
    -Path ./tests/ProducerContract.Battery.ps1 `
    -Data @{ GraphPath = './output/graph.json' })
```

Its last assertion is the one that earns its keep: that the graph maps to a view
model **the renderer accepts**. A graph can be valid against the producer
contract and still map to something PSGraphRender refuses — that is a defect
here, and a producer running the battery is what finds it.

## Build and test

```powershell
./build.ps1                 # clean, lint, build, test
./build.ps1 -Task PreTag    # the gates that seal an iteration
```

Never call `Invoke-Pester` or `Invoke-Build` directly. `PSGraphRender` is
resolved from `$env:PSGRAPHRENDER_MODULE_PATH`, a sibling checkout, or the
module path — and the build **prints the version it resolved**, because
`RequiredModules` declares a floor and a floor accepts everything above it.

## Related repositories

| Repository | Relationship |
| --- | --- |
| [PSGraphRender](https://github.com/JerryBalmer1/PSGraphRender) | **consumed.** v0.13.0. Every byte of a rendered document comes from it; this module contains no markup |
| [PSTerraformGraph](https://github.com/JerryBalmer1/PSTerraformGraph) | **consumer.** v0.2.0, the first real producer. It emits against this contract and its build runs the battery; [run tf-002](https://github.com/JerryBalmer1/AI.Agent.Claude.PowerShellModuleBuilder/tree/main/runs/tf-002-convention-and-case3) scored it 7/7 on the fixture's named cases and 7/7 on this battery, and [run tf-003](https://github.com/JerryBalmer1/AI.Agent.Claude.PowerShellModuleBuilder/tree/main/runs/tf-003-generalisation) — a producer built fresh from the seed against an unseen fixture — passed this battery 7/7 and reached 7/7 on that fixture's cases after one iteration |
| [PSModuleGraph](https://github.com/JerryBalmer1/PSModuleGraph) | a producer that renders through PSGraphRender directly today; a candidate to move here |
| [PSAzureDevOpsGraph](https://github.com/JerryBalmer1/PSAzureDevOpsGraph) | a candidate producer — pipelines and repositories |
| AI.Agent.Claude.PowerShellModuleBuilder | the harness this repository is operated from. Its decision 0010 governs how `main` and tags move here |

**Nothing in that list except PSGraphRender is a dependency.** This module does
not import a producer and does not know what a Terraform resource, a PowerShell
module or a pipeline is.

## Where the reasoning lives

| File | Read it when |
| --- | --- |
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | **first.** What this is, the contract, the boundaries, how it is operated, what is open |
| [`contract/producer-graph.schema.json`](contract/producer-graph.schema.json) | writing a producer, or proposing a contract change. The schema is the authority |
| `docs/worklog/` | why a release did what it did |

This module vendors nothing and has no vendoring document. Third-party files
live in [PSGraphRender](https://github.com/JerryBalmer1/PSGraphRender), which
carries the provenance for all of them.

## Licence

MIT.

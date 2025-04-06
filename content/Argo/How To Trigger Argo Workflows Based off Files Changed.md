---
tags:
  - argo-workflows
  - kubernetes
---

This blog is written in Obsidian and published using Argo-Workflows and Github Pages. However, this blog is also only a single folder in my entire Obsidian Vault. 

As a brief example, consider the layout below...

```
obsidian
├── Blog
│   ├── Drafts
│   │   └── How To Trigger Argo Workflows Based of Files Changed.md
│   └── Published
│       ├── Kubernetes
│       │   ├── 7 Days Of Kubernetes.md
│       │   └── ... more kubernetes posts ...
│       ├── Recipes
│       │   └── Chicken Tikka Masala Pizza.md
│       ├── images
│       │   ├── Screenshot 2025-04-05 at 10.31.37 PM.png
│       │   └── ... more images...
│       ├── index.md
│       └── robots.txt
└── ... more notes ...

```

I also hide the [quartz 4 config](https://quartz.jzhao.xyz/) inside the `.obsidian/release/` path. 

In short, my argo-workflow copies into [my blog repo](https://github.com/oliverisaac/blog) using these rules:
- all files form `/.obsidian/release/` copied into `/`
- all files from `Blog/Published/` to `/content`
then pushes a new commit to that repo.

If I triggered my workflow every time the [obsidian-git plugin](https://github.com/Vinzent03/obsidian-git) made a backup commit for each note edit then I would quickly backup my workflow queue for a bunch of work that doesn't need to happen!

# Argo-Workflows' WorkflowEventBinding's Event Selector Field

The WorkflowEventBinding resource in Argo-Workflows has a [poorly documented field](https://argo-workflows.readthedocs.io/en/latest/events/#submitting-a-workflow-from-a-workflowtemplate) at the `.spec.event.selector` path. This field can be used to only trigger the event when the selector returns true.

I dug into [the source code](https://github.com/argoproj/argo-workflows/blob/6c4c49217d20655a6cad7cd5d59b9a870fb23fbe/pkg/apis/workflow/v1alpha1/event_types.go#L34-L37) and found that the selector field uses a syntax called `expr` [from the expr-lang project](https://github.com/expr-lang/expr). 

Expr-lang has [extensive documentation](https://expr-lang.org/docs/language-definition) on how to write expressions!

# WorkflowEventBinding Selector for Commits Which Modify a Subpath of Files

I now had everything I needed to write my selector! 

A github webhook payload has the `commits` array which includes metadata about each commit as well as a list of which files were modified:

```json
{
  ... [ insignficant data removed ] ...
  "commits": [
    {
      ... [ insignficant data removed ] ...
      "id": "8b7845fd7f9abbcfaa970a143aba0f47e588b379",
      "added": [
        "Blog/Published/index.md"
      ],
      "removed": [

      ],
      "modified": [
        ".obsidian/release/Dockerfile"
      ]
    }
  ]
}

```

We can then use the expr syntax to return true only when one of the commits affects a file that has the prefix `.obsidian/release/` or `Blog/Published/` as these are the only two paths that affect the blog!

The psuedocode for this might look like:

```psuedocode
for each prefix in [".obsidian/release/", "Blog/Published/"]:
    for each commit in commits:
        for each action in [added, removed, modified]:
            for each file in the action:
                if the file starts with the prefix:
                    return true
        
```

*(At first glance, this might appear to big-O of `O(n^4)` due to the deeply loops, but it's only `O(n*m)` because neither the length of prefixes nor actions will change. )*

Because we just want to return true if any instance of our files matches we can use expr's `any` syntax to handle the loops. 

To improve legibility and give us access to the variable in each [predicate](https://expr-lang.org/docs/language-definition#predicate) of each `any` we will the `let VARNAME = #` syntax to name the predicate's variable.


This leads to a workflow that looks like this with a crazy-long selector:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowEventBinding
metadata:
  name: blog-publish-webhook
  namespace: argo-workflow-jobs
spec:
  event:
    selector: >
      discriminator == "obsidian" 
      && metadata["x-github-event"] == ["push"]
      && any([ ".obsidian/release/", "Blog/Published/" ], {
          let prefix = #;
          any(payload.commits ?? [], {
            let commit = #;
            any(["added", "removed", "modified"], {
              let sel = #;
              any(commit[sel] ?? [], {
                let filepath = #;
                hasPrefix(filepath, prefix)
              })
            })
          })
        })
  submit:
    workflowTemplateRef:
      name: blog-publish
    arguments:
      parameters: []
```

---
Overall I'm happy to have discovered the expr language syntax and I'm excited to find place where I can leverage expr in my own tools to give them significant flexibility! It was mind-blowing being able to so precisely achieve my selector's goals without having to turn to hacky workarounds. Great work Argo team!
# Architecture Documentation

> A seamless integration of n8n workflow automation with GitHub Actions CI/CD -- turning a single `git push` into a live blog post with an AI-crafted LinkedIn announcement, with one intentional approval step before publishing.

---

## High-Level Architecture

At a glance, the system transforms a markdown file into a published blog post and LinkedIn announcement through two systems working in sequence:

```mermaid
graph LR
    A["Author pushes to Hugo repo"] --> C["GitHub Repository"]
    C --> E["GitHub Actions CI/CD"]
    E --> F["Live Website"]
    F -->|"n8n polls GitHub API"| WF1["WF1: Generate LinkedIn Draft"]
    WF1 -->|"saves draft"| WF2["WF2: Review & Publish"]
    WF2 -->|"author reviews via form"| H["LinkedIn Post"]

    style A fill:#99ccff,stroke:#333
    style F fill:#99ff99,stroke:#333
    style WF1 fill:#e6ffe6,stroke:#4a9e4a
    style WF2 fill:#fffbe6,stroke:#d4a017
    style H fill:#99ff99,stroke:#333
```

| Layer | System | Responsibility |
|---|---|---|
| **Build & Deploy** | GitHub Actions | Hugo build, static site deployment |
| **Detection + AI Draft** | n8n WF1: Generate LinkedIn Draft | Polls for new commits, fetches content, AI generates draft, saves to queue |
| **Review + Publish** | n8n WF2: Review & Publish to LinkedIn | Form-based review, author approves/rejects, publishes to LinkedIn |

**The key insight**: n8n WF1 polls the Pages repo for new commits. A new commit means deployment is complete. WF1 fetches the post content from the source repo, generates an AI LinkedIn draft, and saves it to a FIFO queue. WF2 provides a form-based review UI where the author can edit, approve, or reject the draft before it goes live on LinkedIn.

---

## High-Level System Flow

```
                    ┌─────────────────────────────────────────────┐
                    │            AUTHOR'S MACHINE                  │
                    │                                              │
                    │   1. Write markdown post                     │
                    │   2. git add + commit + push                 │
                    │                                              │
                    └──────────────────┬───────────────────────────┘
                                       │
                              git push │
                                       │
                    ┌──────────────────▼───────────────────────────┐
                    │          GITHUB CLOUD                         │
                    │                                               │
                    │   ┌─────────────────────┐                     │
                    │   │  GitHub Actions      │                    │
                    │   │  Hugo Build + Deploy │                    │
                    │   └──────────┬──────────┘                     │
                    │              │                                 │
                    │     push to Pages repo                        │
                    │              │                                 │
                    │   ┌──────────▼──────────┐                     │
                    │   │  GitHub Pages        │──── Website Live    │
                    │   └─────────────────────┘                     │
                    │                                               │
                    └───────────────────────────────────────────────┘
                                       ▲
                            polls every │ 5 min
                                       │
                    ┌──────────────────┴────────────────────────────┐
                    │          n8n (Docker)                          │
                    │                                               │
                    │   WF1: Generate LinkedIn Draft                 │
                    │   Poll → Detect → Fetch → AI → Save Draft     │
                    │                                               │
                    │   WF2: Review & Publish to LinkedIn            │
                    │   Form → Review → Approve/Reject → Publish    │
                    │   http://localhost:5678/form/linkedin-review-form
                    │                                               │
                    └──────────────────┬────────────────────────────┘
                                       │
                    ┌──────────────────▼──────────┐
                    │     LinkedIn Feed            │
                    │     (AI-Generated Post)      │
                    └─────────────────────────────┘
```

---

## Low-Level Architecture

### Complete System Component Diagram

```
┌─── GITHUB CLOUD ────────────────────────────────────────────────────────────┐
│                                                                              │
│  ┌── whataboutadarsh ────────────┐     ┌── thatsmeadarsh.github.io ──────┐  │
│  │  content/posts/*.md           │     │  Static HTML files              │  │
│  │  GitHub Actions (hugo.yml)    │────▶│  GitHub Pages CDN               │  │
│  └───────────────────────────────┘     │  REST API: /commits/main        │  │
│               ▲ GET raw .md            └─────────────────────────────────┘  │
│               │                                      │ polls every 5 min    │
└───────────────┼──────────────────────────────────────┼──────────────────────┘
                │                                      │
┌───────────────┼── DOCKER (n8n v2.11.4) ──────────────▼──────────────────────┐
│               │                                                              │
│  ┌── WF1: Generate LinkedIn Draft ───────────────────────────────────────┐  │
│  │            │                                                           │  │
│  │            │   Schedule Trigger                                        │  │
│  │            │         │                                                 │  │
│  │            │   Fetch Latest Deployment                                 │  │
│  │            │         │                                                 │  │
│  │            │   Extract New Post Slugs                                  │  │
│  │            │         │                                                 │  │
│  │            └── Fetch Post Markdown                                     │  │
│  │                       │                                                │  │
│  │                 Parse Frontmatter                                      │  │
│  │                       │                                                │  │
│  │          draft=true ──┤── draft=false                                  │  │
│  │               │                  │                                     │  │
│  │             Skip         Prepare HF Request                            │  │
│  │                                  │                                     │  │
│  │                          HuggingFace Call ───────▶ HuggingFace Router  │  │
│  │                                  │◀── AI post text   SambaNova / Llama│  │
│  │                          Save Draft for Review                         │  │
│  │                          (pendingDrafts queue)                         │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                      │                                       │
│                          n8n REST API │ (read static data)                   │
│                                      ▼                                       │
│  ┌── WF2: Review & Publish to LinkedIn ──────────────────────────────────┐  │
│  │                                                                        │  │
│  │   Load Draft (Form Trigger page 1)                                     │  │
│  │         │                                                              │  │
│  │   Fetch Draft from WF1 (HTTP GET n8n API)                              │  │
│  │         │                                                              │  │
│  │   Extract Latest Draft (Code, FIFO)                                    │  │
│  │         │                                                              │  │
│  │   Review & Edit (Form page 2, pre-filled)                              │  │
│  │         │                                                              │  │
│  │   Approved? ──────────────────────────┐                                │  │
│  │         │ true                         │ false                         │  │
│  │   Get LinkedIn Profile ──▶ LinkedIn   Rejected (NoOp)                  │  │
│  │         │◀── person URN     API       │                                │  │
│  │   Prepare LinkedIn Post               │                                │  │
│  │         │                             │                                │  │
│  │   POST /v2/ugcPosts ────▶ LinkedIn   │                                │  │
│  │         │                  API        │                                │  │
│  │         └─────────────────────────────┘                                │  │
│  │                     │                                                  │  │
│  │         Fetch Draft for Cleanup                                        │  │
│  │         Prepare Queue Cleanup                                          │  │
│  │         Remove Draft from Queue (PUT n8n API)                          │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│   Form URL: http://localhost:5678/form/linkedin-review-form                  │
└──────────────────────────────────────────────────────────────────────────────┘
                    │                               │
                    ▼                               ▼
        thatsmeadarsh.github.io             LinkedIn Feed
        (live blog post)                    (AI announcement)
```

---

### Low-Level: GitHub Actions Pipeline

The `whataboutadarsh` repo contains a GitHub Actions workflow that triggers on every push to `main`. This is the **build and deploy** engine.

```mermaid
graph TD
    subgraph Trigger["Trigger"]
        T[Push to main branch]
    end

    subgraph Build["Build Phase"]
        CO[Checkout with submodules]
        HS[Setup Hugo latest extended]
        DL[Download Contentful JSON]
        CD[Commit data folder]
        PD[Push data changes]
        RC[Delete Hugo cache]
        HB[Run hugo --buildFuture]
    end

    subgraph Deploy["Deploy Phase"]
        CL[Clone thatsmeadarsh.github.io]
        RM[Clear target repo]
        CY[Copy public/ to target]
        CM[Commit site content]
        PS[Push to Pages repo]
    end

    subgraph Live["Auto-Deploy"]
        PA[GitHub Pages Action triggers]
        WB[Website goes live]
    end

    T --> CO --> HS --> DL --> CD --> PD
    PD --> RC --> HB --> CL --> RM --> CY --> CM --> PS
    PS -->|push triggers| PA --> WB

    style Trigger fill:#ff9999,stroke:#333
    style Build fill:#99ccff,stroke:#333
    style Deploy fill:#ffcc66,stroke:#333
    style Live fill:#99ff99,stroke:#333
```

**Key Details**:

| Step | Action | Purpose |
|---|---|---|
| Checkout | `actions/checkout@v4` with submodules | Fetches Hugo theme as git submodule |
| Contentful | `curl` to Contentful CDN | Downloads latest services data for the Services page |
| Hugo Build | `hugo --buildFuture` | Compiles markdown + Ananke theme into static HTML, including future-dated posts |
| Cross-Repo Push | `git push` with PAT | Pushes built HTML to the GitHub Pages repository |
| Authentication | `PERSONAL_ACCESS_TOKEN` secret | Enables cross-repository push access |
| public/ ignored | `.gitignore` excludes `public/` | Build artifacts not tracked in source repo; Pages repo updated via cross-repo push |

### Low-Level: n8n Workflow Pipeline

The n8n workflow handles everything after deployment -- polling for changes, fetching content, AI generation, and social media publishing.

#### WF1: Generate LinkedIn Draft (10 nodes)

```mermaid
graph TD
    ST[Poll Every 5 Minutes] --> FD[Fetch Latest Deployment]
    FD --> ES[Extract New Post Slugs]
    ES --> FM[Fetch Post Markdown]
    FM --> PF[Parse Frontmatter]
    PF --> DC{Is Not Draft?}
    DC -->|true| PR[Prepare HF Request]
    DC -->|false| SK[Skip - Draft]
    PR --> HF[AI Generate LinkedIn Post]
    HF --> SD[Save Draft for Review]

    style ST fill:#f0e6ff,stroke:#8a4ac8
    style FD fill:#f0e6ff,stroke:#8a4ac8
    style ES fill:#e6f3ff,stroke:#4a86c8
    style FM fill:#f0f0e6,stroke:#999
    style PF fill:#f0f0e6,stroke:#999
    style DC fill:#fff3e6,stroke:#e8a020
    style SK fill:#f0f0f0,stroke:#999
    style PR fill:#e6ffe6,stroke:#4a9e4a
    style HF fill:#e6ffe6,stroke:#4a9e4a
    style SD fill:#fffbe6,stroke:#d4a017
```

![WF1: Generate LinkedIn Draft](../screenshots/generate-linkedin-draft-n8n.png)

#### WF2: Review & Publish to LinkedIn (10 nodes)

```mermaid
graph TD
    LD[Load Draft - Form Trigger page 1] --> FD[Fetch Draft from WF1 - HTTP GET n8n API]
    FD --> EX[Extract Latest Draft - Code FIFO]
    EX --> RE[Review & Edit - Form page 2 pre-filled]
    RE --> AP{Approved?}
    AP -->|true| GL[Get LinkedIn Profile]
    GL --> PL[Prepare LinkedIn Post]
    PL --> LI[Post to LinkedIn]
    AP -->|false| RJ[Rejected - NoOp]
    LI --> FC[Fetch Draft for Cleanup]
    RJ --> FC
    FC --> PC[Prepare Queue Cleanup]
    PC --> RM[Remove Draft from Queue - PUT n8n API]

    style LD fill:#f0e6ff,stroke:#8a4ac8
    style FD fill:#f0e6ff,stroke:#8a4ac8
    style EX fill:#e6f3ff,stroke:#4a86c8
    style RE fill:#fffbe6,stroke:#d4a017
    style AP fill:#fff3e6,stroke:#e8a020
    style GL fill:#ffe6f0,stroke:#c84a86
    style PL fill:#ffe6f0,stroke:#c84a86
    style LI fill:#ffe6f0,stroke:#c84a86
    style RJ fill:#f0f0f0,stroke:#999
    style FC fill:#e6f3ff,stroke:#4a86c8
    style PC fill:#e6f3ff,stroke:#4a86c8
    style RM fill:#e6f3ff,stroke:#4a86c8
```

![WF2: Review & Publish to LinkedIn](../screenshots/review-and-publish-linkedin-n8n.png)

---

## System Flow Diagram (Sequence)

```mermaid
sequenceDiagram
    actor Author
    participant HugoRepo as GitHub Hugo Repo
    participant Actions as GitHub Actions
    participant PagesRepo as GitHub Pages Repo
    participant WF1 as n8n WF1: Generate Draft
    participant WF2 as n8n WF2: Review & Publish
    participant HF as HuggingFace API
    participant LinkedIn as LinkedIn API

    Note over Author,PagesRepo: Pipeline 1 — Build and Deploy
    Author->>HugoRepo: git push to main
    HugoRepo->>Actions: Triggers workflow
    activate Actions
    Actions->>Actions: Checkout + setup Hugo
    Actions->>Actions: Download Contentful data
    Actions->>Actions: Run hugo --buildFuture
    Actions->>PagesRepo: Push built HTML (cross-repo)
    deactivate Actions
    Note right of PagesRepo: GitHub Pages deploys — site is live

    Note over WF1,HF: Pipeline 2 — WF1: Detection + AI Draft
    loop Every 5 minutes
        WF1->>PagesRepo: GET /repos/.../commits/main
        PagesRepo-->>WF1: Commit SHA + changed files
    end
    Note over WF1: New SHA detected — new deployment

    WF1->>HugoRepo: GET raw markdown for new post
    HugoRepo-->>WF1: Markdown with frontmatter

    alt draft = false
        WF1->>HF: POST chat/completions (Llama 3.1)
        activate HF
        HF-->>WF1: AI-generated LinkedIn post text
        deactivate HF
        Note over WF1: Saves draft to pendingDrafts queue (static data)
    else draft = true
        Note over WF1: Skip — no LinkedIn draft
    end

    Note over Author,LinkedIn: Pipeline 3 — WF2: Form Review + Publish
    Author->>WF2: Opens form URL (localhost:5678/form/linkedin-review-form)
    WF2->>WF1: GET static data via n8n REST API (internal API key)
    WF1-->>WF2: pendingDrafts queue
    Note over WF2: Extracts latest draft (FIFO), pre-fills form
    WF2->>Author: Shows review form with draft text
    Author->>WF2: Reviews, edits, approves or rejects

    alt approved
        WF2->>LinkedIn: GET /v2/userinfo
        LinkedIn-->>WF2: Person URN
        WF2->>LinkedIn: POST /v2/ugcPosts
        LinkedIn-->>WF2: Post URN (published)
        Note right of LinkedIn: Post live with article card preview
    else rejected
        Note over WF2: No LinkedIn post
    end
    WF2->>WF1: PUT static data via n8n REST API (remove draft from queue)
```

---

## Integration Highlight: n8n + GitHub Actions

> **How we bridged workflow automation with CI/CD to create a zero-touch publishing pipeline**

```mermaid
graph TB
    subgraph Bridge["The Bridge: GitHub API Polling"]
        FW["n8n polls commits — new commit means deployment complete"]
    end

    subgraph GitHubActions["GitHub Actions: Build and Deploy"]
        direction TB
        GA1["Triggered by git push to Hugo repo"]
        GA2["Builds Hugo static site"]
        GA3["Deploys to GitHub Pages"]
        GA4["Output: Live website"]
        GA1 --> GA2 --> GA3 --> GA4
    end

    subgraph n8nWF1["n8n WF1: Generate LinkedIn Draft"]
        direction TB
        N1["Triggered by new commit detected via polling"]
        N2["Fetches and parses blog content"]
        N3["AI generates LinkedIn draft"]
        N4["Saves draft to pendingDrafts queue"]
        N1 --> N2 --> N3 --> N4
    end

    subgraph n8nWF2["n8n WF2: Review & Publish"]
        direction TB
        N5["Author opens form URL"]
        N6["Form-based review with pre-filled draft"]
        N7["Approve -> posts to LinkedIn"]
        N5 --> N6 --> N7
    end

    GitHubActions -->|"commit to Pages repo"| Bridge
    Bridge -->|"new commit detected"| n8nWF1
    n8nWF1 -->|"draft saved to static data"| n8nWF2

    style Bridge fill:#ffcc66,stroke:#333
    style GitHubActions fill:#e6f3ff,stroke:#4a86c8
    style n8nWF1 fill:#e6ffe6,stroke:#4a9e4a
    style n8nWF2 fill:#fffbe6,stroke:#d4a017
```

### Why This Integration Works

| Principle | Implementation |
|---|---|
| **Separation of concerns** | GitHub Actions handles CI/CD. n8n handles detection, AI, and social. |
| **No duplication** | Build and deploy happen only in GitHub Actions. AI and social happen only in n8n. |
| **Deployment guarantee** | n8n only fires after a new commit appears on the Pages repo, meaning deployment is complete. |
| **No host dependencies** | No file watcher, no tunnels, no background processes. Just `git push` and Docker. |
| **Fault isolation** | If LinkedIn posting fails, the website is still live. If GitHub Actions fails, n8n sees no new commit. |
| **One intentional manual step** | After `git push`, WF1 runs automatically up to saving the draft. The author opens a form URL, reviews the AI-generated text, and approves or rejects via WF2 -- by design, not by accident. |
| **Corporate-friendly** | Polling uses outbound HTTPS only -- works behind corporate proxies and firewalls. |

---

## Security Architecture

```mermaid
graph LR
    subgraph Secrets["Credential Storage"]
        GS["GitHub Secrets: PERSONAL_ACCESS_TOKEN"]
        NC["n8n Credential Store: GitHub, LinkedIn, HuggingFace, n8n Internal API Key"]
    end

    subgraph Access["Access Scope"]
        GS --> GHA["GitHub: repo + workflow scope"]
        NC --> GTA["GitHub: repo read scope"]
        NC --> LIA["LinkedIn: w_member_social only"]
        NC --> HFA["HuggingFace: Inference only"]
        NC --> N8A["n8n API: Workflow read/write (static data)"]
    end

    style Secrets fill:#fff3e6,stroke:#333
    style Access fill:#e6ffe6,stroke:#333
```

| Secret | Location | Scope | Expiry |
|---|---|---|---|
| GitHub PAT (Actions) | GitHub repo secret (`PERSONAL_ACCESS_TOKEN`) | `repo` + `workflow` | Configurable (90 days recommended) |
| GitHub PAT (n8n) | n8n credential store | `repo` (read access for commits + raw files) | Configurable |
| HuggingFace token | n8n credential store | Inference Providers only | No expiry |
| LinkedIn OAuth2 | n8n credential store (encrypted) | `w_member_social` | 2 months (auto-refreshed by n8n) |
| n8n Internal API Key | n8n credential store | Workflow read/write (static data access) | No expiry |

### Security Boundaries

- **n8n** runs in Docker locally -- no public exposure needed
- **All connections are outbound** -- no inbound ports, no tunnels, corporate-firewall-friendly
- **n8n** runs with `NODE_TLS_REJECT_UNAUTHORIZED=0` (container-scoped, not host)
- **GitHub PAT** is stored in GitHub's encrypted secrets and n8n's encrypted credential store

---

## How Post URLs Are Constructed

A key property of this system is that post URLs are **derived automatically from the deployed file path** -- no configuration or guessing involved.

### The Hugo URL Contract

Hugo's static site generator has a deterministic output structure. Given a source file, the output path (and therefore the live URL) is always predictable:

```
Source repo                          Pages repo                    Live URL
─────────────────────────────────────────────────────────────────────────────
content/posts/{slug}.md    →    posts/{slug}/index.html    →    /posts/{slug}/
```

### How n8n Exploits This

When GitHub Actions pushes the built site to the Pages repo, the commit's `files[]` array lists every file that was added. n8n reads this list and applies a regex to extract the slug:

```
Commit files[]:
  "posts/building-auto-publish/index.html"   ← status: added
  "posts/building-auto-publish/cover.jpg"    ← status: added  (ignored)
  "index.html"                               ← status: modified (ignored)
  "sitemap.xml"                              ← status: modified (ignored)

Regex: /^posts\/([^\/]+)\/index\.html$/
           ↑ only post index files
                    ↑ capture group = slug

Result: slug = "building-auto-publish"
```

Then the URL is assembled:

```
"https://thatsmeadarsh.github.io" + "/posts/" + slug + "/"
= "https://thatsmeadarsh.github.io/posts/building-auto-publish/"
```

### Why This Is Reliable

| Property | Guarantee |
|---|---|
| **Deterministic** | Same source filename always produces the same URL |
| **Source of truth** | URL is derived from the actual deployed file, not a guess |
| **Always accurate** | n8n only fires after the Pages repo receives the commit, so the URL is already live |
| **No configuration** | No URL mapping needed -- the file path IS the URL path |

### Example End-to-End

```
Author writes:  content/posts/building-n8n-auto-publish.md
                         │
                         ▼
Hugo builds:    posts/building-n8n-auto-publish/index.html
                         │
                         ▼
Pages repo commit files[]:
  "posts/building-n8n-auto-publish/index.html"  ← added
                         │
                         ▼
n8n extracts slug:  "building-n8n-auto-publish"
                         │
                         ▼
Post URL:  "https://thatsmeadarsh.github.io/posts/building-n8n-auto-publish/"
                         │
                         ▼
LinkedIn scheduled post includes article link:
  originalUrl: "https://thatsmeadarsh.github.io/posts/building-n8n-auto-publish/"
```

---

## LinkedIn Review & Approval Flow

Rather than publishing immediately or using LinkedIn's scheduled post API (which requires special partner permissions), the system uses a **two-workflow architecture** with a **form-based review step**. WF1 saves AI-generated drafts to a queue, and WF2 presents them to the author via an n8n form for review.

```
WF1: Generate LinkedIn Draft
              │
    AI generates LinkedIn post text
              │
              ▼
    Save Draft for Review
    (appends to pendingDrafts queue in static data)

              ── cross-workflow boundary ──

WF2: Review & Publish to LinkedIn
              │
    Author opens http://localhost:5678/form/linkedin-review-form
              │
              ▼
    Load Draft (Form Trigger page 1)
              │
    Fetch Draft from WF1 (HTTP GET n8n REST API)
              │
    Extract Latest Draft (FIFO from queue)
              │
    Review & Edit (Form page 2, pre-filled with draft text)
              │
    ┌─────────┴──────────────┐
    │                        │
    ▼                        ▼
 Approve                  Reject
    │                        │
    ▼                        ▼
LinkedIn post goes live    No post published
with article link preview
    │                        │
    └────────────┬───────────┘
                 ▼
    Remove Draft from Queue
    (PUT n8n REST API to update WF1 static data)
```

**The article link card** (title + description + thumbnail) is automatically generated by LinkedIn when it crawls the `originalUrl`. Since the URL is already live when WF1 fires, the preview renders correctly.

**Why not LinkedIn scheduled posts?** LinkedIn's `scheduledPublishTime` field in the UGC Posts API requires a special "Scheduled Sharing" permission that is only available to LinkedIn Marketing Partners. Standard developer apps receive a `403 Forbidden — Unpermitted fields: /scheduledPublishTime` error.

**Why not a Wait node?** n8n 2.11.4 has a known SQLite bug (`SQLITE_ERROR: no such table: main.execution_data`) when using Wait or Form Trigger nodes in certain configurations. The two-workflow split with n8n REST API communication avoids this entirely while providing a cleaner form-based UX.

---

## Design Decisions

| Decision | Rationale |
|---|---|
| **Polling over webhooks** | No tunnel or public URL required. Works behind corporate firewalls. Only outbound HTTPS needed. |
| **5-minute poll interval** | Balances responsiveness with API rate limits. GitHub allows 5000 authenticated requests/hour. |
| **Watch Pages repo, not Hugo repo** | Ensures the website is actually live before announcing on LinkedIn. |
| **Fetch markdown from source repo** | The Pages repo only has built HTML. The source repo has the original markdown with frontmatter for AI context. |
| **Static data for state tracking** | n8n's `$getWorkflowStaticData()` persists the last processed commit SHA between polls. |
| **GitHub Actions for build/deploy** | Already configured and tested; Hugo + cross-repo push is complex to replicate elsewhere |
| **n8n for detection + AI + social** | Keeps n8n focused on what it excels at: API orchestration and conditional logic |
| **HTTP Request nodes over LinkedIn node** | Built-in LinkedIn node doesn't support "Ignore SSL Issues" needed in Docker |
| **Code nodes for JSON construction** | Blog content contains special characters that break inline JSON templates |
| **SambaNova via HuggingFace Router** | Free tier, fast inference, OpenAI-compatible API format |
| **Draft check in n8n** | Allows deploying draft posts to test site rendering without triggering LinkedIn |
| **Two-workflow split** | Avoids n8n 2.11.4's SQLite bug with Wait/Form nodes in a single workflow; provides cleaner separation between automated detection and human review |
| **Form-based review over Wait node** | n8n 2.11.4 has a `SQLITE_ERROR: no such table: main.execution_data` bug when using Wait nodes; form-based review in a separate workflow provides a better UX and avoids the bug entirely |
| **FIFO draft queue** | `pendingDrafts` array in static data handles multiple drafts if the author pushes several posts before reviewing; oldest draft is presented first |
| **n8n REST API for cross-workflow data** | WF2 reads WF1's static data via the n8n internal API (`/api/v1/workflows/{id}`), avoiding the need for an external database or shared file system |
| **`--buildFuture` flag on Hugo build** | Ensures posts with a future-dated frontmatter timestamp are included in the build |
| **`public/` in `.gitignore`** | Build artifacts are generated fresh by GitHub Actions on every run; committing them to the source repo was redundant and caused merge conflicts |
| **`actions/checkout@v4` + `peaceiris/actions-hugo@v3`** | Updated from v3/v2 to maintain Node.js 24 compatibility ahead of GitHub's June 2026 forced migration |

---

*Last Updated: 2026-03-15*
*Project: n8n-Powered Auto Web Publish*

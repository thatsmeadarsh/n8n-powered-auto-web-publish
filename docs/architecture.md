# Architecture Documentation

> A seamless integration of n8n workflow automation with GitHub Actions CI/CD -- turning a single `git push` into a live blog post with an AI-crafted LinkedIn announcement, all without manual intervention.

---

## High-Level Architecture

At a glance, the system transforms a markdown file into a published blog post and LinkedIn announcement through two systems working in sequence:

```mermaid
graph LR
    A["Author pushes to Hugo repo"] --> C["GitHub Repository"]
    C --> E["GitHub Actions CI/CD"]
    E --> F["Live Website"]
    F -->|"n8n polls GitHub API"| D["n8n Workflow Engine"]
    D --> G["AI Content Generation"]
    G --> H["LinkedIn Post"]

    style A fill:#99ccff,stroke:#333
    style F fill:#99ff99,stroke:#333
    style H fill:#99ff99,stroke:#333
```

| Layer | System | Responsibility |
|---|---|---|
| **Build & Deploy** | GitHub Actions | Hugo build, static site deployment |
| **Detection** | n8n polling GitHub API | Detects new commits on the Pages repo every 5 minutes |
| **AI & Social** | n8n + Hugging Face + LinkedIn | Fetch post, AI summary generation, social publishing |

**The key insight**: n8n polls the Pages repo for new commits. A new commit means deployment is complete. n8n then fetches the post content from the source repo, generates an AI summary, and publishes to LinkedIn -- only after the site is live.

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
                    │   Poll GitHub API → Detect new commit         │
                    │   → Fetch markdown → AI summary               │
                    │   → LinkedIn publish                          │
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
│               │   Schedule Trigger                                           │
│               │         │                                                    │
│               │   Fetch Latest Deployment                                    │
│               │         │                                                    │
│               │   Extract New Post Slugs                                     │
│               │         │                                                    │
│               └── Fetch Post Markdown                                        │
│                          │                                                   │
│                    Parse Frontmatter                                         │
│                          │                                                   │
│             draft=true ──┤── draft=false                                     │
│                  │                  │                                        │
│                Skip         Prepare HF Request                               │
│                                     │                                        │
│                             HuggingFace Call ───────▶ HuggingFace Router    │
│                                     │◀── AI post text   SambaNova / Llama   │
│                             Format LinkedIn Post                             │
│                                     │                                        │
│                             Wait for Approval                                │
│                         (author resumes via n8n UI)                         │
│                                     │                                        │
│                             Get LinkedIn Profile ───▶ LinkedIn API          │
│                                     │◀── person URN     OAuth2              │
│                             Prepare LinkedIn Post                            │
│                                     │                                        │
│                             POST /v2/ugcPosts ──────▶ LinkedIn API          │
│                                                        UGC Posts             │
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

```mermaid
graph TD
    ST[Schedule Trigger] --> FD[Fetch Latest Deployment]
    FD --> ES[Extract New Post Slugs]
    ES --> FM[Fetch Post Markdown]
    FM --> PF[Parse Frontmatter]
    PF --> DC{Is Not Draft?}
    DC -->|true| PR[Prepare HF Request]
    DC -->|false| SK[Skip]
    PR --> HF[AI Generate LinkedIn Post]
    HF --> FL[Format LinkedIn Post]
    FL --> WA[Wait for Approval]
    WA --> GL[Get LinkedIn Profile]
    GL --> PL[Prepare LinkedIn Post]
    PL --> LI[Post to LinkedIn]

    style ST fill:#f0e6ff,stroke:#8a4ac8
    style FD fill:#f0e6ff,stroke:#8a4ac8
    style ES fill:#e6f3ff,stroke:#4a86c8
    style FM fill:#f0f0e6,stroke:#999
    style PF fill:#f0f0e6,stroke:#999
    style DC fill:#fff3e6,stroke:#e8a020
    style SK fill:#f0f0f0,stroke:#999
    style PR fill:#e6ffe6,stroke:#4a9e4a
    style HF fill:#e6ffe6,stroke:#4a9e4a
    style FL fill:#e6ffe6,stroke:#4a9e4a
    style WA fill:#fffbe6,stroke:#d4a017
    style GL fill:#ffe6f0,stroke:#c84a86
    style PL fill:#ffe6f0,stroke:#c84a86
    style LI fill:#ffe6f0,stroke:#c84a86
```

---

## System Flow Diagram (Sequence)

```mermaid
sequenceDiagram
    actor Author
    participant HugoRepo as GitHub Hugo Repo
    participant Actions as GitHub Actions
    participant PagesRepo as GitHub Pages Repo
    participant n8n as n8n (Docker)
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

    Note over n8n,LinkedIn: Pipeline 2 — Detection, AI, and Social
    loop Every 5 minutes
        n8n->>PagesRepo: GET /repos/.../commits/main
        PagesRepo-->>n8n: Commit SHA + changed files
    end
    Note over n8n: New SHA detected — new deployment

    n8n->>HugoRepo: GET raw markdown for new post
    HugoRepo-->>n8n: Markdown with frontmatter

    alt draft = false
        n8n->>HF: POST chat/completions (Llama 3.1)
        activate HF
        HF-->>n8n: AI-generated LinkedIn post text
        deactivate HF
        Note over n8n: Execution pauses at Wait for Approval node
        Author->>n8n: Opens localhost:5678, goes to Executions tab
        Author->>n8n: Finds Waiting execution, copies resumeUrl
        Author->>n8n: Opens resumeUrl in browser to approve
        Note over n8n: Execution resumes
        n8n->>LinkedIn: GET /v2/userinfo
        LinkedIn-->>n8n: Person URN
        n8n->>LinkedIn: POST /v2/ugcPosts
        LinkedIn-->>n8n: Post URN (published)
        Note right of LinkedIn: Post live with article card preview
    else draft = true
        Note over n8n: Skip — no LinkedIn post
    end
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

    subgraph n8nWorkflow["n8n: Detection, AI and Social Media"]
        direction TB
        N1["Triggered by new commit detected via polling"]
        N2["Fetches and parses blog content"]
        N3["AI generates LinkedIn summary"]
        N4["Approval gate then posts to LinkedIn"]
        N1 --> N2 --> N3 --> N4
    end

    GitHubActions -->|"commit to Pages repo"| Bridge
    Bridge -->|"new commit detected"| n8nWorkflow

    style Bridge fill:#ffcc66,stroke:#333
    style GitHubActions fill:#e6f3ff,stroke:#4a86c8
    style n8nWorkflow fill:#e6ffe6,stroke:#4a9e4a
```

### Why This Integration Works

| Principle | Implementation |
|---|---|
| **Separation of concerns** | GitHub Actions handles CI/CD. n8n handles detection, AI, and social. |
| **No duplication** | Build and deploy happen only in GitHub Actions. AI and social happen only in n8n. |
| **Deployment guarantee** | n8n only fires after a new commit appears on the Pages repo, meaning deployment is complete. |
| **No host dependencies** | No file watcher, no tunnels, no background processes. Just `git push` and Docker. |
| **Fault isolation** | If LinkedIn posting fails, the website is still live. If GitHub Actions fails, n8n sees no new commit. |
| **One intentional manual step** | After `git push`, everything runs automatically up to the LinkedIn approval gate. The author reviews and resumes the waiting execution in n8n before the post goes live -- by design, not by accident. |
| **Corporate-friendly** | Polling uses outbound HTTPS only -- works behind corporate proxies and firewalls. |

---

## Security Architecture

```mermaid
graph LR
    subgraph Secrets["Credential Storage"]
        GS["GitHub Secrets: PERSONAL_ACCESS_TOKEN"]
        NC["n8n Credential Store: GitHub, LinkedIn, HuggingFace"]
    end

    subgraph Access["Access Scope"]
        GS --> GHA["GitHub: repo + workflow scope"]
        NC --> GTA["GitHub: repo read scope"]
        NC --> LIA["LinkedIn: w_member_social only"]
        NC --> HFA["HuggingFace: Inference only"]
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

Rather than publishing immediately or using LinkedIn's scheduled post API (which requires special partner permissions), the workflow pauses at an n8n **Wait node** and resumes only when the author explicitly approves from the n8n UI.

```
n8n generates AI LinkedIn post text
              │
              ▼
Wait for Approval node (lifecycleState paused in n8n)
              │
              │  Author opens http://localhost:5678
              │  Executions → find "Waiting" execution
              │  Click node → copy resumeUrl → open in browser
              │
    ┌─────────┴──────────────┐
    │                        │
    ▼                        ▼
 Approve                 Don't approve
 (visit resumeUrl)       (let execution expire)
    │                        │
    ▼                        ▼
LinkedIn post goes live    No post published
with article link preview
```

**The article link card** (title + description + thumbnail) is automatically generated by LinkedIn when it crawls the `originalUrl`. Since the URL is already live when n8n fires, the preview renders correctly.

**Why not LinkedIn scheduled posts?** LinkedIn's `scheduledPublishTime` field in the UGC Posts API requires a special "Scheduled Sharing" permission that is only available to LinkedIn Marketing Partners. Standard developer apps receive a `403 Forbidden — Unpermitted fields: /scheduledPublishTime` error.

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
| **Wait node over LinkedIn scheduled posts** | LinkedIn `scheduledPublishTime` requires LinkedIn Marketing Partner access; Wait node provides equivalent review window using only standard API |
| **`--buildFuture` flag on Hugo build** | Ensures posts with a future-dated frontmatter timestamp are included in the build |
| **`public/` in `.gitignore`** | Build artifacts are generated fresh by GitHub Actions on every run; committing them to the source repo was redundant and caused merge conflicts |
| **`actions/checkout@v4` + `peaceiris/actions-hugo@v3`** | Updated from v3/v2 to maintain Node.js 24 compatibility ahead of GitHub's June 2026 forced migration |

---

*Last Updated: 2026-03-15*
*Project: n8n-Powered Auto Web Publish*

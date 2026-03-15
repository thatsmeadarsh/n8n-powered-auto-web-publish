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

```mermaid
graph TB
    subgraph GitHub["GitHub Cloud"]
        subgraph HugoRepo["whataboutadarsh repo"]
            SRC[content/posts/*.md]
            GA[GitHub Actions Workflow<br/>hugo.yml]
        end
        subgraph PagesRepo["thatsmeadarsh.github.io repo"]
            HTML[Static HTML files]
            PA[GitHub Pages Action<br/>Deploy to Pages]
            GAPI[GitHub REST API<br/>commits endpoint]
        end
    end

    subgraph Docker["Docker Container"]
        subgraph n8n["n8n v2.11.4"]
            ST[Schedule Trigger<br/>Every 5 minutes]
            FD[Fetch Latest Deployment<br/>GET /commits/main]
            ES[Extract New Post Slugs<br/>Compare SHA + parse files]
            FM[Fetch Post Markdown<br/>GET raw from source repo]
            PF[Parse Frontmatter<br/>Extract metadata]
            DC{Draft Check}
            PR[Prepare HF Request<br/>Build AI prompt]
            HF[HTTP Request<br/>HuggingFace API]
            FL[Format LinkedIn Post<br/>Extract AI text]
            GL[HTTP Request<br/>LinkedIn Profile]
            PL[Prepare LinkedIn Post<br/>Build UGC body]
            LI[HTTP Request<br/>LinkedIn Publish]
            SK[Skip - Draft]
        end
    end

    subgraph APIs["External APIs"]
        HFA[Hugging Face Router<br/>SambaNova Provider<br/>Meta-Llama-3.1-8B]
        LIA[LinkedIn API<br/>OAuth2 + UGC Posts]
    end

    subgraph Output["Published Outputs"]
        WEB["thatsmeadarsh.github.io<br/>Live Blog Post"]
        LIP["LinkedIn Feed<br/>AI-Generated Announcement"]
    end

    SRC -->|triggers| GA
    GA -->|hugo build + push| HTML
    HTML -->|triggers| PA --> WEB
    ST --> FD -->|poll| GAPI
    FD --> ES --> FM
    FM -->|GET raw markdown| SRC
    FM --> PF --> DC
    DC -->|not draft| PR --> HF
    DC -->|draft| SK
    HF -->|API call| HFA
    HFA -->|response| FL
    FL --> GL -->|fetch profile| LIA
    GL --> PL --> LI -->|publish| LIA
    LIA --> LIP

    style GitHub fill:#f0f0f0,stroke:#333
    style Docker fill:#fff3e6,stroke:#e8a020
    style APIs fill:#e6ffe6,stroke:#4a9e4a
    style Output fill:#ffe6f0,stroke:#c84a86
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
        CO[Checkout code<br/>with submodules]
        HS[Setup Hugo<br/>latest extended]
        DL[Download Contentful JSON<br/>services data]
        CD[Commit data folder]
        PD[Push data changes]
        RC[Delete Hugo cache<br/>resources/_gen]
        HB[Run: hugo<br/>Generate static site]
        CP[Commit public folder]
        PP[Push public changes]
    end

    subgraph Deploy["Deploy Phase"]
        CL[Clone thatsmeadarsh.github.io]
        RM[Clear target repo]
        CY[Copy public/* to target]
        CM[Commit site content]
        PS[Push to GitHub Pages repo]
    end

    subgraph Live["Auto-Deploy"]
        PA[GitHub Pages Action<br/>in thatsmeadarsh.github.io]
        WB[Website Goes Live]
    end

    T --> CO --> HS --> DL --> CD --> PD
    PD --> RC --> HB --> CP --> PP
    PP --> CL --> RM --> CY --> CM --> PS
    PS -->|push triggers| PA --> WB

    style Trigger fill:#ff9999,stroke:#333
    style Build fill:#99ccff,stroke:#333
    style Deploy fill:#ffcc66,stroke:#333
    style Live fill:#99ff99,stroke:#333
```

**Key Details**:

| Step | Action | Purpose |
|---|---|---|
| Checkout | `actions/checkout@v3` with submodules | Fetches Hugo theme as git submodule |
| Contentful | `curl` to Contentful CDN | Downloads latest services data for the Services page |
| Hugo Build | `hugo` command | Compiles markdown + Ananke theme into static HTML |
| Cross-Repo Push | `git push` with PAT | Pushes built HTML to the GitHub Pages repository |
| Authentication | `PERSONAL_ACCESS_TOKEN` secret | Enables cross-repository push access |

### Low-Level: n8n Workflow Pipeline

The n8n workflow handles everything after deployment -- polling for changes, fetching content, AI generation, and social media publishing.

```mermaid
graph TD
    subgraph Polling["1. Polling"]
        ST[Schedule Trigger<br/>Every 5 minutes]
        FD[Fetch Latest Deployment<br/>GET /repos/.../commits/main]
    end

    subgraph Detection["2. Detection"]
        ES[Extract New Post Slugs<br/>Compare SHA with stored state<br/>Filter for new posts/*]
    end

    subgraph Fetch["3. Content Fetch"]
        FM[Fetch Post Markdown<br/>GET raw .md from Hugo source repo]
        PF[Parse Frontmatter<br/>Regex extracts TOML metadata]
    end

    subgraph Validation["4. Validation"]
        DC{draft === false?}
        SK[Skip Node<br/>No LinkedIn for drafts]
    end

    subgraph AIGeneration["5. AI Content Generation"]
        PR[Prepare HF Request<br/>Builds chat prompt]
        HF[HuggingFace API Call<br/>SambaNova / Llama 3.1]
        FL[Format Response<br/>Extract text + fallback]
    end

    subgraph LinkedInPublish["6. LinkedIn Publishing"]
        GL[Get Profile<br/>GET /v2/userinfo]
        PL[Prepare Post Body<br/>Build UGC schema]
        LI[Publish Post<br/>POST /v2/ugcPosts]
    end

    ST --> FD --> ES --> FM --> PF --> DC
    DC -->|true| PR
    DC -->|false| SK
    PR --> HF --> FL
    FL --> GL --> PL --> LI

    style Polling fill:#f0e6ff,stroke:#8a4ac8
    style Detection fill:#e6f3ff,stroke:#4a86c8
    style Fetch fill:#f0f0e6,stroke:#999
    style Validation fill:#fff3e6,stroke:#e8a020
    style AIGeneration fill:#e6ffe6,stroke:#4a9e4a
    style LinkedInPublish fill:#ffe6f0,stroke:#c84a86
```

---

## System Flow Diagram (PlantUML)

```plantuml
@startuml
!theme plain
skinparam backgroundColor #FFFFFF
skinparam sequenceMessageAlign center
skinparam responseMessageBelowArrow true

title End-to-End Auto-Publish System Flow

actor Author as author
participant "Git CLI" as git
participant "GitHub\nwhataboutadarsh" as hugorepo
participant "GitHub Actions\nCI/CD" as actions
participant "GitHub\nthatsmeadarsh.github.io" as pagesrepo
participant "GitHub Pages\nCDN" as cdn
participant "n8n\nSchedule Trigger" as trigger
participant "n8n\nFetch & Parse" as parse
participant "HuggingFace\nSambaNova" as hf
participant "n8n\nFormat Post" as format
participant "LinkedIn\nAPI" as linkedin

== Author Pushes ==
author -> git : git add + commit + push
git -> hugorepo : push to main branch
note right of hugorepo : Push triggers\nGitHub Actions

== Pipeline 1: Build & Deploy ==
hugorepo -> actions : Workflow triggered
activate actions
actions -> actions : Checkout + setup Hugo
actions -> actions : Download Contentful data
actions -> actions : Run hugo build
actions -> pagesrepo : Push built HTML
deactivate actions
pagesrepo -> cdn : GitHub Pages deploys
note right of cdn : Website is live

== Pipeline 2: n8n Polling & Social ==
trigger -> pagesrepo : GET /repos/.../commits/main\n(every 5 minutes)
pagesrepo --> trigger : Latest commit SHA + files
trigger -> trigger : Compare SHA with stored state

alt new commit detected
    trigger -> parse : Extract new post slugs from files
    parse -> hugorepo : GET raw markdown via GitHub API
    hugorepo --> parse : Markdown file content
    parse -> parse : Parse frontmatter\nCheck draft status

    alt draft = false
        parse -> hf : POST /sambanova/v1/chat/completions\n{system prompt + article context}
        activate hf
        hf --> parse : AI-generated LinkedIn post text
        deactivate hf
        parse -> format : Format response
        format -> linkedin : GET /v2/userinfo
        linkedin --> format : Person URN
        format -> linkedin : POST /v2/ugcPosts\n{author, commentary, article URL}
        linkedin --> format : Post published
        note right of linkedin : LinkedIn post is live\nwith article link preview
    else draft = true
        parse -> parse : Skip (no LinkedIn post)
    end
else same commit as last poll
    trigger -> trigger : No action (already processed)
end

@enduml
```

---

## Integration Highlight: n8n + GitHub Actions

> **How we bridged workflow automation with CI/CD to create a zero-touch publishing pipeline**

```mermaid
graph TB
    subgraph Bridge["The Bridge: GitHub API Polling"]
        FW["n8n polls commits endpoint<br/>New commit = deployment complete"]
    end

    subgraph GitHubActions["GitHub Actions -- Build & Deploy"]
        direction TB
        GA1["Triggered by: git push to Hugo repo"]
        GA2["Builds Hugo static site"]
        GA3["Deploys to GitHub Pages"]
        GA4["Output: Live website"]
        GA1 --> GA2 --> GA3 --> GA4
    end

    subgraph n8nWorkflow["n8n -- Detection, AI & Social Media"]
        direction TB
        N1["Triggered by: new commit detected via polling"]
        N2["Fetches and parses blog content"]
        N3["AI generates LinkedIn summary"]
        N4["Posts to LinkedIn with article link"]
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
| **Zero manual steps** | From pushing a markdown file to a live website + LinkedIn announcement -- no human intervention. |
| **Corporate-friendly** | Polling uses outbound HTTPS only -- works behind corporate proxies and firewalls. |

---

## Security Architecture

```mermaid
graph LR
    subgraph Secrets["Credential Storage"]
        GS["GitHub Secrets<br/>PERSONAL_ACCESS_TOKEN"]
        NC["n8n Credential Store<br/>GitHub API Token<br/>LinkedIn OAuth2<br/>HuggingFace Header Auth"]
    end

    subgraph Access["Access Scope"]
        GS --> GHA["GitHub: repo + workflow scope"]
        NC --> GTA["GitHub: repo (read commits)"]
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

## LinkedIn Scheduled Post & Review Flow

Rather than publishing immediately, the workflow creates a **scheduled post** set 24 hours in the future. This gives the author a review window.

```
n8n creates scheduled post (lifecycleState: SCHEDULED)
              │
              ▼
LinkedIn: Post queued for T+24h
              │
              │  Author reviews in LinkedIn UI:
              │  Me → Posts & Activity → Scheduled
              │
    ┌─────────┴──────────────┐
    │                        │
    ▼                        ▼
 Happy with it?         Needs edits?
    │                        │
    ▼                        ▼
"Post now"            Edit text → "Post now"
    │                   or wait for auto-publish
    ▼
LinkedIn post goes live with article link preview
```

**The article link card** (title + description + thumbnail) is automatically generated by LinkedIn when it crawls the `originalUrl`. Since the URL is already live when n8n fires, the preview renders correctly.

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

---

*Last Updated: 2026-03-14*
*Project: n8n-Powered Auto Web Publish*

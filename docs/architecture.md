# Architecture Documentation

> A seamless integration of n8n workflow automation with GitHub Actions CI/CD — turning a single markdown file into a live blog post with an AI-crafted LinkedIn announcement, all without manual intervention.

---

## High-Level Architecture

At a glance, the system transforms a markdown file into a published blog post and LinkedIn announcement through three independent systems working in concert:

```mermaid
graph LR
    A["Author writes .md file"] --> B["File Watcher"]
    B --> C["GitHub Repository"]
    B --> D["n8n Workflow Engine"]
    C --> E["GitHub Actions CI/CD"]
    E --> F["Live Website"]
    D --> G["AI Content Generation"]
    G --> H["LinkedIn Post"]

    style A fill:#99ccff,stroke:#333
    style F fill:#99ff99,stroke:#333
    style H fill:#99ff99,stroke:#333
```

| Layer | System | Responsibility |
|---|---|---|
| **Detection** | `fswatch` on host | Watches for new blog posts |
| **Build & Deploy** | GitHub Actions | Hugo build, static site deployment |
| **AI & Social** | n8n + Hugging Face + LinkedIn | AI summary generation, social publishing |

**The key insight**: The file watcher acts as an **event bridge** — a single file creation triggers two parallel pipelines (GitHub Actions for deployment, n8n for social promotion) that work independently but deliver a unified outcome.

---

## High-Level System Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AUTHOR'S MACHINE                             │
│                                                                     │
│   1. Write markdown post                                            │
│   2. Save to content/posts/                                         │
│                     │                                               │
│                     ▼                                               │
│            ┌─────────────────┐                                      │
│            │  File Watcher   │                                      │
│            │  (fswatch)      │                                      │
│            └────┬───────┬────┘                                      │
│                 │       │                                           │
│        git push │       │ webhook POST                              │
│                 │       │                                           │
└─────────────────┼───────┼───────────────────────────────────────────┘
                  │       │
         ┌────────┘       └────────┐
         ▼                         ▼
┌─────────────────┐     ┌──────────────────┐
│  GitHub Actions  │     │  n8n (Docker)    │
│  ─────────────── │     │  ──────────────  │
│  Hugo Build      │     │  AI Summary      │
│  Deploy to Pages │     │  LinkedIn Post   │
└────────┬────────┘     └────────┬─────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐     ┌──────────────────┐
│  Live Website    │     │  LinkedIn Feed   │
│  (GitHub Pages)  │     │  (Public Post)   │
└─────────────────┘     └──────────────────┘
```

---

## Low-Level Architecture

### Complete System Component Diagram

```mermaid
graph TB
    subgraph Host["Host Machine (macOS)"]
        FS[fswatch<br/>File System Monitor]
        SH[watch-and-publish.sh<br/>Orchestration Script]
        GIT[Git CLI<br/>Commit & Push]
        CURL[curl + jq<br/>Webhook Caller]
    end

    subgraph GitHub["GitHub Cloud"]
        subgraph HugoRepo["whataboutadarsh repo"]
            SRC[content/posts/*.md]
            GA[GitHub Actions Workflow<br/>hugo.yml]
        end
        subgraph PagesRepo["thatsmeadarsh.github.io repo"]
            HTML[Static HTML files]
            PA[GitHub Pages Action<br/>Deploy to Pages]
        end
    end

    subgraph Docker["Docker Container"]
        subgraph n8n["n8n v2.11.4"]
            WH[Webhook Trigger<br/>POST /publish-post]
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

    FS -->|detect .md| SH
    SH --> GIT -->|push to main| SRC
    SH --> CURL -->|POST| WH
    SRC -->|triggers| GA
    GA -->|hugo build + push| HTML
    HTML -->|triggers| PA --> WEB
    WH --> PF --> DC
    DC -->|not draft| PR --> HF
    DC -->|draft| SK
    HF -->|API call| HFA
    HFA -->|response| FL
    FL --> GL -->|fetch profile| LIA
    GL --> PL --> LI -->|publish| LIA
    LIA --> LIP

    style Host fill:#e6f3ff,stroke:#4a86c8
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

    subgraph Live["Auto-Triggered"]
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
| Hugo Build | `hugo` command | Compiles markdown + Ananke theme → static HTML |
| Cross-Repo Push | `git push` with PAT | Pushes built HTML to the GitHub Pages repository |
| Authentication | `PERSONAL_ACCESS_TOKEN` secret | Enables cross-repository push access |

### Low-Level: n8n Workflow Pipeline

The n8n workflow handles everything GitHub Actions cannot — AI content generation and social media publishing.

```mermaid
graph TD
    subgraph Ingestion["1. Ingestion"]
        WH[Webhook Trigger<br/>Receives POST with file content]
        PF[Parse Frontmatter<br/>Regex extracts TOML metadata]
    end

    subgraph Validation["2. Validation"]
        DC{draft === false?}
        SK[Skip Node<br/>No LinkedIn for drafts]
    end

    subgraph AIGeneration["3. AI Content Generation"]
        PR[Prepare HF Request<br/>Builds chat prompt with:<br/>- title, tags, excerpt<br/>- formatting instructions]
        HF[HuggingFace API Call<br/>POST router.huggingface.co<br/>SambaNova / Llama 3.1]
        FL[Format Response<br/>Extract text from choices<br/>Fallback if AI fails]
    end

    subgraph LinkedInPublish["4. LinkedIn Publishing"]
        GL[Get Profile<br/>GET /v2/userinfo<br/>Returns person URN]
        PL[Prepare Post Body<br/>Build UGC schema with:<br/>- author URN<br/>- AI commentary<br/>- article link + title]
        LI[Publish Post<br/>POST /v2/ugcPosts<br/>Public visibility]
    end

    WH --> PF --> DC
    DC -->|true| PR
    DC -->|false| SK
    PR --> HF --> FL
    FL --> GL --> PL --> LI

    style Ingestion fill:#e6f3ff,stroke:#4a86c8
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
participant "File Watcher\n(fswatch)" as watcher
participant "Git CLI" as git
participant "GitHub\nwhataboutadarsh" as hugorepo
participant "GitHub Actions\nCI/CD" as actions
participant "GitHub\nthatsmeadarsh.github.io" as pagesrepo
participant "GitHub Pages\nCDN" as cdn
participant "n8n\nWebhook" as webhook
participant "n8n\nParse & Validate" as parse
participant "HuggingFace\nSambaNova" as hf
participant "n8n\nFormat Post" as format
participant "LinkedIn\nAPI" as linkedin

== File Creation ==
author -> author : Write markdown post
author -> watcher : Save .md to content/posts/

== Git Commit & Push ==
watcher -> git : git add + commit
git -> hugorepo : git push origin main
note right of hugorepo : Push triggers\nGitHub Actions

== Parallel Pipeline 1: Build & Deploy ==
hugorepo -> actions : Workflow triggered
activate actions
actions -> actions : Checkout + setup Hugo
actions -> actions : Download Contentful data
actions -> actions : Run hugo build
actions -> pagesrepo : Push built HTML
deactivate actions
pagesrepo -> cdn : GitHub Pages deploys
note right of cdn : Website is live\nwithin ~60 seconds

== Parallel Pipeline 2: AI & Social ==
watcher -> webhook : POST /webhook/publish-post\n{fileName, slug, fileContent}
activate webhook
webhook -> parse : Extract frontmatter
parse -> parse : Check draft status

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
deactivate webhook

@enduml
```

---

## Detailed Activity Diagram (PlantUML)

```plantuml
@startuml
!theme plain
skinparam backgroundColor #FFFFFF

title Detailed Activity Flow — Auto-Publish Pipeline

start

partition "File Detection" {
    :Author saves .md file to content/posts/;
    :fswatch detects Created event;
    :Wait 2 seconds for write completion;
    if (File is .md?) then (yes)
    else (no)
        stop
    endif
}

partition "Source Control" {
    :Extract filename and slug;
    :git add content/posts/{filename};
    if (Changes to commit?) then (yes)
        :git commit -m "Add post: {slug}";
        :git push origin main;
        note right
            This push triggers GitHub Actions
            workflow in whataboutadarsh repo
        end note
    else (no)
        :Skip commit (already pushed);
    endif
}

fork
    partition "GitHub Actions Pipeline" #LightBlue {
        :Checkout repository with submodules;
        :Setup Hugo (latest extended);
        :Download Contentful services.json;
        :Commit data folder;
        :Push data changes;
        :Delete Hugo cache (resources/_gen);
        :Run **hugo** build;
        :Commit public folder;
        :Push public changes;
        :Clone thatsmeadarsh.github.io;
        :Clear target repo;
        :Copy public/* to target;
        :Commit and push to Pages repo;
        note right
            Push triggers GitHub Pages
            deployment workflow
        end note
        :GitHub Pages deploys static files;
        :**Website goes live**;
    }

fork again
    partition "n8n Webhook Pipeline" #LightGreen {
        :POST webhook with file content;
        :Parse TOML frontmatter;
        :Extract title, date, tags, slug;
        :Build post URL from slug;
        :Take first 500 words as excerpt;

        if (draft = false?) then (yes)
            partition "AI Generation" #LightYellow {
                :Build chat prompt with title, tags, excerpt;
                :POST to HuggingFace SambaNova API;
                :Model: Meta-Llama-3.1-8B-Instruct;
                :Receive AI-generated LinkedIn text;
                if (AI response valid?) then (yes)
                    :Extract choices[0].message.content;
                else (no)
                    :Use fallback: title + URL + hashtags;
                endif
            }

            partition "LinkedIn Publishing" #Pink {
                :GET /v2/userinfo (fetch person URN);
                :Build UGC post body with:
                - Author URN
                - AI commentary text
                - Article URL as media
                - Public visibility;
                :POST /v2/ugcPosts;
                :**LinkedIn post published**;
            }
        else (draft)
            :Skip (no LinkedIn post for drafts);
        endif
    }
end fork

stop

@enduml
```

---

## Integration Highlight: n8n + GitHub Actions

> **How we bridged workflow automation with CI/CD to create a zero-touch publishing pipeline**

The power of this architecture lies in how **n8n and GitHub Actions complement each other** without overlap or duplication:

```mermaid
graph TB
    subgraph Bridge["The Bridge: File Watcher"]
        FW["watch-and-publish.sh<br/>Single event → Two pipelines"]
    end

    subgraph GitHubActions["GitHub Actions — Build & Deploy"]
        direction TB
        GA1["Triggered by: git push to main"]
        GA2["Builds Hugo static site"]
        GA3["Deploys to GitHub Pages"]
        GA4["Output: Live website"]
        GA1 --> GA2 --> GA3 --> GA4
    end

    subgraph n8nWorkflow["n8n — AI & Social Media"]
        direction TB
        N1["Triggered by: webhook POST"]
        N2["Parses blog metadata"]
        N3["AI generates LinkedIn summary"]
        N4["Posts to LinkedIn with article link"]
        N1 --> N2 --> N3 --> N4
    end

    FW -->|"git push"| GitHubActions
    FW -->|"HTTP POST"| n8nWorkflow

    style Bridge fill:#ffcc66,stroke:#333
    style GitHubActions fill:#e6f3ff,stroke:#4a86c8
    style n8nWorkflow fill:#e6ffe6,stroke:#4a9e4a
```

### Why This Integration Works

| Principle | Implementation |
|---|---|
| **Separation of concerns** | GitHub Actions handles what it's best at (CI/CD, building, deploying). n8n handles what it's best at (API orchestration, AI integration, conditional logic). |
| **No duplication** | Build and deploy happen only in GitHub Actions. AI and social happen only in n8n. Neither system repeats the other's work. |
| **Event-driven** | A single file creation event fans out into two independent pipelines through the watcher script acting as an event bridge. |
| **Fault isolation** | If LinkedIn posting fails, the website still deploys. If GitHub Actions fails, the LinkedIn post still goes out (with the correct future URL). |
| **Zero manual steps** | From saving a markdown file to a live website + LinkedIn announcement — no human intervention required. |

### The Integration Pattern

```
                    ┌─────────────────┐
                    │  Single Event   │
                    │  (new .md file) │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │  Event Bridge   │
                    │  (watcher.sh)   │
                    └───┬─────────┬───┘
                        │         │
              ┌─────────┘         └─────────┐
              │                             │
    ┌─────────▼─────────┐       ┌───────────▼───────────┐
    │   git push         │       │   webhook POST        │
    │   (synchronous)    │       │   (asynchronous)      │
    └─────────┬─────────┘       └───────────┬───────────┘
              │                             │
    ┌─────────▼─────────┐       ┌───────────▼───────────┐
    │  GitHub Actions    │       │  n8n Workflow          │
    │  ───────────────── │       │  ──────────────────    │
    │  Hugo build        │       │  Parse frontmatter     │
    │  Contentful sync   │       │  Draft validation      │
    │  Cross-repo deploy │       │  AI text generation    │
    │                    │       │  LinkedIn publishing   │
    └─────────┬─────────┘       └───────────┬───────────┘
              │                             │
    ┌─────────▼─────────┐       ┌───────────▼───────────┐
    │  LIVE WEBSITE      │       │  LINKEDIN POST        │
    │  thatsmeadarsh     │       │  AI-crafted summary   │
    │  .github.io        │       │  with article link    │
    └───────────────────┘       └───────────────────────┘
```

This pattern is **reusable** — the same event-bridge approach can integrate any CI/CD pipeline with any workflow automation tool, enabling scenarios like:
- Auto-posting to Twitter/X, Mastodon, or other platforms
- Sending email newsletters for new posts
- Triggering SEO indexing via Google Search Console API
- Cross-posting to Medium or Dev.to

---

## Security Architecture

```mermaid
graph LR
    subgraph Secrets["Credential Storage"]
        CE["config.env (gitignored)<br/>HuggingFace token"]
        GS["GitHub Secrets<br/>PERSONAL_ACCESS_TOKEN"]
        NC["n8n Credential Store<br/>LinkedIn OAuth2<br/>HuggingFace Header Auth"]
    end

    subgraph Access["Access Scope"]
        CE --> HFA["HuggingFace: Inference only"]
        GS --> GHA["GitHub: repo + workflow scope"]
        NC --> LIA["LinkedIn: w_member_social only"]
    end

    style Secrets fill:#fff3e6,stroke:#333
    style Access fill:#e6ffe6,stroke:#333
```

| Secret | Location | Scope | Expiry |
|---|---|---|---|
| HuggingFace token | `config.env` + n8n credential store | Inference Providers only | No expiry |
| GitHub PAT | GitHub repo secret (`PERSONAL_ACCESS_TOKEN`) | `repo` + `workflow` | Configurable (90 days recommended) |
| LinkedIn OAuth2 | n8n credential store (encrypted) | `w_member_social` | 2 months (auto-refreshed by n8n) |

### Security Boundaries

- **Webhook endpoint** is `localhost:5678` only — not exposed to internet
- **n8n** runs in Docker with `NODE_TLS_REJECT_UNAUTHORIZED=0` (container-scoped, not host)
- **GitHub PAT** is stored in GitHub's encrypted secrets, never in code
- **config.env** is gitignored — never committed to version control

---

## Design Decisions

| Decision | Rationale |
|---|---|
| **Watcher on host, not in n8n** | n8n runs in Docker without host filesystem access; `fswatch` on the host is the simplest file detection mechanism |
| **GitHub Actions for build/deploy** | Already configured and tested; Hugo + cross-repo push is complex to replicate elsewhere |
| **n8n for AI + social only** | Keeps n8n focused on what it excels at: API orchestration and conditional logic |
| **HTTP Request nodes over LinkedIn node** | Built-in LinkedIn node doesn't support "Ignore SSL Issues" needed in Docker |
| **Code nodes for JSON construction** | Blog content contains special characters that break inline JSON templates |
| **SambaNova via HuggingFace Router** | Free tier, fast inference, OpenAI-compatible API format |
| **Draft check in n8n** | Allows deploying draft posts to test site rendering without triggering LinkedIn |

---

*Last Updated: 2026-03-14*
*Project: n8n-Powered Auto Web Publish*

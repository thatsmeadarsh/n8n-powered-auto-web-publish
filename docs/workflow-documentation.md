# Workflow Documentation

> Detailed functional documentation of the watcher script, GitHub Actions pipeline, and every node in the n8n workflow — the three systems that power zero-touch blog publishing.

---

## System Overview

The auto-publish pipeline consists of three independent systems triggered by a single event:

```mermaid
graph TD
    E["Event: New .md file saved"] --> W["Watcher Script"]
    W -->|"git push"| GA["GitHub Actions"]
    W -->|"webhook POST"| N8N["n8n Workflow"]
    GA --> SITE["Live Website"]
    N8N --> LI["LinkedIn Post"]

    style E fill:#ffcc66,stroke:#333
    style SITE fill:#99ff99,stroke:#333
    style LI fill:#99ff99,stroke:#333
```

---

## Part 1: Watcher Script

**File**: `scripts/watch-and-publish.sh`

The watcher is the simplest component — it detects new files and dispatches events to both pipelines.

```mermaid
graph TD
    A[Load config.env] --> B[Start fswatch on content/posts/]
    B --> C{New .md file?}
    C -->|No| B
    C -->|Yes| D[Wait 2s for write completion]
    D --> E[git add + commit + push]
    E --> F[POST to n8n webhook]
    F --> G[Log result]
    G --> B

    style A fill:#99ccff,stroke:#333
    style E fill:#ffcc66,stroke:#333
    style F fill:#99ff99,stroke:#333
```

### Configuration

All paths and URLs are loaded from `config.env`:

| Variable | Purpose |
|---|---|
| `HUGO_DIR` | Path to the Hugo project (for git operations) |
| `POSTS_DIR` | Path to `content/posts/` (watch target) |
| `WEBHOOK_URL` | n8n webhook endpoint |
| `SITE_BASE_URL` | Website base URL (for constructing post links) |
| `LOG_DIR` | Log file location |

### Webhook Payload

The watcher sends this JSON to n8n:

```json
{
  "fileName": "my-new-post.md",
  "slug": "my-new-post",
  "fileContent": "+++\ntitle = '...'\n+++\n\nFull markdown content...",
  "siteBaseUrl": "https://thatsmeadarsh.github.io"
}
```

---

## Part 2: GitHub Actions Pipeline

**File**: `whataboutadarsh/.github/workflows/hugo.yml`
**Trigger**: Push to `main` branch (triggered by the watcher's `git push`)

This is the **build and deploy** engine. It runs entirely in GitHub's cloud infrastructure.

### Pipeline Stages

```mermaid
graph TD
    subgraph Stage1["Stage 1: Setup"]
        CO["Checkout code<br/>(with submodules for Hugo theme)"]
        HS["Setup Hugo<br/>(latest extended version)"]
    end

    subgraph Stage2["Stage 2: Data Sync"]
        DL["Download services.json<br/>from Contentful CDN"]
        CD["Commit data folder"]
        PD["Push data changes<br/>(using PERSONAL_ACCESS_TOKEN)"]
    end

    subgraph Stage3["Stage 3: Build"]
        RC["Delete Hugo cache<br/>(resources/_gen)"]
        HB["Run: hugo<br/>Generates 34 pages, 11 static files"]
        CP["Commit public folder"]
        PP["Push public changes"]
    end

    subgraph Stage4["Stage 4: Deploy"]
        CL["Clone thatsmeadarsh.github.io"]
        RM["Clear all files in target repo"]
        CY["Copy public/* to target"]
        CM["Commit: 'Update site content'"]
        PS["Push to Pages repo<br/>(using PERSONAL_ACCESS_TOKEN)"]
    end

    subgraph Stage5["Stage 5: Auto-Deploy"]
        PA["GitHub Pages Action triggers<br/>(in thatsmeadarsh.github.io)"]
        WB["Website goes live"]
    end

    Stage1 --> Stage2 --> Stage3 --> Stage4 --> Stage5

    style Stage1 fill:#e6f3ff,stroke:#333
    style Stage2 fill:#fff3e6,stroke:#333
    style Stage3 fill:#e6ffe6,stroke:#333
    style Stage4 fill:#ffe6f0,stroke:#333
    style Stage5 fill:#99ff99,stroke:#333
```

### Authentication Flow

```mermaid
sequenceDiagram
    participant GA as GitHub Actions
    participant HR as Hugo Repo (whataboutadarsh)
    participant PR as Pages Repo (thatsmeadarsh.github.io)

    GA->>GA: Read PERSONAL_ACCESS_TOKEN from secrets
    GA->>HR: Push data + public folders (PAT auth)
    GA->>PR: git clone (HTTPS)
    GA->>GA: Copy public/* to cloned repo
    GA->>PR: git push via x-access-token:PAT
    Note over PR: Push triggers Pages<br/>deployment workflow
```

### Key Configuration

| Setting | Value | Purpose |
|---|---|---|
| `persist-credentials: false` | Checkout step | Prevents default GITHUB_TOKEN from being used for pushes |
| `PERSONAL_ACCESS_TOKEN` | Repository secret | Enables cross-repository push (Hugo repo → Pages repo) |
| `submodules: true` | Checkout step | Fetches Ananke Hugo theme |
| `fetch-depth: 0` | Checkout step | Full git history for Hugo's `.GitInfo` |

---

## Part 3: n8n Workflow

**File**: `workflows/auto-publish-workflow.json`
**Trigger**: Webhook POST from watcher script
**Total Nodes**: 9 active + 1 no-op

### Workflow Canvas

```
Webhook    Parse       Is Not    Prepare    AI Generate   Format      Get         Prepare     Post to
Trigger → Frontmatter → Draft? → HF Request → LinkedIn → LinkedIn → LinkedIn  → LinkedIn  → LinkedIn
                          │        Post        Post       Profile     Post
                          ▼
                       Skip (Draft)
```

### Node-by-Node Documentation

---

#### Node 1: Webhook Trigger

| Property | Value |
|---|---|
| **Type** | `n8n-nodes-base.webhook` |
| **Method** | POST |
| **Path** | `/webhook/publish-post` |
| **Full URL** | `http://localhost:5678/webhook/publish-post` |
| **Response** | Immediate 200 (async processing) |

Receives the file content and metadata from the watcher script.

---

#### Node 2: Parse Frontmatter

| Property | Value |
|---|---|
| **Type** | `n8n-nodes-base.code` (JavaScript) |
| **Purpose** | Extract structured metadata from Hugo's TOML frontmatter |

**Parsing Logic**:

```mermaid
graph TD
    A[Raw fileContent string] --> B["Regex match: /^\\+\\+\\+([\\s\\S]*?)\\+\\+\\+/"]
    B --> C[TOML block extracted]
    C --> D["title = regex /title\\s*=\\s*['\"](.+?)['\"]/"]
    C --> E["date = regex /date\\s*=\\s*['\"](.+?)['\"]/"]
    C --> F["draft = regex /draft\\s*=\\s*(true|false)/"]
    C --> G["tags = regex /tags\\s*=\\s*\\[([^\\]]+)\\]/"]
    C --> H["categories = similar pattern"]
    A --> I["Body = content after closing +++"]
    I --> J["Excerpt = first 500 words"]

    style A fill:#99ccff,stroke:#333
    style J fill:#99ff99,stroke:#333
```

**Supported Frontmatter Format** (Hugo TOML):
```toml
+++
title = 'My Blog Post Title'
date = 2026-03-14T10:00:00+01:00
draft = false
tags = ['AI', 'MCP', 'Automation']
categories = ['Technology', 'Software Engineering']
+++
```

**Output Schema**:
```json
{
  "title": "My Blog Post Title",
  "date": "2026-03-14T10:00:00+01:00",
  "draft": false,
  "tags": ["AI", "MCP", "Automation"],
  "categories": ["Technology", "Software Engineering"],
  "slug": "my-blog-post",
  "fileName": "my-blog-post.md",
  "postUrl": "https://thatsmeadarsh.github.io/posts/my-blog-post/",
  "excerpt": "First 500 words of the article body..."
}
```

---

#### Node 3: Is Not Draft?

| Property | Value |
|---|---|
| **Type** | `n8n-nodes-base.if` |
| **Condition** | `$json.draft === false` |
| **True** | Continue to AI generation |
| **False** | Skip (no LinkedIn post) |

**Why this matters**: Draft posts are committed and deployed (for preview testing) but don't trigger social media posting. This gives authors the ability to review their post on the live site before promoting it.

---

#### Node 4: Prepare HF Request

| Property | Value |
|---|---|
| **Type** | `n8n-nodes-base.code` (JavaScript) |
| **Purpose** | Build a safe, properly escaped JSON request body |

**Why a separate code node?** Blog content contains quotes, newlines, markdown syntax, HTML, and special characters. Directly interpolating these into the HTTP Request node's JSON template causes parsing errors. This node builds the request programmatically.

**AI Prompt Structure**:
```
System: You are a professional LinkedIn content writer. Write engaging
        posts that drive clicks and engagement.

User:   Write a compelling LinkedIn post (150-200 words) announcing my
        new blog article.

        Title: {extracted title}
        Tags: {extracted tags}
        Article excerpt: {first 800 chars}
        URL: {constructed post URL}

        Requirements:
        - Professional but engaging tone
        - 2-3 relevant hashtags from tags
        - Call to action with article URL
        - Maximum 2-3 emojis
```

---

#### Node 5: AI Generate LinkedIn Post

| Property | Value |
|---|---|
| **Type** | `n8n-nodes-base.httpRequest` |
| **Method** | POST |
| **URL** | `https://router.huggingface.co/sambanova/v1/chat/completions` |
| **Auth** | Header Auth (`Authorization: Bearer hf_...`) |
| **SSL** | Ignore SSL Issues: ON |
| **Timeout** | 30 seconds |

```mermaid
sequenceDiagram
    participant N as n8n
    participant R as HuggingFace Router
    participant S as SambaNova Provider
    participant M as Meta-Llama-3.1-8B

    N->>R: POST /sambanova/v1/chat/completions
    R->>S: Route to serverless endpoint
    S->>M: Run inference
    M-->>S: Generated text (~200 words)
    S-->>R: OpenAI-compatible response
    R-->>N: {choices: [{message: {content: "..."}}]}
```

**Model Configuration**:

| Parameter | Value | Rationale |
|---|---|---|
| Model | `Meta-Llama-3.1-8B-Instruct` | Free tier, good instruction-following |
| Provider | SambaNova | Fast serverless inference |
| max_tokens | 400 | Enough for 200-word post |
| temperature | 0.7 | Creative but coherent |

---

#### Node 6: Format LinkedIn Post

| Property | Value |
|---|---|
| **Type** | `n8n-nodes-base.code` (JavaScript) |
| **Purpose** | Extract AI text with fallback handling |

**Logic**:
1. Try `choices[0].message.content` (OpenAI-compatible format)
2. Fallback: try `[0].generated_text` (legacy HF format)
3. Final fallback: simple post with title + URL + hashtags

The fallback ensures LinkedIn always gets a post, even if the AI API fails.

---

#### Node 7: Get LinkedIn Profile

| Property | Value |
|---|---|
| **Type** | `n8n-nodes-base.httpRequest` |
| **Method** | GET |
| **URL** | `https://api.linkedin.com/v2/userinfo` |
| **Auth** | LinkedIn OAuth2 (Predefined Credential) |
| **SSL** | Ignore SSL Issues: ON |

Returns the `sub` field — the authenticated user's LinkedIn person URN ID, required for creating posts.

---

#### Node 8: Prepare LinkedIn Post

| Property | Value |
|---|---|
| **Type** | `n8n-nodes-base.code` (JavaScript) |
| **Purpose** | Build LinkedIn UGC Post API body |

Constructs the post with:
- **Author**: `urn:li:person:{sub}` from profile lookup
- **Commentary**: AI-generated text
- **Media**: Article link (renders as a link preview card on LinkedIn)
- **Visibility**: Public

---

#### Node 9: Post to LinkedIn

| Property | Value |
|---|---|
| **Type** | `n8n-nodes-base.httpRequest` |
| **Method** | POST |
| **URL** | `https://api.linkedin.com/v2/ugcPosts` |
| **Auth** | LinkedIn OAuth2 (Predefined Credential) |
| **SSL** | Ignore SSL Issues: ON |

Publishes the post. Returns the created post URN on success.

---

## Error Handling

```mermaid
graph TD
    subgraph Watcher["Watcher Script Errors"]
        WE1["Git push fails"] --> WA1["Log error<br/>Webhook still fires"]
        WE2["Webhook returns non-200"] --> WA2["Log warning<br/>Continue watching"]
    end

    subgraph Actions["GitHub Actions Errors"]
        AE1["Hugo build fails"] --> AA1["Workflow fails<br/>Email notification to repo owner"]
        AE2["Cross-repo push fails"] --> AA2["Check PAT expiry<br/>Re-generate token"]
    end

    subgraph n8n["n8n Workflow Errors"]
        NE1["HuggingFace API fails"] --> NA1["Fallback post generated<br/>title + URL + hashtags"]
        NE2["LinkedIn API fails"] --> NA2["Execution marked as error<br/>Check OAuth token refresh"]
        NE3["Draft post detected"] --> NA3["Skip node<br/>No LinkedIn post created"]
    end

    style WA1 fill:#ffcc66,stroke:#333
    style NA1 fill:#ffcc66,stroke:#333
    style AA2 fill:#ff9999,stroke:#333
```

### Fault Isolation

| Failure | Website Impact | LinkedIn Impact |
|---|---|---|
| Watcher crashes | No new posts detected | No LinkedIn posts |
| GitHub Actions fails | Site not updated | LinkedIn post still sent (with future URL) |
| n8n fails | No impact — site deploys normally | No LinkedIn post |
| HuggingFace API down | No impact | Fallback text used |
| LinkedIn API down | No impact | Post not published |

The **parallel pipeline design** ensures that a failure in one system doesn't cascade to the other. The website can deploy without LinkedIn, and LinkedIn can post without waiting for deployment.

---

*Last Updated: 2026-03-14*
*Project: n8n-Powered Auto Web Publish*

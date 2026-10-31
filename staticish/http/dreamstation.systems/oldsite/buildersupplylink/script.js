const { useEffect, useState } = React;
const h = React.createElement;

const fitItems = [
  {
    id: "ai",
    tab: "AI engineering",
    blurb: "LLM tooling, RAG interest, and document-analysis curiosity.",
    kicker: "AI systems fit",
    title: "The AI focus is the strongest reason this role stands out to me.",
    summary:
      "Builder Supply Link sits at a technically unusual intersection: AI, architectural documents, and production software. That is exactly the kind of work I want more exposure to. I already use AI tools in technical workflows and I am especially interested in how LLM orchestration and computer vision can be turned into reliable products.",
    metrics: [
      { label: "LLM usage", value: "Active", note: "Already using AI tools in technical work" },
      { label: "RAG interest", value: "High", note: "Strong interest in retrieval-based systems" },
      { label: "CV curiosity", value: "Real", note: "Interested in document and layout understanding" }
    ],
    bullets: [
      "I treat AI as engineering infrastructure, not just a novelty layer.",
      "The architectural-document angle is especially compelling because it turns AI into a concrete workflow tool.",
      "I would value the chance to work around RAG, computer vision, and production-grade LLM usage."
    ],
    tags: ["LLMs", "RAG", "Computer Vision", "Document AI"]
  },
  {
    id: "python",
    tab: "Backend optimization",
    blurb: "Python background with strong systems instincts.",
    kicker: "Backend and performance",
    title: "I bring a useful backend perspective, especially where software meets real systems.",
    summary:
      "Your posting calls out FastAPI, concurrency, multiprocessing, and hardware-aware workflows. My resume does not claim deep FastAPI production experience, but it does show a strong Python base, Linux familiarity, scripting comfort, and systems-oriented thinking. That gives me a credible foundation for ramping quickly on backend optimization work.",
    metrics: [
      { label: "Python", value: "Strong", note: "Used across multiple technical projects" },
      { label: "Systems sense", value: "Useful", note: "Linux, networking, observability" },
      { label: "Ramp speed", value: "Fast", note: "Comfortable learning unfamiliar stacks" }
    ],
    bullets: [
      "I am comfortable thinking about performance as a systems problem, not only a code problem.",
      "Infrastructure-oriented projects gave me practical instincts around concurrency, tooling, and runtime behavior.",
      "That makes the FastAPI optimization side of this role attractive rather than intimidating."
    ],
    tags: ["Python", "Backend", "Concurrency", "Linux"]
  },
  {
    id: "frontend",
    tab: "Modern frontend",
    blurb: "React-based UI work with product and data awareness.",
    kicker: "Frontend contribution",
    title: "I can contribute on the frontend while still thinking like a full-stack engineer.",
    summary:
      "The role includes React, Tailwind CSS, Next.js, and headless e-commerce infrastructure. My background in JavaScript, TypeScript, and React fits that well. I like frontend work most when it is tied to real product data, API integration, and cross-team iteration, which is clearly the case here.",
    metrics: [
      { label: "React fit", value: "Ready", note: "React and TypeScript experience" },
      { label: "Web base", value: "Solid", note: "HTML, CSS, JavaScript fundamentals" },
      { label: "API mindset", value: "Good", note: "Comfortable with integration-oriented work" }
    ],
    bullets: [
      "I can help build clean interfaces without losing sight of the backend shape behind them.",
      "Headless commerce is appealing because it combines frontend polish with systems thinking.",
      "That full-stack mix is a strong match for how I prefer to work."
    ],
    tags: ["React", "TypeScript", "Next.js-ready", "API integration"]
  },
  {
    id: "team",
    tab: "Collaboration",
    blurb: "Coachability, communication, and team-first habits.",
    kicker: "Remote team behavior",
    title: "The collaboration requirements fit my working style well.",
    summary:
      "The soft-skill section in your posting is unusually specific, which I appreciate. Team-first development, proactive communication, and early blocker reporting are signs of a strong engineering culture. Open-source work, public-facing roles, and self-directed projects helped me build the habits that make those expectations realistic.",
    metrics: [
      { label: "Git/GitHub", value: "Active", note: "Package maintenance and PR contributions" },
      { label: "Communication", value: "Clear", note: "Comfortable writing concise progress updates" },
      { label: "Coachability", value: "High", note: "Prefer feedback-rich environments" }
    ],
    bullets: [
      "I do well in teams that value transparency over silent solo work.",
      "I am looking for an internship where pair work, iteration, and feedback are normal.",
      "That makes this role feel like a strong cultural match as well as a technical one."
    ],
    tags: ["Remote collaboration", "Git", "Team-first", "Communication"]
  }
];

const proofItems = [
  {
    id: "homelab",
    name: "Homelab networking",
    type: "Systems + AI tooling",
    summary:
      "I built a segmented home network with pfSense, used Wazuh for logging, and wrote Python scripts with AI assistance to parse unsupported log sources.",
    signals: [
      "Comfort with systems, logging, and practical troubleshooting.",
      "Evidence that I already use AI tools inside technical workflows.",
      "Shows initiative around building useful tooling where off-the-shelf support is incomplete."
    ],
    relevance: [
      "Strong support for backend optimization and observability instincts.",
      "Relevant to AI-assisted engineering and data pipeline thinking.",
      "Shows I can handle messy, real-world technical inputs."
    ],
    tags: ["Python", "Wazuh", "pfSense", "AI-assisted tooling"]
  },
  {
    id: "ath",
    name: "!~ATH",
    type: "Deep implementation",
    summary:
      "I designed and built a custom programming language with a lexer, parser, and interpreters in Python and JavaScript.",
    signals: [
      "Strong decomposition of complex technical problems.",
      "Ability to move from abstract design to detailed implementation.",
      "Persistence with debugging, semantics, and edge cases."
    ],
    relevance: [
      "Useful signal for backend work that requires careful reasoning.",
      "Supports the claim that I can learn hard systems quickly.",
      "Shows I am comfortable owning nontrivial technical work."
    ],
    tags: ["Python", "JavaScript", "Parsers", "Interpreters"]
  },
  {
    id: "oss",
    name: "Open-source maintenance",
    type: "Collaborative engineering",
    summary:
      "I maintain multiple Arch User Repository packages and have contributed pull requests to other projects.",
    signals: [
      "Comfort working inside shared conventions and existing codebases.",
      "Experience reading other people’s code and contributing responsibly.",
      "Understands maintainability and iterative improvement."
    ],
    relevance: [
      "Direct fit for collaborative development and code quality expectations.",
      "Supports the team-first, communication-heavy culture described in the posting.",
      "Good evidence for reliable remote contribution habits."
    ],
    tags: ["Git", "GitHub", "AUR", "Maintenance"]
  },
  {
    id: "xcaca",
    name: "Xcaca",
    type: "Creative systems work",
    summary:
      "I worked on an X server that renders graphical output as ASCII art, which required understanding complex existing systems deeply enough to reinterpret them.",
    signals: [
      "Comfort in unusual technical territory.",
      "Creative engineering with low-level systems awareness.",
      "Strong curiosity and persistence."
    ],
    relevance: [
      "Useful for fast-moving environments where problems are not textbook cases.",
      "Supports the case that I can handle technical ambiguity.",
      "Reinforces a genuine builder mindset."
    ],
    tags: ["C", "Linux", "Systems", "Graphics"]
  }
];

const gainItems = [
  {
    label: "AI exposure",
    title: "Production-grade model workflows",
    text: "Hands-on experience with LLM tooling, RAG patterns, and document-analysis systems."
  },
  {
    label: "Product depth",
    title: "Real full-stack responsibility",
    text: "A role that spans backend performance, frontend refinement, and cloud deployment."
  },
  {
    label: "Career path",
    title: "Clear growth potential",
    text: "The possibility of full-time conversion makes the internship feel substantive and outcome-oriented."
  }
];

function renderList(items, className) {
  return h(
    "ul",
    { className },
    items.map((item) => h("li", { key: item }, item))
  );
}

function renderTags(items) {
  return h(
    "ul",
    { className: "tags" },
    items.map((item) => h("li", { key: item }, item))
  );
}

function App() {
  const [activeFit, setActiveFit] = useState("ai");
  const [activeProof, setActiveProof] = useState("homelab");

  const fit = fitItems.find((item) => item.id === activeFit) || fitItems[0];
  const proof = proofItems.find((item) => item.id === activeProof) || proofItems[0];

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return undefined;
    }

    const nodes = Array.from(document.querySelectorAll(".reveal"));
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12 }
    );

    nodes.forEach((node) => observer.observe(node));
    return () => observer.disconnect();
  }, []);

  return h(
    "div",
    { className: "shell" },
    h(
      "header",
      { className: "topbar" },
      h("a", { className: "brand", href: "#top" }, "Robin Reel // Builder Supply Link"),
      h(
        "nav",
        { className: "nav", "aria-label": "Primary" },
        h("a", { href: "#fit" }, "Role Fit"),
        h("a", { href: "#proof" }, "Evidence"),
        h("a", { href: "#gains" }, "Why This Role"),
        h("a", { href: "#close" }, "Closing")
      )
    ),
    h(
      "main",
      { id: "top" },
      h(
        "section",
        { className: "hero reveal" },
        h(
          "div",
          { className: "hero-copy" },
          h("p", { className: "eyebrow" }, "Interactive Cover Letter • AI Software Engineering Intern"),
          h(
            "h1",
            null,
            "I want to help Builder Supply Link build",
            h("span", null, " AI systems that can reason through architectural complexity.")
          ),
          h(
            "p",
            { className: "lede" },
            "I am an Information Technology student with hands-on experience in Python, JavaScript, React, TypeScript, Linux, Git, and AI-assisted technical workflows. This role is especially compelling because it combines backend performance, modern frontend work, and AI systems aimed at a concrete document-analysis problem."
          ),
          h(
            "div",
            { className: "action-row" },
            h("a", { className: "button button-primary", href: "#fit" }, "Review My Fit"),
            h("a", { className: "button button-secondary mono", href: "mailto:robin413@protonmail.com" }, "robin413@protonmail.com")
          ),
          h(
            "div",
            { className: "quick-grid", "aria-label": "Quick qualifications" },
            h("article", { className: "quick-card" }, h("strong", null, "Python, JavaScript, React"), h("span", null, "A practical base for AI-adjacent full-stack work")),
            h("article", { className: "quick-card" }, h("strong", null, "AI tool usage"), h("span", null, "Already using LLMs in technical problem solving")),
            h("article", { className: "quick-card" }, h("strong", null, "Linux, Git, networking"), h("span", null, "Systems perspective that supports backend work"))
          )
        ),
        h(
          "aside",
          { className: "hero-panel" },
          h("p", { className: "label" }, "Role Snapshot"),
          h("h2", null, "Why this internship fits my trajectory"),
          h(
            "div",
            { className: "score-grid" },
            h("article", { className: "score-card" }, h("strong", null, "AI systems"), h("span", null, "LLM usage, RAG interest, document-analysis curiosity")),
            h("article", { className: "score-card" }, h("strong", null, "Backend potential"), h("span", null, "Python foundation with strong systems instincts")),
            h("article", { className: "score-card" }, h("strong", null, "Frontend fit"), h("span", null, "React and TypeScript for data-driven interfaces")),
            h("article", { className: "score-card" }, h("strong", null, "Team match"), h("span", null, "Comfortable with collaborative, feedback-rich work"))
          ),
          h(
            "div",
            { className: "status-card" },
            h("p", { className: "label" }, "What stands out"),
            h(
              "p",
              null,
              "This is not a generic software internship. The mix of FastAPI performance work, headless commerce, and architectural-document AI makes the role unusually technical and unusually interesting."
            )
          )
        )
      ),
      h(
        "section",
        { className: "section reveal", id: "fit" },
        h(
          "div",
          { className: "section-head" },
          h("div", null, h("p", { className: "eyebrow" }, "Role Fit"), h("h2", null, "Where I can contribute and ramp quickly")),
          h("p", { className: "section-note" }, "My fit is strongest where AI curiosity, systems thinking, and practical full-stack work overlap.")
        ),
        h(
          "div",
          { className: "split-grid" },
          h(
            "div",
            { className: "tab-stack", role: "tablist", "aria-label": "Fit categories" },
            fitItems.map((item) =>
              h(
                "button",
                {
                  key: item.id,
                  className: `tab ${item.id === activeFit ? "is-active" : ""}`,
                  onClick: () => setActiveFit(item.id),
                  role: "tab",
                  "aria-selected": item.id === activeFit
                },
                h("strong", null, item.tab),
                h("span", null, item.blurb)
              )
            )
          ),
          h(
            "article",
            { className: "detail-panel" },
            h("p", { className: "label" }, fit.kicker),
            h("h3", null, fit.title),
            h("p", { className: "lede" }, fit.summary),
            h(
              "div",
              { className: "metric-grid" },
              fit.metrics.map((metric) =>
                h(
                  "div",
                  { className: "metric-card", key: metric.label },
                  h("strong", null, metric.value),
                  h("p", null, metric.label),
                  h("p", null, metric.note)
                )
              )
            ),
            renderList(fit.bullets, "list"),
            renderTags(fit.tags)
          )
        )
      ),
      h(
        "section",
        { className: "section reveal", id: "proof" },
        h(
          "div",
          { className: "section-head" },
          h("div", null, h("p", { className: "eyebrow" }, "Evidence"), h("h2", null, "Resume details with direct relevance")),
          h("p", { className: "section-note" }, "These examples best support the backend, AI-tooling, and collaborative engineering parts of the role.")
        ),
        h(
          "div",
          { className: "proof-grid" },
          h(
            "div",
            { className: "proof-stack" },
            proofItems.map((item) =>
              h(
                "button",
                {
                  key: item.id,
                  className: `proof-button ${item.id === activeProof ? "is-active" : ""}`,
                  onClick: () => setActiveProof(item.id)
                },
                h("strong", null, item.name),
                h("span", null, item.type)
              )
            )
          ),
          h(
            "article",
            { className: "detail-panel" },
            h("p", { className: "label" }, proof.type),
            h("h3", null, proof.name),
            h("p", { className: "lede" }, proof.summary),
            renderTags(proof.tags),
            h(
              "div",
              { className: "columns" },
              h("div", null, h("p", { className: "label" }, "What it shows"), renderList(proof.signals, "list")),
              h("div", null, h("p", { className: "label" }, "Why it matters here"), renderList(proof.relevance, "list"))
            )
          )
        )
      ),
      h(
        "section",
        { className: "section reveal", id: "gains" },
        h(
          "div",
          { className: "section-head" },
          h("div", null, h("p", { className: "eyebrow" }, "Why This Role"), h("h2", null, "What makes this internship especially valuable")),
          h("p", { className: "section-note" }, "The posting offers both technical depth and a credible path to long-term growth.")
        ),
        h(
          "div",
          { className: "gain-grid" },
          gainItems.map((item) =>
            h(
              "article",
              { className: "gain-card", key: item.title },
              h("p", { className: "label" }, item.label),
              h("strong", null, item.title),
              h("p", null, item.text)
            )
          )
        )
      ),
      h(
        "section",
        { className: "section reveal", id: "close" },
        h(
          "article",
          { className: "closing-card" },
          h("p", { className: "eyebrow" }, "Closing"),
          h("h2", null, "I would be ready to contribute, communicate clearly, and grow quickly inside a technically ambitious team."),
          h(
            "p",
            { className: "lede" },
            "Builder Supply Link’s focus on AI-powered automation, backend performance, and modern product engineering is exactly the kind of environment I want for my next stage of growth. I would welcome the chance to discuss how I could contribute as an AI Software Engineering Intern."
          ),
          h(
            "div",
            { className: "contact-row" },
            h("a", { className: "contact-pill mono", href: "mailto:robin413@protonmail.com" }, "robin413@protonmail.com"),
            h("a", { className: "contact-pill mono", href: "https://github.com/robinpie", target: "_blank", rel: "noreferrer" }, "github.com/robinpie"),
            h("span", { className: "contact-pill mono" }, "Springfield, MO")
          )
        )
      )
    )
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(h(App));

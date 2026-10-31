const { useEffect, useState } = React;
const h = React.createElement;

const fitItems = [
  {
    id: "analytics",
    tab: "Analytics fit",
    blurb: "Cleaning data, spotting patterns, and turning findings into something useful.",
    kicker: "Why the role fits",
    title: "I am drawn to work that turns messy information into decisions people can actually use.",
    summary:
      "The strongest part of this internship is that it connects data work to real operational and business decisions. Collecting, cleaning, exploring, and visualizing information is interesting to me because it turns raw inputs into something practical. The healthcare setting adds weight to that work because the quality of analysis affects how teams understand performance and prioritize action.",
    metrics: [
      { label: "Curiosity", value: "High", note: "I like asking why systems behave the way they do" },
      { label: "Analysis mindset", value: "Strong", note: "Comfortable moving from raw details to patterns" },
      { label: "Practicality", value: "Good", note: "Focused on useful outputs rather than abstract metrics" }
    ],
    bullets: [
      "I like analysis most when it informs real decisions rather than just filling a report.",
      "This role’s mix of business intelligence and product support is especially appealing.",
      "That makes the internship feel applied and substantive rather than purely observational."
    ],
    tags: ["EDA", "Insight generation", "Business intelligence", "Healthcare context"]
  },
  {
    id: "sql",
    tab: "Data foundation",
    blurb: "SQL, structured thinking, and comfort with data-oriented tools.",
    kicker: "Core technical fit",
    title: "My background gives me a credible base for analytics and data-engineering work.",
    summary:
      "I already have experience with SQL, scripting, Linux, and technical problem solving across multiple environments. My resume is broader than a pure analytics profile, but that is useful here. It means I can reason about data quality, tooling, transformation steps, and the systems around the data instead of treating analysis as an isolated spreadsheet task.",
    metrics: [
      { label: "SQL", value: "Relevant", note: "Comfortable with structured data work" },
      { label: "Technical range", value: "Broad", note: "Python, JavaScript, SQL, Linux, Bash" },
      { label: "Data hygiene", value: "Careful", note: "Attention to details and edge cases matters to me" }
    ],
    bullets: [
      "I can contribute to analytics work while still thinking about the pipeline behind it.",
      "That broader technical base fits an internship touching both insight generation and ETL-style work.",
      "I am comfortable learning new tools quickly when the underlying logic is clear."
    ],
    tags: ["SQL", "Data pipelines", "Technical range", "Data quality"]
  },
  {
    id: "communication",
    tab: "Communication",
    blurb: "Clear writing, stakeholder awareness, and presentation-minded thinking.",
    kicker: "Working with people around the data",
    title: "The communication side of analytics is one of the reasons this role appeals to me.",
    summary:
      "Good analytics work is not only about correctness. It is also about explaining findings clearly, understanding stakeholder needs, and presenting information in a way that helps people act. My background includes public-facing work and collaborative environments that required clarity, patience, and translating information for different audiences.",
    metrics: [
      { label: "Writing", value: "Clear", note: "Concise communication is one of my strengths" },
      { label: "Stakeholder sense", value: "Useful", note: "Understand the need to tailor communication" },
      { label: "Presentation", value: "Developing", note: "Interested in growing this skill further" }
    ],
    bullets: [
      "I understand that a dashboard only matters if someone can use it confidently.",
      "That makes the customer-success and cross-functional parts of the role especially interesting.",
      "I would take the reporting and presentation side of the internship seriously."
    ],
    tags: ["Communication", "Reporting", "Stakeholders", "Presentation"]
  },
  {
    id: "values",
    tab: "Values match",
    blurb: "Curiosity, resourcefulness, compassion, and teamwork.",
    kicker: "How I work",
    title: "The values section reads like the kind of environment where I would do good work.",
    summary:
      "The values in the posting are unusually specific, and that matters. Intellectual curiosity, resourcefulness, open-mindedness, and compassion are not generic add-ons in healthcare work. They shape how people collaborate and how carefully they approach data. Those values line up well with how I tend to work: ask questions, use available tools, stay useful, and treat the work and the people around it with care.",
    metrics: [
      { label: "Curiosity", value: "Genuine", note: "I want to understand the why behind the process" },
      { label: "Resourcefulness", value: "Strong", note: "Used to figuring things out with available tools" },
      { label: "Team fit", value: "Good", note: "Comfortable in collaborative environments" }
    ],
    bullets: [
      "I prefer teams that care about both rigor and how people work together.",
      "The healthcare setting makes compassion and open-mindedness feel especially important.",
      "That makes this internship feel like a cultural fit as well as a technical one."
    ],
    tags: ["Curiosity", "Resourcefulness", "Teamwork", "Compassion"]
  }
];

const proofItems = [
  {
    id: "homelab",
    name: "Homelab networking",
    type: "Data and systems thinking",
    summary:
      "I configured a segmented home network, used Wazuh for logging, and wrote Python scripts with AI assistance to parse unsupported log sources.",
    signals: [
      "Comfort with messy data sources and practical troubleshooting.",
      "Evidence of interest in gathering, cleaning, and interpreting information.",
      "Strong systems awareness beyond the surface level of an application."
    ],
    relevance: [
      "Directly relevant to working with datasets from multiple sources.",
      "Supports the pipeline and infrastructure-monitoring parts of the role.",
      "Shows I can stay useful when the data is imperfect."
    ],
    tags: ["Python", "Logs", "Tooling", "Systems"]
  },
  {
    id: "ath",
    name: "!~ATH",
    type: "Structured problem solving",
    summary:
      "I built a custom programming language with a lexer, parser, and interpreters in Python and JavaScript.",
    signals: [
      "Strong decomposition of complex problems into logical stages.",
      "Attention to detail and comfort with abstract structure.",
      "Persistence with debugging and precision."
    ],
    relevance: [
      "Useful for analytics work that depends on careful thinking and accuracy.",
      "Supports the claim that I can handle technically demanding tasks.",
      "Reinforces that I do well with complexity instead of avoiding it."
    ],
    tags: ["Python", "JavaScript", "Logic", "Precision"]
  },
  {
    id: "oss",
    name: "Open-source maintenance",
    type: "Reliability and stewardship",
    summary:
      "I maintain several Arch User Repository packages and have contributed pull requests to other projects.",
    signals: [
      "Comfort with recurring responsibilities and clean maintenance work.",
      "Strong habits around documentation and shared systems.",
      "Experience working responsibly inside collaborative workflows."
    ],
    relevance: [
      "Useful for maintaining dashboards, reports, and data processes over time.",
      "Supports the reliability and teamwork aspects of the internship.",
      "Shows that I can contribute steadily rather than only in bursts."
    ],
    tags: ["Maintenance", "Shared systems", "Git", "Consistency"]
  },
  {
    id: "ballot",
    name: "Ballot initiative outreach",
    type: "Communication under pressure",
    summary:
      "I gathered signatures for a ballot initiative, which required clear communication, deadline discipline, and regular interaction with a wide range of people.",
    signals: [
      "Comfortable communicating clearly with different audiences.",
      "Able to stay organized while working toward visible goals.",
      "Good practical sense for how people receive information."
    ],
    relevance: [
      "Supports stakeholder communication and presentation aspects of analytics work.",
      "Useful in a matrixed organization where collaboration matters.",
      "Shows that I can stay effective in fast-moving environments."
    ],
    tags: ["Communication", "Deadlines", "Stakeholders", "Execution"]
  }
];

const gainItems = [
  {
    label: "Applied work",
    title: "A real analytics internship, not a passive one",
    text: "The role offers hands-on experience with data cleaning, reporting, dashboards, and pipeline work rather than observation alone."
  },
  {
    label: "Healthcare",
    title: "Insight work tied to meaningful operations",
    text: "The healthcare context gives business intelligence work real practical stakes and makes the outcomes more meaningful."
  },
  {
    label: "Growth",
    title: "A strong bridge into analytics or data engineering",
    text: "The mix of business insight and technical pipeline exposure makes this a useful internship for either path."
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
  const [activeFit, setActiveFit] = useState("analytics");
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
      h("a", { className: "brand", href: "#top" }, "Robin Reel // Sound Physicians"),
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
          h("p", { className: "eyebrow" }, "Interactive Cover Letter • Data & Analytics Intern"),
          h(
            "h1",
            null,
            "I want to help Sound Physicians turn",
            h("span", null, " complex data into useful operational insight.")
          ),
          h(
            "p",
            { className: "lede" },
            "I am an Information Technology student with experience in SQL, Python, JavaScript, Linux, Git, technical troubleshooting, and self-directed project work. This internship stands out because it combines analytics, reporting, pipeline support, and healthcare operations in a way that feels both practical and meaningful."
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
            h("article", { className: "quick-card" }, h("strong", null, "SQL, Python, JavaScript"), h("span", null, "A good technical base for analytics and pipeline work")),
            h("article", { className: "quick-card" }, h("strong", null, "Systems and tooling perspective"), h("span", null, "Comfortable with Linux, logs, and troubleshooting")),
            h("article", { className: "quick-card" }, h("strong", null, "Communication and curiosity"), h("span", null, "Interested in both the numbers and the why behind them"))
          )
        ),
        h(
          "aside",
          { className: "hero-panel" },
          h("p", { className: "label" }, "Role Snapshot"),
          h("h2", null, "Why this internship is a strong match"),
          h(
            "div",
            { className: "score-grid" },
            h("article", { className: "score-card" }, h("strong", null, "Analytics"), h("span", null, "Cleaning data, exploring patterns, generating insight")),
            h("article", { className: "score-card" }, h("strong", null, "Reporting"), h("span", null, "Dashboards, visualization, and useful outputs")),
            h("article", { className: "score-card" }, h("strong", null, "Pipelines"), h("span", null, "Interest in ETL and infrastructure support")),
            h("article", { className: "score-card" }, h("strong", null, "Values"), h("span", null, "Curiosity, resourcefulness, teamwork, compassion"))
          ),
          h(
            "div",
            { className: "status-card" },
            h("p", { className: "label" }, "What stands out"),
            h(
              "p",
              null,
              "The role is unusually well balanced: business intelligence, customer success, and technical data work all in one internship. That is exactly the kind of range I find useful."
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
          h("div", null, h("p", { className: "eyebrow" }, "Role Fit"), h("h2", null, "How my background maps to the work")),
          h("p", { className: "section-note" }, "My fit is strongest where technical range, curiosity, and communication overlap with practical analytics work.")
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
          h("p", { className: "section-note" }, "These examples best support my case for analytical thinking, reliable execution, and working well across technical and business contexts.")
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
          h("div", null, h("p", { className: "eyebrow" }, "Why This Role"), h("h2", null, "What makes this internship especially useful")),
          h("p", { className: "section-note" }, "The opportunity offers exactly the mix of technical and business-facing experience that makes an analytics internship worth doing.")
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
          h("h2", null, "I would be ready to contribute carefully, learn quickly, and turn data work into something genuinely useful."),
          h(
            "p",
            { className: "lede" },
            "Sound Physicians offers the combination I want most in an internship: meaningful healthcare context, practical analytics work, and exposure to both business intelligence and data-engineering workflows. I would welcome the opportunity to contribute as a Data & Analytics Intern during the June 1, 2026 through August 7, 2026 program."
          ),
          h(
            "div",
            { className: "contact-row" },
            h("a", { className: "contact-pill mono", href: "mailto:robin413@protonmail.com" }, "robin413@protonmail.com"),
            h("a", { className: "contact-pill mono", href: "https://github.com/robinpie", target: "_blank", rel: "noreferrer" }, "github.com/robinpie"),
            h("span", { className: "contact-pill mono" }, "Springfield, MO"),
            h("span", { className: "contact-pill mono" }, "Summer 2026 available")
          )
        )
      )
    )
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(h(App));

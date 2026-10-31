const { useEffect, useState } = React;
const h = React.createElement;

const fitItems = [
  {
    id: "operations",
    tab: "Operations fit",
    blurb: "Clean systems, accurate records, and dependable follow-through.",
    kicker: "Why the role fits",
    title: "I am well suited to work where careful data handling directly supports mission-critical operations.",
    summary:
      "The strongest part of this internship is that the data work is tied to real outreach and hotline operations. Cleaning records, maintaining tracking systems, and compiling useful metrics are not background tasks here. They directly support services that matter. That makes the work more meaningful and gives accuracy, consistency, and organization real weight.",
    metrics: [
      { label: "Detail focus", value: "Strong", note: "I take accuracy and consistency seriously" },
      { label: "Operations mindset", value: "Good", note: "I like work that improves the system, not just the report" },
      { label: "Reliability", value: "High", note: "Follow-through matters to me" }
    ],
    bullets: [
      "I am comfortable with recurring operational work when it clearly supports a larger mission.",
      "This role’s combination of data cleaning and service-oriented reporting is especially compelling.",
      "That makes the internship feel useful rather than abstract."
    ],
    tags: ["Operations", "Data quality", "Tracking systems", "Mission support"]
  },
  {
    id: "tools",
    tab: "Spreadsheet and data fit",
    blurb: "Excel, structured data work, and careful organization.",
    kicker: "Core technical fit",
    title: "My current skill set matches the practical tools this internship actually uses.",
    summary:
      "NVPH is not asking for a heavy engineering stack. It needs someone who can work carefully with spreadsheets, databases, and internal tracking systems. That aligns well with my background. I have experience with SQL, advanced Excel, Microsoft Office tools, and the kind of structured thinking required to keep data usable over time.",
    metrics: [
      { label: "Excel", value: "Advanced", note: "Cengage Microsoft Excel Advanced certification" },
      { label: "SQL", value: "Relevant", note: "Comfortable working with structured data" },
      { label: "Organization", value: "Strong", note: "I work carefully with detail-heavy systems" }
    ],
    bullets: [
      "I can contribute immediately to spreadsheet-heavy and database-adjacent work.",
      "The role’s emphasis on cleaning and maintaining data is a practical fit for me.",
      "I am comfortable learning specific internal systems quickly."
    ],
    tags: ["Excel", "SQL", "Data cleaning", "Database management"]
  },
  {
    id: "reporting",
    tab: "Reporting and communication",
    blurb: "Turning operational information into clear summaries.",
    kicker: "Insight and communication",
    title: "I care about making data understandable, not just technically correct.",
    summary:
      "Compiling metrics and impact summaries only matters if the result is clear and usable. I am interested in analytics work because it sits between careful data handling and practical communication. My background includes public-facing work and explaining information clearly under pressure, which supports the reporting side of this internship as much as the cleaning side.",
    metrics: [
      { label: "Clarity", value: "Strong", note: "I prefer concise, usable communication" },
      { label: "Analysis", value: "Developing", note: "Interested in growing through applied reporting work" },
      { label: "Stakeholder sense", value: "Useful", note: "I think about how information will be received" }
    ],
    bullets: [
      "Good reporting should help staff act, not just archive numbers.",
      "I would take internal summaries and external-facing metrics seriously.",
      "That communication layer is part of why the role is appealing."
    ],
    tags: ["Impact summaries", "Metrics", "Communication", "Reporting"]
  },
  {
    id: "mission",
    tab: "Mission alignment",
    blurb: "Interested in social-impact operations and public-serving systems.",
    kicker: "Why NVPH",
    title: "I am motivated by work that supports people in difficult real-world situations.",
    summary:
      "The nonprofit and violence-prevention context matters here. Supporting outreach and crisis-intervention systems is serious work, and the quality of internal operations has real downstream effects. I would approach the role with respect for that context and with the understanding that careful operational data work can make public-serving programs stronger.",
    metrics: [
      { label: "Mission interest", value: "Genuine", note: "Social-impact work is more meaningful to me than generic business reporting" },
      { label: "Maturity", value: "Important", note: "I would treat the subject matter with care" },
      { label: "Remote fit", value: "Good", note: "Comfortable working independently and responsibly" }
    ],
    bullets: [
      "I would not treat the role as just a spreadsheet exercise.",
      "The mission gives the operations work context and purpose.",
      "That makes the internship especially compelling."
    ],
    tags: ["Nonprofit", "Social impact", "Operations", "Public service"]
  }
];

const proofItems = [
  {
    id: "ballot",
    name: "Ballot initiative signature gathering",
    type: "Mission-oriented outreach work",
    summary:
      "I worked on ballot initiative signature gathering with the Missouri Workers Center, which involved community engagement, deadline discipline, and signature verification.",
    signals: [
      "Comfort working in mission-driven environments with public impact.",
      "Experience balancing outreach activity with accuracy and verification.",
      "Able to stay organized under hard deadlines."
    ],
    relevance: [
      "Directly relevant to outreach tracking and operational reporting.",
      "Supports the social-impact side of the role in a way that is concrete, not abstract.",
      "Shows I understand that public-serving work depends on both people skills and accurate records."
    ],
    tags: ["Outreach", "Verification", "Mission work", "Deadlines"]
  },
  {
    id: "excel",
    name: "Advanced Excel certification",
    type: "Practical data-tool readiness",
    summary:
      "I earned the Cengage Microsoft Excel Advanced certification, which reflects comfort with spreadsheet-based workflows and data organization.",
    signals: [
      "A practical base for spreadsheet-heavy operational work.",
      "Comfort with structured data and careful documentation.",
      "Willingness to build applied tool proficiency, not only theoretical knowledge."
    ],
    relevance: [
      "Highly relevant to the role’s emphasis on spreadsheets, tracking systems, and data cleaning.",
      "Supports immediate usefulness in day-to-day nonprofit operations work.",
      "Shows that I can contribute with the tools the role actually uses."
    ],
    tags: ["Excel", "Spreadsheets", "Data organization", "Tool readiness"]
  },
  {
    id: "homelab",
    name: "Homelab networking",
    type: "Data hygiene and systems awareness",
    summary:
      "I configured a segmented home network, used Wazuh for logging, and wrote Python scripts and AI tools to parse unsupported log sources.",
    signals: [
      "Comfort cleaning up imperfect technical data and making it usable.",
      "Strong systems awareness and process-oriented thinking.",
      "Resourcefulness in solving messy information problems."
    ],
    relevance: [
      "Supports the data-scrubbing and workflow-improvement parts of the role.",
      "Shows I can work through messy records instead of expecting clean input.",
      "Reinforces the values of curiosity and resourcefulness."
    ],
    tags: ["Data cleanup", "Resourcefulness", "Systems thinking", "Python"]
  },
  {
    id: "oss",
    name: "Open-source maintenance",
    type: "Consistency and stewardship",
    summary:
      "I maintain several Arch User Repository packages and have contributed pull requests to other projects.",
    signals: [
      "Comfort with recurring maintenance responsibilities.",
      "Strong habits around consistency, documentation, and shared systems.",
      "Able to contribute steadily in collaborative environments."
    ],
    relevance: [
      "Useful for maintaining contact databases, tracking systems, and recurring reports.",
      "Supports the idea that I can handle careful, ongoing operational work.",
      "Shows reliability rather than only one-time project energy."
    ],
    tags: ["Maintenance", "Documentation", "Consistency", "Shared systems"]
  }
];

const gainItems = [
  {
    label: "Mission",
    title: "Operational work with real social impact",
    text: "This role connects everyday data accuracy to programs that support violence prevention and crisis intervention."
  },
  {
    label: "Experience",
    title: "A practical nonprofit operations internship",
    text: "The internship offers direct experience with reporting, tracking, and workflow improvement rather than passive observation."
  },
  {
    label: "Growth",
    title: "A strong bridge into applied analytics",
    text: "The mix of data cleaning, basic analysis, and impact summaries is exactly the kind of work that builds useful operational judgment."
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
  const [activeFit, setActiveFit] = useState("operations");
  const [activeProof, setActiveProof] = useState("ballot");

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
      h("a", { className: "brand", href: "#top" }, "Robin Reel // NVPH"),
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
          h("p", { className: "eyebrow" }, "Interactive Cover Letter • Data Analytics & Operations Intern"),
          h(
            "h1",
            null,
            "I want to help NVPH keep",
            h("span", null, " mission-critical outreach data accurate, organized, and useful.")
          ),
          h(
            "p",
            { className: "lede" },
            "I am an Information Technology student with experience in advanced Excel, SQL, technical troubleshooting, data-oriented project work, and mission-driven outreach experience. This role stands out because it connects data cleaning, internal reporting, and workflow improvement to programs that support violence prevention and crisis intervention."
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
            h("article", { className: "quick-card" }, h("strong", null, "Advanced Excel and SQL"), h("span", null, "A practical base for spreadsheets, reporting, and structured data work")),
            h("article", { className: "quick-card" }, h("strong", null, "Detail-oriented operations mindset"), h("span", null, "Comfortable with recurring accuracy and maintenance work")),
            h("article", { className: "quick-card" }, h("strong", null, "Mission-linked experience"), h("span", null, "Previous outreach and verification work in a public-serving setting"))
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
            h("article", { className: "score-card" }, h("strong", null, "Data cleaning"), h("span", null, "Accuracy, consistency, and usable records")),
            h("article", { className: "score-card" }, h("strong", null, "Reporting"), h("span", null, "Metrics, summaries, and operational insight")),
            h("article", { className: "score-card" }, h("strong", null, "Workflow support"), h("span", null, "Tracking systems and process improvement")),
            h("article", { className: "score-card" }, h("strong", null, "Mission context"), h("span", null, "Nonprofit operations with real public impact"))
          ),
          h(
            "div",
            { className: "status-card" },
            h("p", { className: "label" }, "What stands out"),
            h(
              "p",
              null,
              "This role is appealing because it treats operational data as part of program strength, not just administrative overhead."
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
          h("p", { className: "section-note" }, "My fit is strongest where careful data handling, spreadsheet fluency, and mission-oriented operations overlap.")
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
          h("p", { className: "section-note" }, "These examples best support my case for accurate records work, mission alignment, and careful operational reporting.")
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
          h("div", null, h("p", { className: "eyebrow" }, "Why This Role"), h("h2", null, "What makes this internship especially worthwhile")),
          h("p", { className: "section-note" }, "The role offers the exact kind of operational experience that can make data work more grounded and more meaningful.")
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
          h("h2", null, "I would be ready to contribute carefully, support the operation, and treat the mission with the seriousness it deserves."),
          h(
            "p",
            { className: "lede" },
            "NVPH offers a strong opportunity to do data and operations work that is directly connected to outreach effectiveness and crisis-response support. I would welcome the opportunity to contribute as a Data Analytics & Operations Intern and help strengthen the systems behind that work."
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

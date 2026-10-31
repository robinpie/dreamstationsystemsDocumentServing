const { useEffect, useState } = React;
const h = React.createElement;

const fitItems = [
  {
    id: "automation",
    tab: "Automation fit",
    blurb: "Workflow logic, prompt thinking, and practical systems improvement.",
    kicker: "Why this role fits",
    title: "I am drawn to automation work that makes internal systems faster, clearer, and more reliable.",
    summary:
      "The most compelling part of this internship is that it focuses on applied automation rather than something nebulous. Task routing, data validation, summarization, classification, and notification workflows are concrete problems with visible operational value. That makes the role attractive to me because I like work where logic, tooling, and usability all matter at the same time.",
    metrics: [
      { label: "Automation interest", value: "High", note: "Interested in workflows that remove friction" },
      { label: "AI practicality", value: "Strong", note: "Prefer grounded AI use over vague experimentation" },
      { label: "Systems mindset", value: "Useful", note: "Comfortable thinking about inputs, outputs, and failure points" }
    ],
    bullets: [
      "I am especially interested in the boundary between rule-based automation and AI-assisted decision support.",
      "This role feels useful because the work is tied to internal teams and real operational needs.",
      "That kind of applied automation is much more compelling to me than generic AI branding."
    ],
    tags: ["Automation", "Workflow design", "Prompt logic", "Operational value"]
  },
  {
    id: "testing",
    tab: "QA mindset",
    blurb: "Edge cases, validation, and careful thinking about failure modes.",
    kicker: "Quality and reliability",
    title: "My strongest fit may be the way I think about correctness, not just implementation.",
    summary:
      "The posting emphasizes testing, evaluating automation quality, and thinking critically about edge cases. That aligns with how I naturally work. I tend to break systems down, look for failure scenarios, and care about how a workflow behaves when the inputs are messy or unexpected. That is exactly the mindset useful in early automation work.",
    metrics: [
      { label: "Detail orientation", value: "Strong", note: "I take edge cases and precision seriously" },
      { label: "Quality focus", value: "High", note: "Interested in whether outputs are actually useful" },
      { label: "Testing mindset", value: "Natural", note: "Comfortable thinking in positive and negative scenarios" }
    ],
    bullets: [
      "I do not assume a workflow is good just because it technically runs.",
      "I care about consistency, usefulness, and what breaks when assumptions fail.",
      "That makes the validation side of this role especially appealing."
    ],
    tags: ["QA thinking", "Edge cases", "Validation", "Failure analysis"]
  },
  {
    id: "ai",
    tab: "AI-assisted workflows",
    blurb: "Introductory AI understanding with real curiosity and hands-on use.",
    kicker: "AI and prompt design",
    title: "I already use AI tools in technical work, and I want deeper experience applying them responsibly.",
    summary:
      "I have already used AI tools in technical projects, and what interests me most is not novelty but controlled usefulness. This role’s focus on prompts, decision logic, summarization, classification, and improvement loops is a strong match for that interest. It treats AI as part of a system that needs structure, review, and iteration.",
    metrics: [
      { label: "LLM exposure", value: "Active", note: "Already using AI tools in technical workflows" },
      { label: "Responsible use", value: "Important", note: "I care about quality and privacy implications" },
      { label: "Experimentation", value: "Genuine", note: "Interested in iterative improvement under feedback" }
    ],
    bullets: [
      "I think AI is most useful when it is constrained by good workflow design.",
      "The role’s focus on quality, feedback, and refinement is exactly right.",
      "That makes this a strong learning opportunity rather than just an AI buzzword role."
    ],
    tags: ["LLMs", "Prompts", "Summarization", "Responsible AI"]
  },
  {
    id: "agile",
    tab: "Team process",
    blurb: "Agile collaboration, documentation, and cross-functional work.",
    kicker: "How I work with teams",
    title: "The process side of the internship is as appealing to me as the technology.",
    summary:
      "Daily standups, sprint planning, retrospectives, documentation, and collaboration across engineering, product, and operations are all good signs. They suggest a team that expects interns to work in the real process, not outside it. That matters to me. I want an internship where I am part of the system of delivery, not only assigned isolated tasks.",
    metrics: [
      { label: "Collaboration", value: "Strong", note: "Comfortable working across different functions" },
      { label: "Communication", value: "Clear", note: "I write and explain progress concisely" },
      { label: "Organization", value: "Reliable", note: "I value documentation and follow-through" }
    ],
    bullets: [
      "I work best when expectations are visible and iteration is normal.",
      "The Agile structure makes the internship feel substantive and well run.",
      "That process exposure is part of the value of the role for me."
    ],
    tags: ["Agile", "Documentation", "Cross-functional work", "Remote collaboration"]
  }
];

const proofItems = [
  {
    id: "homelab",
    name: "Homelab networking",
    type: "Applied automation instincts",
    summary:
      "I configured a segmented home network, used Wazuh for logging, and wrote Python scripts with AI assistance to parse unsupported log sources.",
    signals: [
      "Comfort with practical automation around imperfect systems.",
      "Evidence that I already use AI tools to extend existing workflows.",
      "Systems awareness that helps when thinking about inputs, outputs, and infrastructure."
    ],
    relevance: [
      "Directly relevant to AI-assisted internal automation work.",
      "Supports the quality-evaluation and workflow-refinement side of the role.",
      "Shows I am comfortable solving operational problems with a mix of scripts and AI tools."
    ],
    tags: ["Python", "Automation", "Logs", "AI-assisted tooling"]
  },
  {
    id: "ath",
    name: "!~ATH",
    type: "Logic and precision",
    summary:
      "I built a custom programming language with a lexer, parser, and interpreters in Python and JavaScript.",
    signals: [
      "Strong decomposition of logic into structured stages.",
      "Comfort reasoning carefully about correctness and edge cases.",
      "Persistence with debugging and semantics."
    ],
    relevance: [
      "Useful for prompt logic, workflow conditions, and automation decision paths.",
      "Supports the testing-oriented mindset this role needs.",
      "Shows I can handle complex behavior without losing precision."
    ],
    tags: ["Python", "JavaScript", "Logic", "Edge cases"]
  },
  {
    id: "oss",
    name: "Open-source maintenance",
    type: "Documentation and stewardship",
    summary:
      "I maintain several Arch User Repository packages and have contributed pull requests to other projects.",
    signals: [
      "Comfort with ongoing maintenance rather than one-off feature work only.",
      "Good habits around documentation, shared conventions, and reliability.",
      "Experience contributing responsibly inside collaborative workflows."
    ],
    relevance: [
      "Relevant to maintaining automation documentation and usage guidelines.",
      "Supports the organizational side of the role.",
      "Shows I can be dependable in shared systems over time."
    ],
    tags: ["Documentation", "Maintenance", "Shared systems", "Git"]
  },
  {
    id: "ballot",
    name: "Ballot initiative outreach",
    type: "Communication and execution",
    summary:
      "I gathered signatures for a ballot initiative, which required clear communication, deadline discipline, and steady execution in public-facing work.",
    signals: [
      "Strong practical communication in changing situations.",
      "Ability to stay organized under visible goals and timelines.",
      "Comfort working with different people and perspectives."
    ],
    relevance: [
      "Useful in cross-functional team environments and standup-driven work.",
      "Supports the communication and prioritization aspects of the internship.",
      "Shows I can stay effective in fast-moving settings."
    ],
    tags: ["Communication", "Execution", "Deadlines", "Adaptability"]
  }
];

const gainItems = [
  {
    label: "Practical AI",
    title: "A grounded way to learn automation",
    text: "This role offers exposure to AI where quality, evaluation, and workflow design matter as much as the model itself."
  },
  {
    label: "Healthcare ops",
    title: "Automation with real operational value",
    text: "Improving internal systems in a healthcare organization gives the work clear stakes and clear usefulness."
  },
  {
    label: "Process",
    title: "Experience inside a real delivery team",
    text: "Agile rituals, documentation, and cross-functional collaboration make this internship valuable beyond the technical tooling alone."
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
  const [activeFit, setActiveFit] = useState("automation");
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
      h("a", { className: "brand", href: "#top" }, "Robin Reel // Sound Physicians Automation"),
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
          h("p", { className: "eyebrow" }, "Interactive Cover Letter • Software Development Intern"),
          h(
            "h1",
            null,
            "I want to help Sound Physicians build",
            h("span", null, " automation that is useful, testable, and trustworthy.")
          ),
          h(
            "p",
            { className: "lede" },
            "I am an Information Technology student with experience in Python, JavaScript, Linux, Git, technical troubleshooting, and AI-assisted workflows. This internship stands out because it focuses on applied automation inside a real healthcare organization, with equal attention to prompts, logic, testing, documentation, and team process."
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
            h("article", { className: "quick-card" }, h("strong", null, "Automation-minded"), h("span", null, "Interested in practical AI workflow improvement, not just hype")),
            h("article", { className: "quick-card" }, h("strong", null, "QA-oriented"), h("span", null, "Comfortable thinking about edge cases and failure scenarios")),
            h("article", { className: "quick-card" }, h("strong", null, "Technical base"), h("span", null, "Python, JavaScript, Linux, Git, systems thinking"))
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
            h("article", { className: "score-card" }, h("strong", null, "Intelligent automation"), h("span", null, "Rule-based and AI-assisted workflow support")),
            h("article", { className: "score-card" }, h("strong", null, "Testing mindset"), h("span", null, "Validation, consistency, and usefulness matter")),
            h("article", { className: "score-card" }, h("strong", null, "Prompt logic"), h("span", null, "Interested in inputs, outputs, and decision design")),
            h("article", { className: "score-card" }, h("strong", null, "Agile team fit"), h("span", null, "Standups, sprints, retrospectives, and documentation"))
          ),
          h(
            "div",
            { className: "status-card" },
            h("p", { className: "label" }, "What stands out"),
            h(
              "p",
              null,
              "The role treats automation quality as seriously as automation speed. That balance is exactly what makes the internship appealing."
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
          h("div", null, h("p", { className: "eyebrow" }, "Role Fit"), h("h2", null, "How my background maps to intelligent automation work")),
          h("p", { className: "section-note" }, "My fit is strongest where technical curiosity, testing instincts, and practical workflow thinking come together.")
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
          h("p", { className: "section-note" }, "These examples best support my case for workflow logic, quality thinking, and collaborative execution.")
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
          h("p", { className: "section-note" }, "The opportunity offers the exact mix of AI, process, and operational usefulness that makes automation work worth learning well.")
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
          h("h2", null, "I would be ready to contribute carefully, iterate quickly, and help build automation that people can trust."),
          h(
            "p",
            { className: "lede" },
            "Sound Physicians offers a strong environment for learning intelligent automation the right way: through collaboration, testing, documentation, and real operational value. I would welcome the opportunity to contribute as a Software Development Intern during the June 1, 2026 through August 7, 2026 program."
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

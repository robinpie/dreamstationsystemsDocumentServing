const { useEffect, useState } = React;
const h = React.createElement;

const fitItems = [
  {
    id: "frontend",
    tab: "Frontend work",
    blurb: "Responsive UI, React, and practical product delivery.",
    kicker: "Interface contribution",
    title: "I can contribute on the frontend from day one.",
    summary:
      "The role asks for responsive web application work with modern JavaScript and React-style frameworks. That aligns well with my background. I already work with JavaScript, TypeScript, React, and CSS, and I enjoy building interfaces that feel clean and usable.",
    metrics: [
      { label: "Core web", value: "Strong", note: "HTML, CSS, JavaScript" },
      { label: "Framework fit", value: "Ready", note: "React and TypeScript experience" },
      { label: "Product style", value: "Practical", note: "Focused on shippable UI" }
    ],
    bullets: [
      "I like turning requirements into working screens, not just prototypes.",
      "Responsive layout work is a good fit for how I think about frontend development.",
      "I value clarity and maintainability over unnecessary complexity."
    ],
    tags: ["React", "TypeScript", "Responsive UI", "CSS"]
  },
  {
    id: "backend",
    tab: "Backend range",
    blurb: "APIs, data flow, and cross-stack thinking.",
    kicker: "Beyond the interface",
    title: "I bring enough backend and systems awareness to work across the stack.",
    summary:
      "I am not limited to frontend concerns. My broader technical background includes Python, SQL, Bash, Linux, networking, and system-oriented projects. That makes it easier for me to reason about APIs, tooling, debugging, and how applications behave beyond the browser.",
    metrics: [
      { label: "Language range", value: "Wide", note: "JS, TS, Python, Java, C, SQL" },
      { label: "API mindset", value: "Solid", note: "Comfortable reasoning about REST patterns" },
      { label: "System sense", value: "Useful", note: "Linux and infrastructure experience" }
    ],
    bullets: [
      "I can move between interface concerns and the logic supporting them.",
      "My IT background helps when debugging spans multiple layers of a system.",
      "That range fits internships where responsibilities shift quickly."
    ],
    tags: ["APIs", "Node-ready", "SQL", "Systems thinking"]
  },
  {
    id: "remote",
    tab: "Remote collaboration",
    blurb: "Self-direction, communication, and reliable follow-through.",
    kicker: "Remote team fit",
    title: "I work well in environments that depend on clear communication and ownership.",
    summary:
      "Because this internship is remote, reliability matters as much as technical ability. Open-source contribution, package maintenance, and deadline-based work all helped me build habits that translate well to remote collaboration: writing clearly, working independently, and staying accountable.",
    metrics: [
      { label: "Git", value: "Active", note: "GitHub and shared repositories" },
      { label: "Self-direction", value: "High", note: "Project-driven learner" },
      { label: "Professionalism", value: "Proven", note: "Public-facing work under deadlines" }
    ],
    bullets: [
      "I am comfortable learning independently while still taking feedback well.",
      "Remote work is strongest when communication is concise and consistent.",
      "I am looking for a team where reviews and iteration improve the work."
    ],
    tags: ["Remote work", "Git", "Collaboration", "Accountability"]
  },
  {
    id: "growth",
    tab: "Intern mindset",
    blurb: "Fast learning, strong fundamentals, and coachability.",
    kicker: "Growth trajectory",
    title: "I am looking for an internship where I can contribute now and ramp quickly.",
    summary:
      "The strongest part of my profile is not that I already know everything in the posting. It is that I have solid fundamentals, broad technical curiosity, and a history of learning quickly by building real things. That is the profile I would bring to this internship.",
    metrics: [
      { label: "Learning speed", value: "Fast", note: "Comfortable ramping on unfamiliar tools" },
      { label: "Technical base", value: "Solid", note: "Programming plus systems background" },
      { label: "Intern fit", value: "High", note: "Coachability and genuine interest" }
    ],
    bullets: [
      "I am motivated by meaningful work and visible progress.",
      "I prefer internships with real responsibility and a high learning rate.",
      "That is why this role is appealing despite the broad stack."
    ],
    tags: ["Builder mindset", "Fast learner", "Internship fit", "Adaptability"]
  }
];

const proofItems = [
  {
    id: "ath",
    name: "!~ATH",
    type: "Complex implementation",
    summary:
      "I built a custom programming language with a lexer, parser, and interpreters in Python and JavaScript.",
    signals: [
      "Shows strong decomposition and implementation discipline.",
      "Proves I can take abstract ideas and make them operational.",
      "Demonstrates persistence with debugging and edge cases."
    ],
    relevance: [
      "Useful for application work that requires careful technical reasoning.",
      "Supports the case that I can own nontrivial tasks.",
      "Relevant to both frontend and backend problem solving."
    ],
    tags: ["Python", "JavaScript", "Parsers", "Interpreters"]
  },
  {
    id: "homelab",
    name: "Homelab networking",
    type: "Infrastructure perspective",
    summary:
      "I configured a segmented home network, used Wazuh for logging, and wrote Python scripts with AI assistance to parse unsupported logs.",
    signals: [
      "Comfort with systems, observability, and messy inputs.",
      "Practical experience using AI tools in technical workflows.",
      "Broadens my perspective beyond pure UI development."
    ],
    relevance: [
      "Makes me more useful when debugging full-stack issues.",
      "Supports backend and operational awareness.",
      "Shows initiative and self-directed problem solving."
    ],
    tags: ["Python", "Wazuh", "pfSense", "Automation"]
  },
  {
    id: "oss",
    name: "Open-source maintenance",
    type: "Remote collaboration signal",
    summary:
      "I maintain several Arch User Repository packages and have contributed pull requests to other projects.",
    signals: [
      "Comfortable contributing inside shared conventions.",
      "Used to reading other people’s code and making careful changes.",
      "Understands version control and iterative improvement."
    ],
    relevance: [
      "Direct fit for Git-based remote team workflows.",
      "Useful for maintenance, testing, and ongoing application support.",
      "Strong signal for collaboration and reliability."
    ],
    tags: ["Git", "GitHub", "AUR", "Maintenance"]
  },
  {
    id: "xcaca",
    name: "Xcaca",
    type: "Creative systems work",
    summary:
      "I worked on an X server that renders graphical output as ASCII art, which required understanding existing systems in depth.",
    signals: [
      "Comfort with unfamiliar technical terrain.",
      "Creative problem solving under constraints.",
      "Willingness to learn beyond standard coursework."
    ],
    relevance: [
      "Useful in internships where ambiguous problems are common.",
      "Shows technical curiosity and resilience.",
      "Supports the case that I learn by building."
    ],
    tags: ["C", "Linux", "Graphics", "Low-level work"]
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
  const [activeFit, setActiveFit] = useState("frontend");
  const [activeProof, setActiveProof] = useState("oss");

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
      h("a", { className: "brand", href: "#top" }, "Robin Reel // Porfyro"),
      h(
        "nav",
        { className: "nav", "aria-label": "Primary" },
        h("a", { href: "#fit" }, "Fit"),
        h("a", { href: "#proof" }, "Proof"),
        h("a", { href: "#close" }, "Close")
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
          h("p", { className: "eyebrow" }, "Interactive Cover Letter • Full Stack Developer Intern"),
          h(
            "h1",
            null,
            "I want to help Porfyro ship",
            h("span", null, " reliable full-stack products in a remote team.")
          ),
          h(
            "p",
            { className: "lede" },
            "I am an Information Technology student with hands-on experience in JavaScript, React, TypeScript, Python, Linux, Git, and system-oriented projects. This internship is appealing because it combines practical frontend work, backend awareness, and the accountability of a remote engineering environment."
          ),
          h(
            "div",
            { className: "action-row" },
            h("a", { className: "button button-primary", href: "#fit" }, "View My Fit"),
            h("a", { className: "button button-secondary mono", href: "mailto:robin413@protonmail.com" }, "robin413@protonmail.com")
          ),
          h(
            "div",
            { className: "quick-grid", "aria-label": "Quick qualifications" },
            h("article", { className: "quick-card" }, h("strong", null, "HTML, CSS, JavaScript"), h("span", null, "Comfortable with core frontend fundamentals")),
            h("article", { className: "quick-card" }, h("strong", null, "React, TypeScript, Python"), h("span", null, "Useful range across UI and application logic")),
            h("article", { className: "quick-card" }, h("strong", null, "Git, Linux, SQL, Bash"), h("span", null, "Good base for remote full-stack work"))
          )
        ),
        h(
          "aside",
          { className: "hero-panel" },
          h(
            "div",
            { className: "hero-panel-head" },
            h("div", null, h("p", { className: "section-label" }, "Role Snapshot"), h("h2", null, "Why I match this internship"))
          ),
          h(
            "div",
            { className: "score-grid" },
            h("article", { className: "score-card" }, h("strong", null, "Frontend"), h("span", null, "React, JavaScript, TypeScript, responsive layout work")),
            h("article", { className: "score-card" }, h("strong", null, "Backend-ready"), h("span", null, "Comfortable reasoning about APIs, data, and tooling")),
            h("article", { className: "score-card" }, h("strong", null, "Remote fit"), h("span", null, "Git-based collaboration and self-directed project work")),
            h("article", { className: "score-card" }, h("strong", null, "Fast learner"), h("span", null, "Strong fundamentals with broad technical curiosity"))
          ),
          h(
            "div",
            { className: "status-strip" },
            h("p", { className: "card-label" }, "Why this stands out"),
            h(
              "p",
              null,
              "The posting is broad in a good way. It asks for someone who can contribute across the stack, debug thoughtfully, and operate well with a remote team. That mix fits how I prefer to work."
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
          h("p", { className: "section-note" }, "The strongest overlap is not one single tool. It is the combination of web fundamentals, technical range, and remote-work discipline.")
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
            h("p", { className: "section-label" }, fit.kicker),
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
          h("div", null, h("p", { className: "eyebrow" }, "Proof"), h("h2", null, "Evidence from my resume")),
          h("p", { className: "section-note" }, "These examples show the kind of work habits and technical range I would bring to a full-stack internship.")
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
            h("p", { className: "section-label" }, proof.type),
            h("h3", null, proof.name),
            h("p", { className: "lede" }, proof.summary),
            renderTags(proof.tags),
            h(
              "div",
              { className: "columns" },
              h("div", null, h("p", { className: "card-label" }, "What it shows"), renderList(proof.signals, "list")),
              h("div", null, h("p", { className: "card-label" }, "Why it matters here"), renderList(proof.relevance, "list"))
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
          h("h2", null, "I would be ready to contribute quickly and keep improving inside a remote full-stack team."),
          h(
            "p",
            { className: "lede" },
            "Porfyro’s internship is appealing because it values practical web development, cross-stack curiosity, and dependable collaboration. I would welcome the chance to discuss how I could contribute as a Full Stack Developer Intern."
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

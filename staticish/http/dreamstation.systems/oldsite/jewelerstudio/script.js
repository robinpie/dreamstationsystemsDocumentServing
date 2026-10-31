const { useEffect, useState } = React;
const h = React.createElement;

const fitItems = [
  {
    id: "product",
    tab: "Feature shipping",
    blurb: "Useful features, clean execution, fast feedback.",
    kicker: "Public platform work",
    title: "I want an internship where shipped code matters immediately.",
    summary:
      "Jeweler Studio describes real feature delivery, real bugs, and real users. That is the right environment for me. I learn fastest when the work is visible, concrete, and held to a production standard.",
    metrics: [
      { label: "React fit", value: "Strong", note: "JavaScript, TypeScript, React" },
      { label: "Builder bias", value: "High", note: "Project-first learning style" },
      { label: "Startup pace", value: "Ready", note: "Comfortable with evolving scope" }
    ],
    bullets: [
      "My projects are implementation-heavy, not tutorial-level replicas.",
      "I like closing the loop from idea to working software.",
      "A fast product cycle is more motivating to me than narrowly scoped academic exercises."
    ],
    tags: ["React", "JavaScript", "Feature work", "Iteration"]
  },
  {
    id: "ai",
    tab: "AI-assisted development",
    blurb: "Curious about AI infrastructure and practical coding leverage.",
    kicker: "AI as a working tool",
    title: "The AI emphasis is a direct match for how I already like to work.",
    summary:
      "Your posting is unusually explicit about AI-assisted coding infrastructure. That stands out. I have already used AI tools in technical projects, including parsing custom log sources in my homelab, and I want deeper exposure to production-grade AI workflows.",
    metrics: [
      { label: "AI curiosity", value: "Real", note: "Used AI in technical experimentation" },
      { label: "Infra lens", value: "Useful", note: "Networking and systems background" },
      { label: "Learning mode", value: "Fast", note: "Comfortable ramping on new tools" }
    ],
    bullets: [
      "I treat AI as a force multiplier, not a substitute for technical judgment.",
      "Infrastructure-oriented work appeals to me because it links tooling to actual team velocity.",
      "I am especially interested in how AI can improve product quality and developer speed together."
    ],
    tags: ["AI tooling", "Automation", "Systems", "Experimentation"]
  },
  {
    id: "fullstack",
    tab: "Full-stack range",
    blurb: "UI comfort backed by systems and scripting depth.",
    kicker: "Frontend plus backend instincts",
    title: "I bring a useful mix of interface work and low-level curiosity.",
    summary:
      "The role spans responsive frontend work and backend logic. My resume is broad in a way that fits that. I have React and JavaScript fundamentals, but also enough systems experience to think beyond the surface layer of an application.",
    metrics: [
      { label: "Languages", value: "Wide", note: "JS, TS, Python, C, Java, SQL, Bash" },
      { label: "Platform sense", value: "Good", note: "Linux, Windows, networking" },
      { label: "Codebase range", value: "Cross-layer", note: "UI to infra-adjacent" }
    ],
    bullets: [
      "I can contribute on the frontend while still reasoning about data flow, reliability, and tooling.",
      "My IT background helps when software meets real environments and operational constraints.",
      "That range is useful in a small team where responsibilities move quickly."
    ],
    tags: ["Full stack", "React", "Node-ready", "Systems thinking"]
  },
  {
    id: "team",
    tab: "Team contribution",
    blurb: "Shared codebases, reviews, maintenance, professionalism.",
    kicker: "Working with others",
    title: "I am comfortable contributing inside a professional engineering loop.",
    summary:
      "This role mentions Git, GitHub, peer reviews, and exclusive clients. That combination calls for professionalism as much as technical skill. Open-source maintenance and public-facing work both helped me develop that discipline.",
    metrics: [
      { label: "Git/GitHub", value: "Active", note: "Open-source maintenance and PRs" },
      { label: "Professionalism", value: "Proven", note: "Client-facing and deadline-based work" },
      { label: "Coachability", value: "High", note: "Prefer feedback-rich environments" }
    ],
    bullets: [
      "I have maintained AUR packages and contributed changes in shared repos.",
      "Customer-facing work taught me clear communication and reliability under deadlines.",
      "I am looking for an internship where reviews and iteration raise the quality bar."
    ],
    tags: ["Git", "Code review", "Open source", "Client awareness"]
  }
];

const projectItems = [
  {
    id: "ath",
    name: "!~ATH",
    type: "Language tooling",
    summary:
      "I designed and built a custom esoteric programming language, including a lexer, parser, and interpreters in Python and JavaScript.",
    signals: [
      "Strong decomposition across syntax, parsing, and runtime behavior.",
      "Ability to turn abstract design ideas into working software.",
      "Persistence with debugging and edge cases."
    ],
    relevance: [
      "Useful for feature work that requires careful reasoning.",
      "Shows I do more than surface-level app assembly.",
      "Supports the builder mindset you described."
    ],
    tags: ["Python", "JavaScript", "Parsers", "Interpreters"]
  },
  {
    id: "homelab",
    name: "Homelab networking",
    type: "Systems + AI tooling",
    summary:
      "I built a segmented home network with pfSense, used Wazuh for logging, and wrote Python scripts with AI assistance to parse unsupported log sources.",
    signals: [
      "Comfort with infrastructure, networking, and operational thinking.",
      "Practical use of AI in a technical workflow.",
      "Bias toward building useful tools around imperfect systems."
    ],
    relevance: [
      "Directly aligns with interest in AI-assisted infrastructure.",
      "Suggests I can reason about reliability, monitoring, and messy real-world inputs.",
      "Adds backend and systems perspective beyond the UI."
    ],
    tags: ["Python", "Wazuh", "pfSense", "AI-assisted automation"]
  },
  {
    id: "xcaca",
    name: "Xcaca",
    type: "Systems programming",
    summary:
      "I worked on an X server that renders graphical output as ASCII art, which required understanding existing systems deeply enough to reinterpret them.",
    signals: [
      "Comfort exploring unusual technical terrain.",
      "Creative problem solving under heavy constraints.",
      "Willingness to learn beyond the obvious path."
    ],
    relevance: [
      "Good evidence that I can handle hard, unfamiliar problems.",
      "Fits a startup environment where solutions are rarely textbook.",
      "Shows initiative and technical curiosity."
    ],
    tags: ["C", "Linux", "Graphics", "Low-level work"]
  },
  {
    id: "oss",
    name: "Open-source maintenance",
    type: "Shared codebases",
    summary:
      "I maintain several Arch User Repository packages and have multiple pull requests merged into other projects.",
    signals: [
      "Comfort reading and modifying code written by others.",
      "Understands maintenance and compatibility over time.",
      "Used to contribution workflows instead of solo-only development."
    ],
    relevance: [
      "Directly relevant to GitHub-based team development.",
      "Supports code review readiness and shared ownership.",
      "Signals professional habits in collaborative environments."
    ],
    tags: ["Git", "GitHub", "AUR", "Maintenance"]
  }
];

function listItems(items, className) {
  return h(
    "ul",
    { className },
    items.map((item) => h("li", { key: item }, item))
  );
}

function tagItems(items) {
  return h(
    "ul",
    { className: "tag-row" },
    items.map((item) => h("li", { key: item }, item))
  );
}

function App() {
  const [activeFit, setActiveFit] = useState("product");
  const [activeProject, setActiveProject] = useState("homelab");
  const [hoverGlow, setHoverGlow] = useState({ x: 50, y: 18 });

  const activeFitItem = fitItems.find((item) => item.id === activeFit) || fitItems[0];
  const activeProjectItem =
    projectItems.find((item) => item.id === activeProject) || projectItems[0];

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return undefined;
    }

    const revealTargets = Array.from(document.querySelectorAll(".reveal"));
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

    revealTargets.forEach((target) => observer.observe(target));
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return undefined;
    }

    function handlePointerMove(event) {
      setHoverGlow({
        x: (event.clientX / window.innerWidth) * 100,
        y: (event.clientY / window.innerHeight) * 100
      });
    }

    window.addEventListener("pointermove", handlePointerMove);
    return () => window.removeEventListener("pointermove", handlePointerMove);
  }, []);

  return h(
    "div",
    {
      className: "page-shell",
      style: {
        background: `radial-gradient(circle at ${hoverGlow.x}% ${hoverGlow.y}%, rgba(255,255,255,0.24), transparent 24%)`
      }
    },
    h(
      "header",
      { className: "topbar" },
      h("a", { className: "brand", href: "#top" }, "Robin Reel"),
      h(
        "nav",
        { className: "nav", "aria-label": "Primary" },
        h("a", { href: "#fit" }, "Role Fit"),
        h("a", { href: "#proof" }, "Evidence"),
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
          h("p", { className: "eyebrow" }, "Interactive Cover Letter • Full Stack Developer Intern"),
          h(
            "h1",
            null,
            "I want to help Jeweler Studio build",
            h("span", null, " elegant software for a fast-moving luxury product.")
          ),
          h(
            "p",
            { className: "lede" },
            "I am an Information Technology student at Missouri State University with hands-on experience in JavaScript, React, Python, systems work, and AI-assisted tooling. The role stands out because it combines product speed, full-stack breadth, and real AI infrastructure work."
          ),
          h(
            "div",
            { className: "action-row" },
            h("a", { className: "button button-primary", href: "#fit" }, "Review My Fit"),
            h("a", { className: "button button-secondary", href: "mailto:robin413@protonmail.com" }, "robin413@protonmail.com")
          ),
          h(
            "div",
            { className: "signal-grid", "aria-label": "Quick qualifications" },
            h("article", { className: "signal-card" }, h("strong", null, "B.S. Information Technology"), h("span", null, "Missouri State University, expected May 2027")),
            h("article", { className: "signal-card" }, h("strong", null, "React, JavaScript, TypeScript, Python"), h("span", null, "Comfortable across frontend work and technical tooling")),
            h("article", { className: "signal-card" }, h("strong", null, "CompTIA A+ and Network+"), h("span", null, "Systems awareness that complements software work"))
          )
        ),
        h(
          "aside",
          { className: "hero-panel" },
          h("div", { className: "panel-head" }, h("div", null, h("p", { className: "mini-label" }, "Fit Snapshot"), h("h2", null, "Why this role is a strong match"))),
          h(
            "div",
            { className: "score-grid" },
            h("article", { className: "score-card" }, h("span", { className: "score-value" }, "Full stack"), h("strong", null, "Relevant technical base"), h("span", null, "React, JavaScript, TypeScript, Python, SQL, Bash, Linux")),
            h("article", { className: "score-card" }, h("span", { className: "score-value" }, "AI-ready"), h("strong", null, "Practical curiosity"), h("span", null, "Already using AI tools in technical problem-solving")),
            h("article", { className: "score-card" }, h("span", { className: "score-value" }, "Builder"), h("strong", null, "Project-driven learning"), h("span", null, "Language tooling, systems projects, hardware experimentation")),
            h("article", { className: "score-card" }, h("span", { className: "score-value" }, "Professional"), h("strong", null, "Shared-codebase habits"), h("span", null, "Open-source maintenance, pull requests, deadline discipline"))
          ),
          h(
            "div",
            { className: "note-box" },
            h("p", { className: "note-label" }, "Why Jeweler Studio"),
            h(
              "p",
              null,
              "Luxury retail is a distinctive setting, but the technical challenge is what draws me in: embedded design tools, fast iteration, and AI-enabled engineering applied to a real commercial product."
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
          h("div", null, h("p", { className: "eyebrow" }, "Role Fit"), h("h2", null, "Where I can contribute quickly")),
          h("p", null, "This section maps your posting to the parts of my background that are most relevant.")
        ),
        h(
          "div",
          { className: "focus-grid" },
          h(
            "div",
            { className: "tab-list", role: "tablist", "aria-label": "Role fit areas" },
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
            { className: "focus-panel" },
            h("p", { className: "kicker" }, activeFitItem.kicker),
            h("h3", null, activeFitItem.title),
            h("p", { className: "lede" }, activeFitItem.summary),
            h(
              "div",
              { className: "metric-row" },
              activeFitItem.metrics.map((metric) =>
                h(
                  "div",
                  { className: "focus-point metric-copy", key: metric.label },
                  h("strong", null, metric.value),
                  h("p", null, metric.label),
                  h("p", null, metric.note)
                )
              )
            ),
            listItems(activeFitItem.bullets, "bullet-list"),
            tagItems(activeFitItem.tags)
          )
        )
      ),
      h(
        "section",
        { className: "section reveal", id: "proof" },
        h(
          "div",
          { className: "section-head" },
          h("div", null, h("p", { className: "eyebrow" }, "Evidence"), h("h2", null, "Resume details with direct internship relevance")),
          h("p", null, "Selected examples that best support this application.")
        ),
        h(
          "div",
          { className: "artifact-grid" },
          h(
            "div",
            { className: "artifact-stack" },
            projectItems.map((project) =>
              h(
                "button",
                {
                  key: project.id,
                  className: `artifact-button ${project.id === activeProject ? "is-active" : ""}`,
                  onClick: () => setActiveProject(project.id)
                },
                h("strong", null, project.name),
                h("span", null, project.type)
              )
            )
          ),
          h(
            "article",
            { className: "artifact-panel" },
            h("p", { className: "kicker" }, activeProjectItem.type),
            h("h3", null, activeProjectItem.name),
            h("p", null, activeProjectItem.summary),
            tagItems(activeProjectItem.tags),
            h(
              "div",
              { className: "artifact-columns" },
              h("div", null, h("p", { className: "mini-label" }, "What it shows"), listItems(activeProjectItem.signals, "bullet-list")),
              h("div", null, h("p", { className: "mini-label" }, "Why it matters here"), listItems(activeProjectItem.relevance, "bullet-list"))
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
          h("h2", null, "I would be ready to contribute, learn quickly, and raise my level inside a real product team."),
          h(
            "p",
            { className: "lede" },
            "Jeweler Studio’s combination of AI infrastructure, customer-facing product work, and startup intensity is exactly the environment I want for my next stage of growth. I would welcome the chance to discuss how I could support the team as a Full Stack Developer Intern."
          ),
          h(
            "div",
            { className: "contact-row" },
            h("a", { className: "contact-pill", href: "mailto:robin413@protonmail.com" }, "robin413@protonmail.com"),
            h("a", { className: "contact-pill", href: "https://github.com/robinpie", target: "_blank", rel: "noreferrer" }, "github.com/robinpie"),
            h("span", { className: "contact-pill" }, "Springfield, MO")
          )
        )
      )
    )
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(h(App));

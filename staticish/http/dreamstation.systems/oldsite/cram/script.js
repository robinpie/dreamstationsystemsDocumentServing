const { useEffect, useState } = React;
const h = React.createElement;

const fitItems = [
  {
    id: "startup",
    tab: "Startup execution",
    blurb: "Real features, direct founder collaboration, fast iteration.",
    kicker: "Hands-on work",
    title: "I want an internship where the work is real and the feedback loop is short.",
    summary:
      "The strongest part of this posting is that it is explicit about shipping production code instead of observing from the sidelines. That is exactly the kind of internship I want. I learn fastest when I can build, test, ship, and respond to user needs in a real product environment.",
    metrics: [
      { label: "Builder fit", value: "High", note: "Project-driven and implementation-focused" },
      { label: "Startup pace", value: "Good", note: "Comfortable with ambiguity and evolving scope" },
      { label: "Ownership", value: "Ready", note: "Motivated by real responsibility" }
    ],
    bullets: [
      "I prefer internships with visible outcomes and real product stakes.",
      "Direct collaboration with a founder is appealing because it shortens the loop between ideas and execution.",
      "That startup environment matches how I like to learn."
    ],
    tags: ["Startup", "Feature shipping", "Ownership", "User-driven work"]
  },
  {
    id: "fullstack",
    tab: "Full-stack fit",
    blurb: "React, TypeScript, APIs, and practical backend range.",
    kicker: "Across the stack",
    title: "I can contribute on the frontend while thinking beyond it.",
    summary:
      "The role spans React or Next.js, backend APIs, PostgreSQL, and deployment tools like Vercel and Supabase. My background in JavaScript, TypeScript, React, Python, SQL, Linux, and Git fits that well. I am comfortable moving between interface work and the logic behind it.",
    metrics: [
      { label: "Frontend", value: "Strong", note: "React, JavaScript, TypeScript" },
      { label: "Backend", value: "Capable", note: "Python, SQL, scripting, API reasoning" },
      { label: "Tooling", value: "Useful", note: "Git, Linux, practical debugging habits" }
    ],
    bullets: [
      "I can help build UI while still reasoning about data flow and application behavior.",
      "A broad stack is appealing to me because I like learning through real cross-layer work.",
      "That range is a good fit for a small product team."
    ],
    tags: ["React", "TypeScript", "APIs", "SQL"]
  },
  {
    id: "ai",
    tab: "AI-assisted development",
    blurb: "Comfortable using AI tools to move faster without losing judgment.",
    kicker: "AI in the workflow",
    title: "The AI-assisted development angle is a direct match for how I like to work.",
    summary:
      "Your posting treats AI coding tools as part of normal workflow rather than as a side experiment. That stands out. I already use AI tools in technical projects and I am interested in developing stronger habits around integrating AI into day-to-day software development responsibly and efficiently.",
    metrics: [
      { label: "LLM usage", value: "Active", note: "Already using AI tools in technical work" },
      { label: "Workflow fit", value: "Strong", note: "Interested in faster iteration with judgment" },
      { label: "Product tie-in", value: "Useful", note: "OpenAI integration is especially relevant" }
    ],
    bullets: [
      "I see AI tools as accelerators for engineering work, not replacements for reasoning.",
      "That fits well with a startup focused on speed and practical outcomes.",
      "The OpenAI integration side of the role is especially interesting to me."
    ],
    tags: ["AI coding tools", "OpenAI", "Iteration speed", "Technical judgment"]
  },
  {
    id: "student",
    tab: "Product motivation",
    blurb: "Building for real student pain points is compelling.",
    kicker: "Why Cram",
    title: "A student-focused product makes the engineering work more compelling.",
    summary:
      "The company focus matters here. AI study tools for college students are a clear product category with obvious user pain points, and the posting makes it clear that feature planning comes from real feedback. That is the kind of product loop I want exposure to: technical work tied directly to what users actually need.",
    metrics: [
      { label: "User focus", value: "Clear", note: "Customer-driven product thinking" },
      { label: "Motivation", value: "High", note: "Useful software is more interesting to build" },
      { label: "Intern fit", value: "Strong", note: "Good mix of mentorship and ownership" }
    ],
    bullets: [
      "I like software work best when it solves a concrete user problem.",
      "Student-facing tools are a strong context for fast feedback and iteration.",
      "That makes this internship feel substantive rather than performative."
    ],
    tags: ["Student product", "User feedback", "Product decisions", "Mentorship"]
  }
];

const proofItems = [
  {
    id: "ath",
    name: "!~ATH",
    type: "Deep implementation",
    summary:
      "I designed and built a custom programming language with a lexer, parser, and interpreters in Python and JavaScript.",
    signals: [
      "Strong decomposition of complex technical problems.",
      "Ability to move from abstract ideas to working systems.",
      "Persistence with debugging and edge cases."
    ],
    relevance: [
      "Supports the case that I can own nontrivial implementation work.",
      "Useful for backend logic and product feature development.",
      "Shows I learn by building rather than staying theoretical."
    ],
    tags: ["Python", "JavaScript", "Interpreters", "Architecture"]
  },
  {
    id: "homelab",
    name: "Homelab networking",
    type: "Systems + AI tooling",
    summary:
      "I configured a segmented home network, used Wazuh for logging, and wrote Python scripts with AI assistance to parse unsupported logs.",
    signals: [
      "Comfort with systems, tooling, and practical debugging.",
      "Evidence that I already use AI inside technical workflows.",
      "Bias toward building useful solutions around imperfect systems."
    ],
    relevance: [
      "Supports the AI-assisted development side of the role.",
      "Makes me more useful when product issues span multiple layers.",
      "Shows initiative and self-direction."
    ],
    tags: ["Python", "Wazuh", "Automation", "AI-assisted workflow"]
  },
  {
    id: "oss",
    name: "Open-source maintenance",
    type: "Shared codebases",
    summary:
      "I maintain several Arch User Repository packages and have contributed pull requests to other projects.",
    signals: [
      "Comfortable working inside shared conventions and version-control workflows.",
      "Experience reading and modifying other people’s code.",
      "Used to iterative improvement rather than one-off solo work."
    ],
    relevance: [
      "Directly relevant to a small team shipping production code.",
      "Supports collaboration and maintainability.",
      "Good signal for remote contribution habits."
    ],
    tags: ["Git", "GitHub", "Maintenance", "Collaboration"]
  },
  {
    id: "xcaca",
    name: "Xcaca",
    type: "Creative systems work",
    summary:
      "I worked on an X server that renders graphical output as ASCII art, which required understanding complex systems deeply enough to reinterpret them.",
    signals: [
      "Comfort in unusual technical terrain.",
      "Creative problem solving under constraints.",
      "Willingness to explore beyond standard coursework."
    ],
    relevance: [
      "Useful in early-stage startups where technical problems are rarely tidy.",
      "Supports the argument that I can learn quickly and adapt.",
      "Reinforces a builder mindset."
    ],
    tags: ["C", "Linux", "Systems", "Problem solving"]
  }
];

const gainItems = [
  {
    label: "Real users",
    title: "Production code with visible impact",
    text: "The strongest internships are the ones where shipped work reaches actual users and creates an immediate learning loop."
  },
  {
    label: "Mentorship",
    title: "Direct founder collaboration",
    text: "Working closely with a founder should accelerate product judgment as much as technical growth."
  },
  {
    label: "Workflow",
    title: "Hands-on AI-assisted development",
    text: "This role offers the chance to sharpen practical engineering habits around modern AI tooling."
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
  const [activeFit, setActiveFit] = useState("startup");
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
      h("a", { className: "brand", href: "#top" }, "Robin Reel // Cram"),
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
          h("p", { className: "eyebrow" }, "Interactive Cover Letter • Software Developer Intern"),
          h(
            "h1",
            null,
            "I want to help Cram ship",
            h("span", null, " useful AI study tools for real students.")
          ),
          h(
            "p",
            { className: "lede" },
            "I am an Information Technology student with hands-on experience in JavaScript, TypeScript, React, Python, SQL, Git, Linux, and AI-assisted technical workflows. This internship stands out because it combines real product ownership, startup speed, and direct work on software that students actually use."
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
            h("article", { className: "quick-card" }, h("strong", null, "React, TypeScript, JavaScript"), h("span", null, "Useful base for frontend and product work")),
            h("article", { className: "quick-card" }, h("strong", null, "Python, SQL, Linux, Git"), h("span", null, "Practical backend and tooling range")),
            h("article", { className: "quick-card" }, h("strong", null, "AI-assisted workflow"), h("span", null, "Already comfortable using AI tools in technical work"))
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
            h("article", { className: "score-card" }, h("strong", null, "Production work"), h("span", null, "Real features, real users, real iteration")),
            h("article", { className: "score-card" }, h("strong", null, "Startup fit"), h("span", null, "Comfortable with ambiguity and rapid feedback loops")),
            h("article", { className: "score-card" }, h("strong", null, "Full-stack range"), h("span", null, "Frontend comfort with backend awareness")),
            h("article", { className: "score-card" }, h("strong", null, "AI readiness"), h("span", null, "Comfortable using AI tools to accelerate development"))
          ),
          h(
            "div",
            { className: "status-card" },
            h("p", { className: "label" }, "What stands out"),
            h(
              "p",
              null,
              "The posting is unusually clear that interns will write production code instead of sitting on the sidelines. That alone makes the role more compelling than a typical internship."
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
          h("p", { className: "section-note" }, "My fit is strongest where startup execution, practical full-stack work, and AI-assisted development overlap.")
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
          h("p", { className: "section-note" }, "These examples show the implementation depth, self-direction, and collaboration habits I would bring to an early-stage team.")
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
          h("div", null, h("p", { className: "eyebrow" }, "Why This Role"), h("h2", null, "What makes this internship worth pursuing")),
          h("p", { className: "section-note" }, "The role offers the combination I care about most: meaningful shipping, strong learning velocity, and real product context.")
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
          h("h2", null, "I would be ready to contribute quickly and grow fast inside a product team that ships."),
          h(
            "p",
            { className: "lede" },
            "Cram’s combination of startup ownership, AI-assisted development, and student-centered product work is exactly the kind of environment I want for my next stage of growth. I would welcome the chance to discuss how I could contribute as a Software Developer Intern."
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

const { useEffect, useState } = React;
const h = React.createElement;

const fitItems = [
  {
    id: "unconventional",
    tab: "Unconventional fit",
    blurb: "Not the standard DEI pipeline, but useful for the work.",
    kicker: "Why my background still fits",
    title: "My unconventional background is part of why I would bring something valuable to this role.",
    summary:
      "I am not coming from a typical people-operations or communications track. I am an Information Technology student whose background includes public-facing work, independent projects, and experience explaining complex things clearly. For a DEI&B internship centered on coordination, engagement, communication, and follow-through, that difference is not a weakness. It gives me a perspective shaped by both technical problem solving and direct interaction with people.",
    metrics: [
      { label: "Perspective", value: "Different", note: "A nonstandard route into people-and-culture work" },
      { label: "Communication", value: "Strong", note: "Comfortable explaining clearly and directly" },
      { label: "Motivation", value: "Real", note: "Genuine interest rather than résumé padding" }
    ],
    bullets: [
      "I would not approach this work as a checkbox exercise.",
      "Coming from outside the usual pipeline makes me more attentive to how inclusion feels in practice.",
      "That perspective can be useful in employee engagement and internal culture work."
    ],
    tags: ["Nontraditional path", "Fresh perspective", "Communication", "Intentionality"]
  },
  {
    id: "people",
    tab: "People-facing strengths",
    blurb: "Direct communication, outreach, and relationship-building.",
    kicker: "Human skills",
    title: "Public-facing work taught me habits that translate well to DEI&B work.",
    summary:
      "My work gathering signatures for a ballot initiative required me to approach strangers, explain issues clearly, listen well, and stay composed while working toward a concrete goal on a deadline. That is not the same as DEI&B work, but it is highly relevant to building trust, communicating across differences, and staying organized in people-centered environments.",
    metrics: [
      { label: "Outreach", value: "Real", note: "Experienced initiating conversations with many people" },
      { label: "Composure", value: "Reliable", note: "Comfortable in public-facing situations" },
      { label: "Deadline sense", value: "Strong", note: "Used to work with visible targets" }
    ],
    bullets: [
      "I know how to communicate with clarity instead of hiding behind jargon.",
      "I understand that tone, trust, and follow-through matter in people work.",
      "Those habits would help when supporting ERGs, committees, and internal initiatives."
    ],
    tags: ["Public-facing work", "Trust", "Listening", "Clear communication"]
  },
  {
    id: "execution",
    tab: "Execution and organization",
    blurb: "Calendars, coordination, campaigns, and follow-through.",
    kicker: "Operational fit",
    title: "I can bring practical execution discipline to a collaborative team.",
    summary:
      "This role is not only about values. It is also about keeping campaigns moving, maintaining pages and calendars, gathering data, and coordinating across multiple groups. My project work and open-source maintenance reflect a strong bias toward keeping things organized, understanding moving parts, and staying accountable for details.",
    metrics: [
      { label: "Organization", value: "Strong", note: "Comfortable managing many moving parts" },
      { label: "Independence", value: "High", note: "Used to self-directed work in remote settings" },
      { label: "Reliability", value: "Good", note: "Follow-through matters to me" }
    ],
    bullets: [
      "I am comfortable maintaining systems, schedules, and recurring responsibilities.",
      "The mix of campaign support, page maintenance, and data collection is a good fit for me.",
      "I like work that requires both care and consistency."
    ],
    tags: ["Coordination", "Calendars", "Detail orientation", "Remote work"]
  },
  {
    id: "values",
    tab: "Values and learning",
    blurb: "Care, humility, and willingness to grow.",
    kicker: "Why OneDigital",
    title: "The posting’s emphasis on heart work is exactly the right framing.",
    summary:
      "I appreciate that OneDigital explicitly encourages people to apply even if they do not fit every conventional requirement. That suggests a team that understands growth, humility, and inclusion in a practical way. I would bring curiosity, respect, and a willingness to learn quickly while contributing sincerely to work that helps people feel more included and supported.",
    metrics: [
      { label: "Learner mindset", value: "Strong", note: "Comfortable growing into unfamiliar work" },
      { label: "Humility", value: "Real", note: "I am not pretending to know everything already" },
      { label: "Commitment", value: "Genuine", note: "Interested in the work itself, not just the title" }
    ],
    bullets: [
      "I would come into this role ready to listen, contribute, and improve.",
      "The team-first and mentor-based parts of the internship are especially appealing to me.",
      "That is the kind of environment where I think I would do strong work."
    ],
    tags: ["Continuous learner", "Inclusive leadership", "Humility", "Mentorship"]
  }
];

const proofItems = [
  {
    id: "ballot",
    name: "Ballot initiative outreach",
    type: "Public-facing communication",
    summary:
      "I gathered signatures for a ballot initiative, which required approaching community members, explaining issues clearly, and working toward hard collection goals under deadline pressure.",
    signals: [
      "Comfort initiating conversations and meeting people where they are.",
      "Strong practical communication skills in unscripted situations.",
      "Able to stay organized and focused while working with many moving parts."
    ],
    relevance: [
      "Directly relevant to culture work that depends on trust and clear communication.",
      "Supports collaboration with ERGs, committees, and other internal partners.",
      "Shows I can represent an initiative thoughtfully and consistently."
    ],
    tags: ["Outreach", "Communication", "Deadlines", "People work"]
  },
  {
    id: "oss",
    name: "Open-source maintenance",
    type: "Coordination and stewardship",
    summary:
      "I maintain several Arch User Repository packages and have contributed pull requests to other projects.",
    signals: [
      "Comfort taking care of ongoing responsibilities rather than one-time tasks.",
      "Understands the value of consistency, documentation, and maintenance.",
      "Used to collaborative workflows that require accountability."
    ],
    relevance: [
      "Supports the operational side of maintaining pages, calendars, and recurring campaigns.",
      "Shows that I can keep shared systems healthy over time.",
      "Reinforces reliability in collaborative environments."
    ],
    tags: ["Maintenance", "Consistency", "Documentation", "Shared ownership"]
  },
  {
    id: "ath",
    name: "!~ATH",
    type: "Initiative and self-direction",
    summary:
      "I built a custom programming language with interpreters in Python and JavaScript, which required sustained independent work and problem solving.",
    signals: [
      "High degree of initiative and self-direction.",
      "Comfort learning without waiting to be told every next step.",
      "Persistence through ambiguity and complexity."
    ],
    relevance: [
      "Useful in a remote-first environment where independence matters.",
      "Supports the self-starter part of the role even outside a people-focused context.",
      "Shows that I can own projects responsibly."
    ],
    tags: ["Initiative", "Independence", "Problem solving", "Follow-through"]
  },
  {
    id: "service",
    name: "Customer-service work",
    type: "Professional presence",
    summary:
      "My food-service roles required punctuality, patience, and steady communication in fast-paced public settings.",
    signals: [
      "Comfort working with a wide range of people respectfully.",
      "Understands professionalism in everyday interactions.",
      "Able to stay composed in active, high-contact environments."
    ],
    relevance: [
      "Relevant to supporting inclusive engagement across different personalities and groups.",
      "Supports the interpersonal side of employee-focused work.",
      "Helps explain why I take people-facing professionalism seriously."
    ],
    tags: ["Professionalism", "Patience", "People skills", "Dependability"]
  }
];

const gainItems = [
  {
    label: "Visibility",
    title: "High-trust, high-impact culture work",
    text: "This internship offers the chance to contribute to initiatives that shape how people experience the organization day to day."
  },
  {
    label: "Growth",
    title: "Mentorship with real responsibility",
    text: "The combination of assigned mentorship and visible projects is the kind of structure where I tend to grow fastest."
  },
  {
    label: "Perspective",
    title: "A place where nontraditional applicants are welcomed",
    text: "The application language itself suggests a team that understands potential, not only conventional fit."
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
  const [activeFit, setActiveFit] = useState("unconventional");
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
      h("a", { className: "brand", href: "#top" }, "Robin Reel // OneDigital"),
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
          h("p", { className: "eyebrow" }, "Interactive Cover Letter • DEI&B JUMPSTART Internship"),
          h(
            "h1",
            null,
            "My background is unconventional for this role,",
            h("span", null, " and that is part of why I think I fit it.")
          ),
          h(
            "p",
            { className: "lede" },
            "I am an Information Technology student, not a typical people-and-culture applicant. But my background includes public-facing work, communication under pressure, self-directed projects, and a serious interest in how people experience organizations. For a DEI&B internship centered on coordination, engagement, and inclusive culture-building, that different path can be an asset rather than a mismatch."
          ),
          h(
            "div",
            { className: "action-row" },
            h("a", { className: "button button-primary", href: "#fit" }, "See My Case"),
            h("a", { className: "button button-secondary mono", href: "mailto:robin413@protonmail.com" }, "robin413@protonmail.com")
          ),
          h(
            "div",
            { className: "quick-grid", "aria-label": "Quick qualifications" },
            h("article", { className: "quick-card" }, h("strong", null, "Public-facing communication"), h("span", null, "Comfortable engaging people directly and clearly")),
            h("article", { className: "quick-card" }, h("strong", null, "Independent execution"), h("span", null, "Strong follow-through in remote and self-directed work")),
            h("article", { className: "quick-card" }, h("strong", null, "Nontraditional perspective"), h("span", null, "A different route into people-centered work"))
          )
        ),
        h(
          "aside",
          { className: "hero-panel" },
          h("p", { className: "label" }, "Role Snapshot"),
          h("h2", null, "Why this opportunity is compelling"),
          h(
            "div",
            { className: "score-grid" },
            h("article", { className: "score-card" }, h("strong", null, "Culture work"), h("span", null, "Employee engagement, inclusion, and belonging")),
            h("article", { className: "score-card" }, h("strong", null, "Collaboration"), h("span", null, "Partnership with ERGs, communications, and committees")),
            h("article", { className: "score-card" }, h("strong", null, "Execution"), h("span", null, "Campaigns, calendars, pages, and reporting")),
            h("article", { className: "score-card" }, h("strong", null, "Mentorship"), h("span", null, "A cohort experience with visible project work"))
          ),
          h(
            "div",
            { className: "status-card" },
            h("p", { className: "label" }, "What stands out"),
            h(
              "p",
              null,
              "The posting explicitly says to apply even if not every requirement feels like a perfect match. That matters, and it is a large part of why I think my unconventional background belongs in the conversation."
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
          h("div", null, h("p", { className: "eyebrow" }, "Role Fit"), h("h2", null, "Why a nontraditional applicant can still be the right fit")),
          h("p", { className: "section-note" }, "My argument is not that I match the role in the usual way. It is that the strengths I do have line up well with what the work actually requires.")
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
          h("div", null, h("p", { className: "eyebrow" }, "Evidence"), h("h2", null, "What in my background actually supports this application")),
          h("p", { className: "section-note" }, "The strongest evidence is not a conventional DEI résumé line. It is a set of experiences that show communication, steadiness, and follow-through.")
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
          h("p", { className: "section-note" }, "The role offers the combination I value most here: meaningful people work, collaboration, and structured growth.")
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
          h("h2", null, "I would bring curiosity, discipline, and a genuinely different perspective to this team."),
          h(
            "p",
            { className: "lede" },
            "I understand that my background is not the most conventional match for a DEI&B internship. I also think that is part of what makes me worth considering. I would bring strong communication, dependable execution, a willingness to learn, and sincere interest in the work of helping people feel included, informed, and supported at OneDigital."
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

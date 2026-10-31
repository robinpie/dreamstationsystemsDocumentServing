const stageContent = {
  design: {
    kicker: "Architecture and problem framing",
    title: "I am comfortable reasoning about systems before I start coding.",
    text: "Projects like building a programming language or an ASCII X server only work if I first break the problem into layers, interfaces, and constraints.",
    points: [
      "I naturally think in terms of components, flows, and failure cases.",
      "That makes architecture discussions interesting rather than intimidating.",
      "It fits a role that includes design conversations instead of only implementation."
    ]
  },
  build: {
    kicker: "Implementation discipline",
    title: "I like turning abstract requirements into working software.",
    text: "My project history is proof that I do not stop at concepts. I build interpreters, Linux tooling, hardware-facing scripts, and frontend work that actually runs.",
    points: [
      "Comfortable across backend-style logic and frontend technologies.",
      "Experience spans JavaScript, TypeScript, React, Python, Java, C, C++, and Bash.",
      "That range is useful in an internship that expects full-stack participation."
    ]
  },
  test: {
    kicker: "Quality mindset",
    title: "I care about regressions because software only matters if it keeps working.",
    text: "STARZ’s emphasis on test automation and modern practices is part of the appeal. I want to keep leveling up in structured validation, not just feature delivery.",
    points: [
      "My systems projects forced careful debugging and edge-case awareness.",
      "Open-source work reinforced the importance of compatibility and maintainability.",
      "I would bring seriousness about quality even while still growing formal test practice."
    ]
  },
  ship: {
    kicker: "Operations awareness",
    title: "I want stronger production exposure, not just more code exposure.",
    text: "CI/CD, deployment, monitoring, and observability are explicitly part of this internship. That is valuable because it connects code to the reality of serving users reliably.",
    points: [
      "My infrastructure background makes those concerns feel natural rather than separate.",
      "I am motivated by the full pipeline from commit to customer impact.",
      "That makes STARZ a stronger fit than internships limited to isolated coding tasks."
    ]
  }
};

const projectContent = {
  ath: {
    title: "!~ATH Programming Language",
    summary:
      "This project is strong evidence that I can work on backend-style logic and reason about interfaces, execution flow, and edge cases.",
    tags: ["Python", "JavaScript", "Parsing", "Runtime Logic", "Design"],
    signals: [
      "Built a lexer, parser, and interpreters rather than only surface-level app code.",
      "Worked through language semantics and runtime behavior in detail.",
      "Shows patience for complexity and comfort with technical ambiguity."
    ],
    relevance: [
      "Maps well to server-side problem solving and API-oriented thinking.",
      "Supports the internship requirement for backend language experience, even before direct C# experience.",
      "Shows I can handle logic-heavy engineering work with discipline."
    ]
  },
  xcaca: {
    title: "Xcaca",
    summary:
      "An ASCII-art X server is unconventional, but that is exactly why it is persuasive: it demonstrates a willingness to learn difficult systems deeply enough to build against them.",
    tags: ["C", "Systems", "Graphics", "Protocols", "Linux"],
    signals: [
      "Comfortable entering unfamiliar technical areas and making them tractable.",
      "Strong systems-thinking habits and creative implementation ability.",
      "Evidence that I enjoy working below the surface of typical application code."
    ],
    relevance: [
      "Useful in a role that includes architecture discussion and deeper platform thinking.",
      "Signals I can learn production technologies quickly when the concepts are demanding.",
      "Supports collaboration with engineers who care about underlying system behavior."
    ]
  },
  terminal: {
    title: "Receipt Printer Terminal",
    summary:
      "This project combined operating-system knowledge, scripting, and hardware experimentation in a way that feels very aligned with hands-on engineering.",
    tags: ["Bash", "Linux", "Hardware", "Automation", "Tooling"],
    signals: [
      "Comfortable with practical debugging and awkward real-world constraints.",
      "Shows initiative in building something tangible instead of theoretical.",
      "Reflects the systems instincts that make DevOps-adjacent learning easier."
    ],
    relevance: [
      "Useful for deployment and monitoring contexts where environments matter.",
      "Suggests I can contribute beyond narrow feature coding when infrastructure details matter.",
      "Matches STARZ’s full-lifecycle internship structure well."
    ]
  },
  oss: {
    title: "Open Source Contributions",
    summary:
      "Contributing to code I did not originate matters because professional software development is mostly about shared ownership, not isolated invention.",
    tags: ["Git", "Maintenance", "Packaging", "Reviews", "Collaboration"],
    signals: [
      "Reads existing code and adapts to project conventions.",
      "Understands maintenance, compatibility, and long-term quality concerns.",
      "Shows comfort with iterative improvement in public or shared environments."
    ],
    relevance: [
      "Directly supports code reviews, collaboration, and modern engineering practice.",
      "Makes me a better fit for a mentored team environment with multiple stakeholders.",
      "Signals I can contribute productively in codebases that already have standards."
    ]
  }
};

const consoleMessages = [
  "> internship_mode: end-to-end engineering, not observation-only",
  "> best_fit: product software + systems thinking + modern delivery practices",
  "> strongest_signal: broad builder with unusual projects and strong curiosity",
  "> growth_target: production C#, test automation, CI/CD, observability"
];

const stageTabs = Array.from(document.querySelectorAll(".production-tab"));
const stageKicker = document.getElementById("stageKicker");
const stageTitle = document.getElementById("stageTitle");
const stageText = document.getElementById("stageText");
const stagePoints = document.getElementById("stagePoints");

const evidenceCards = Array.from(document.querySelectorAll(".evidence-card"));
const projectTitle = document.getElementById("projectTitle");
const projectSummary = document.getElementById("projectSummary");
const projectTags = document.getElementById("projectTags");
const projectSignals = document.getElementById("projectSignals");
const projectRelevance = document.getElementById("projectRelevance");
const consoleBody = document.getElementById("consoleBody");

function renderList(element, items) {
  element.innerHTML = "";

  items.forEach((item) => {
    const listItem = document.createElement("li");
    listItem.textContent = item;
    element.appendChild(listItem);
  });
}

function setStagePanel(key) {
  const data = stageContent[key];

  stageKicker.textContent = data.kicker;
  stageTitle.textContent = data.title;
  stageText.textContent = data.text;
  renderList(stagePoints, data.points);

  stageTabs.forEach((tab) => {
    const isActive = tab.dataset.stage === key;
    tab.classList.toggle("is-active", isActive);
    tab.setAttribute("aria-selected", String(isActive));
  });
}

function setProjectPanel(key) {
  const data = projectContent[key];

  projectTitle.textContent = data.title;
  projectSummary.textContent = data.summary;
  projectTags.innerHTML = "";

  data.tags.forEach((tag) => {
    const badge = document.createElement("span");
    badge.textContent = tag;
    projectTags.appendChild(badge);
  });

  renderList(projectSignals, data.signals);
  renderList(projectRelevance, data.relevance);

  evidenceCards.forEach((card) => {
    const isActive = card.dataset.project === key;
    card.classList.toggle("is-active", isActive);
  });
}

function playConsoleMessages() {
  let currentIndex = 0;
  consoleBody.textContent = "";

  const writeNext = () => {
    if (currentIndex >= consoleMessages.length) {
      return;
    }

    consoleBody.textContent += `${consoleMessages[currentIndex]}\n`;
    currentIndex += 1;
    window.setTimeout(writeNext, 720);
  };

  writeNext();
}

function setupRevealAnimations() {
  const revealTargets = Array.from(document.querySelectorAll("section, .hero-strip li"));
  revealTargets.forEach((target) => target.classList.add("reveal"));

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
}

function setupPointerGlow() {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    return;
  }

  window.addEventListener("pointermove", (event) => {
    const x = `${(event.clientX / window.innerWidth) * 100}%`;
    const y = `${(event.clientY / window.innerHeight) * 100}%`;
    document.documentElement.style.setProperty("--pointer-x", x);
    document.documentElement.style.setProperty("--pointer-y", y);
  });
}

stageTabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    setStagePanel(tab.dataset.stage);
  });
});

evidenceCards.forEach((card) => {
  card.addEventListener("click", () => {
    setProjectPanel(card.dataset.project);
  });
});

setStagePanel("design");
setProjectPanel("ath");
playConsoleMessages();
setupRevealAnimations();
setupPointerGlow();

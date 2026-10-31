const fitContent = {
  builder: {
    kicker: "Hands-on execution",
    title: "I like owning real technical work, not just talking about it.",
    text: "My projects are concrete: language tooling, graphical systems experiments, Bash automation, and hardware integration. I enjoy moving from concept to working implementation and debugging through ambiguity.",
    points: [
      "Built interpreters and parsing logic instead of staying at the idea stage.",
      "Comfortable learning by making, testing, breaking, and refining.",
      "Motivated by visible product progress and shipping working features."
    ]
  },
  systems: {
    kicker: "Infrastructure instinct",
    title: "I think beyond the UI and care how software behaves as a system.",
    text: "My background in IT infrastructure and certifications gives me a practical perspective on reliability, operating environments, networking, and the messy edges where software meets reality.",
    points: [
      "CompTIA A+ and Network+ support a strong baseline in systems thinking.",
      "Linux-heavy projects developed comfort with tooling, scripts, and environments.",
      "That perspective helps when collaborating with DevOps and test engineering."
    ]
  },
  collaborator: {
    kicker: "Team contribution",
    title: "I work well in shared environments where code quality is social, not solitary.",
    text: "Open-source contributions and public-facing work both taught me to communicate clearly, adapt to expectations, and keep momentum without ego. That matters in distributed teams.",
    points: [
      "Maintained AUR packages and contributed pull requests to other projects.",
      "Used customer-facing roles to develop patience, clarity, and reliability.",
      "Ready to learn through reviews, feedback, and iterative improvement."
    ]
  },
  learner: {
    kicker: "Curiosity with discipline",
    title: "I ramp quickly when the work is difficult and interesting.",
    text: "I am drawn to unfamiliar technical territory, but I do not romanticize chaos. I break problems down, read documentation, and keep moving until the system makes sense.",
    points: [
      "Moved across Python, JavaScript, C, C++, Java, SQL, and Bash as needed.",
      "Built unconventional projects that required self-direction and persistence.",
      "That learning habit fits an internship centered on mentorship and real growth."
    ]
  }
};

const projectContent = {
  ath: {
    title: "!~ATH",
    summary:
      "Designing a programming language from scratch forced me to think carefully about syntax, parsing, runtime behavior, and developer ergonomics.",
    tags: ["Python", "JavaScript", "Parsers", "Interpreters", "Language Design"],
    signals: [
      "Strong problem decomposition across lexer, parser, and interpreter layers.",
      "Ability to translate abstract design decisions into working code.",
      "Persistence through complex debugging and edge-case handling."
    ],
    relevance: [
      "Shows I can handle nontrivial implementation work with real technical depth.",
      "Useful for internship tasks that require ownership and careful reasoning.",
      "Demonstrates the kind of curiosity that grows quickly under mentorship."
    ]
  },
  xcaca: {
    title: "Xcaca",
    summary:
      "Implementing an X server that renders graphics as ASCII art is unusual, but it proves I enjoy understanding existing systems deeply enough to reinterpret them creatively.",
    tags: ["C", "Systems", "Graphics", "Linux", "Legacy Interfaces"],
    signals: [
      "Comfortable exploring complicated technical terrain.",
      "Able to extend existing concepts instead of only building toy apps.",
      "Creative engineering paired with low-level systems focus."
    ],
    relevance: [
      "Useful on teams that value problem solving beyond textbook cases.",
      "Signals comfort with complexity and technical ambiguity.",
      "Supports the idea that I can learn unfamiliar product areas quickly."
    ]
  },
  terminal: {
    title: "Receipt Printer Terminal",
    summary:
      "Repurposing a receipt printer into a hardcopy terminal combined hardware curiosity with Linux scripting and practical experimentation.",
    tags: ["Bash", "Hardware", "Linux", "Automation", "Interfaces"],
    signals: [
      "Shows initiative in turning rough ideas into functioning prototypes.",
      "Blends scripting, device interaction, and operating-system knowledge.",
      "Demonstrates a bias toward building tangible things."
    ],
    relevance: [
      "A good match for teams that value ownership and practical execution.",
      "Supports collaboration with engineers who work across product and infrastructure.",
      "Reinforces that I enjoy solving messy real-world technical problems."
    ]
  },
  oss: {
    title: "AUR + PR Contributions",
    summary:
      "Package maintenance and contributions to other projects taught me to work inside shared conventions rather than only in my own sandbox.",
    tags: ["Git", "Packaging", "Maintenance", "Code Review", "Open Source"],
    signals: [
      "Experience reading code written by others and contributing responsibly.",
      "Understands that maintainability and compatibility matter over time.",
      "Comfortable with iterative improvement in collaborative environments."
    ],
    relevance: [
      "Directly relevant to code review, teamwork, and agile contribution.",
      "Suggests I can slot into an existing engineering culture without friction.",
      "Supports the internship emphasis on mentorship and collaborative delivery."
    ]
  }
};

const consoleMessages = [
  "> mission_match: fintech + human-centered product + measurable social impact",
  "> candidate_signal: broad technical curiosity grounded in real builds",
  "> team_fit: comfortable learning through feedback in shared codebases",
  "> contribution_model: start small, learn fast, own more over time"
];

const fitTabs = Array.from(document.querySelectorAll(".fit-tab"));
const fitKicker = document.getElementById("fitKicker");
const fitTitle = document.getElementById("fitTitle");
const fitText = document.getElementById("fitText");
const fitPoints = document.getElementById("fitPoints");

const projectCards = Array.from(document.querySelectorAll(".project-card"));
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

function setFitPanel(key) {
  const data = fitContent[key];

  fitKicker.textContent = data.kicker;
  fitTitle.textContent = data.title;
  fitText.textContent = data.text;
  renderList(fitPoints, data.points);

  fitTabs.forEach((tab) => {
    const isActive = tab.dataset.fit === key;
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

  projectCards.forEach((card) => {
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

    const nextLine = consoleMessages[currentIndex];
    consoleBody.textContent += `${nextLine}\n`;
    currentIndex += 1;
    window.setTimeout(writeNext, 760);
  };

  writeNext();
}

function setupRevealAnimations() {
  const revealTargets = Array.from(document.querySelectorAll("section, .signal-strip li"));
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
    {
      threshold: 0.14
    }
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

fitTabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    setFitPanel(tab.dataset.fit);
  });
});

projectCards.forEach((card) => {
  card.addEventListener("click", () => {
    setProjectPanel(card.dataset.project);
  });
});

setFitPanel("builder");
setProjectPanel("ath");
playConsoleMessages();
setupRevealAnimations();
setupPointerGlow();

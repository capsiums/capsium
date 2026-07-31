// Loads questions, renders the form, posts answers to the scoring
// handler. Replace with your own UI as needed.
(function () {
  let questions = [];
  init();

  async function init() {
    const res = await fetch("/api/v1/data/questions");
    questions = await res.json();
    render();
  }

  function render() {
    const section = document.getElementById("quiz");
    section.innerHTML = "";
    questions.forEach(function (q, index) {
      const article = document.createElement("article");
      article.className = "question";
      const heading = document.createElement("h3");
      heading.textContent = (index + 1) + ". " + q.text;
      article.appendChild(heading);
      const options = document.createElement("div");
      options.className = "options";
      q.options.forEach(function (opt, i) {
        const label = document.createElement("label");
        const input = document.createElement("input");
        input.type = "radio";
        input.name = q.id;
        input.value = String(i);
        label.appendChild(input);
        label.appendChild(document.createTextNode(" " + opt));
        options.appendChild(label);
      });
      article.appendChild(options);
      section.appendChild(article);
    });
    const submit = document.createElement("button");
    submit.textContent = "Score me";
    submit.addEventListener("click", score);
    section.appendChild(submit);
  }

  async function score() {
    const answers = {};
    questions.forEach(function (q) {
      const picked = document.querySelector('input[name="' + q.id + '"]:checked');
      if (picked) answers[q.id] = parseInt(picked.value, 10);
    });
    const res = await fetch("/api/v1/handler/score", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ answers: answers }),
    });
    const result = await res.json();
    document.getElementById("r-title").textContent = "Score: " + result.score + " / " + result.total;
    document.getElementById("r-body").textContent = result.message || "";
    document.getElementById("result").hidden = false;
  }
})();

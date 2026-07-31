(function () {
  async function load() {
    const res = await fetch("/api/v1/data/projects");
    const projects = await res.json();
    const sorted = projects.slice().sort((a, b) => (a.year < b.year ? 1 : -1));
    const section = document.getElementById("projects");
    section.innerHTML = sorted.map(function (p) {
      const tags = (p.tags || []).map(function (t) {
        return '<span class="tag">' + escapeHtml(t) + "</span>";
      }).join("");
      return '<article class="project"><h3>' + escapeHtml(p.title) + "</h3>" +
             '<p class="meta">' + p.year + " · " + escapeHtml(p.role || "") + "</p>" +
             "<p>" + escapeHtml(p.summary || "") + "</p>" +
             '<p class="tags">' + tags + "</p></article>";
    }).join("");
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  load();
})();

// Renders the sidebar TOC from /api/v1/data/toc, grouped by section.
(function () {
  async function load() {
    try {
      const res = await fetch("/api/v1/data/toc");
      const entries = await res.json();
      render(entries);
    } catch (_err) {
      document.getElementById("sidebar").innerHTML = "<h2>Docs</h2><p>(nav unavailable)</p>";
    }
  }
  function render(entries) {
    const sorted = entries.slice().sort((a, b) =>
      a.section === b.section ? a.order - b.order : a.section.localeCompare(b.section));
    const bySection = new Map();
    for (const e of sorted) {
      if (!bySection.has(e.section)) bySection.set(e.section, []);
      bySection.get(e.section).push(e);
    }
    let html = "";
    for (const [section, items] of bySection) {
      html += "<h3>" + escapeHtml(section) + "</h3>";
      for (const item of items) {
        html += '<a href="' + escapeHtml(item.path) + '">' + escapeHtml(item.title) + "</a>";
      }
    }
    document.getElementById("sidebar").innerHTML = html;
  }
  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  }
  load();
})();

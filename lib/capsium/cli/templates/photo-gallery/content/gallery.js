// Renders a filterable grid from /api/v1/data/photos.
(function () {
  let photos = [];
  init();

  async function init() {
    const res = await fetch("/api/v1/data/photos");
    photos = await res.json();
    render(photos);
    document.getElementById("filter").addEventListener("input", onFilter);
  }

  function onFilter(event) {
    const q = event.target.value.trim().toLowerCase();
    if (!q) return render(photos);
    render(photos.filter(function (p) {
      return (p.title + " " + (p.tags || []).join(" ")).toLowerCase().includes(q);
    }));
  }

  function render(items) {
    const section = document.getElementById("gallery");
    if (!items.length) { section.innerHTML = "<p>No matches.</p>"; return; }
    section.innerHTML = items.map(function (p) {
      const tags = (p.tags || []).join(", ");
      return '<figure><img src="' + esc(p.src) + '" alt="' + esc(p.title) +
             '" loading="lazy" width="' + p.width + '" height="' + p.height + '">' +
             "<figcaption><h3>" + esc(p.title) + "</h3>" +
             '<p class="tags">' + esc(tags) + "</p></figcaption></figure>";
    }).join("");
  }

  function esc(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  }
})();
